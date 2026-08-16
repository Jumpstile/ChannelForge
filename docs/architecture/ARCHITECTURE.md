# Architecture

> Status: Living document

## Purpose

Describe how ChannelForge is structured today, and how that structure enforces the clean layered architecture decided in [ADR 0003](../adr/0003-clean-architecture.md).

## Audience

Developers, maintainers, and technical users who need to know where logic lives before changing it.

## Layers

ChannelForge is organized as a PowerShell module (`src/ChannelForge`) with three conceptual layers.

### Domain layer

Plain data objects with no knowledge of providers, file formats, or output targets.

- [`Channel`](../../src/ChannelForge/Classes/Channel.ps1) — a single channel: identity fields (name, TVG ID, logo, group), classification flags (`IsLocal`, `IsAdult`, `IsRegionalSports`, `IsDuplicate`), and a `Confidence` score with accumulated `Warnings`.
- [`BuildContext`](../../src/ChannelForge/Classes/BuildContext.ps1) — the state of one build run: imported providers, playlists, channels, guide sources, programmes, plus warnings, errors, informational messages, statistics, and output metadata.

### Application / engine layer

Public functions that turn raw input into domain objects, or transform domain objects deterministically. These live in `src/ChannelForge/Public`:

- [`Read-ChannelForgeProvider`](../../src/ChannelForge/Public/Read-ChannelForgeProvider.ps1) — loads `provider.json` and returns one record per configured source.
- [`Read-ChannelForgeEpgSource`](../../src/ChannelForge/Public/Read-ChannelForgeEpgSource.ps1) — loads `epg_sources.json` and returns sources sorted by priority.
- [`Import-ChannelForgeM3UPlaylist`](../../src/ChannelForge/Public/Import-ChannelForgeM3UPlaylist.ps1) — parses a local M3U playlist into `Channel` objects, including the stream URL.
- [`Resolve-ChannelForgeAlias`](../../src/ChannelForge/Public/Resolve-ChannelForgeAlias.ps1) — deterministic, exact-match alias lookup; falls back to the input name when no alias is known.
- [`Set-ChannelForgeChannelNumber`](../../src/ChannelForge/Public/Set-ChannelForgeChannelNumber.ps1) — assigns `AssignedNumber` from `numbering_blocks.json` by exact (case-insensitive) match against a channel's `Group`; leaves a channel unassigned with a warning rather than guessing a category mapping.
- [`Merge-ChannelForgeLineup`](../../src/ChannelForge/Public/Merge-ChannelForgeLineup.ps1) — the Phase 1 end-to-end pipeline (issue #7): parses one or more local playlists in sorted-path order, normalizes, alias-resolves, deduplicates by tvg-id (or display name), numbers, and returns a deterministically ordered channel set plus duplicate/warning counts.
- [`Export-ChannelForgeM3UPlaylist`](../../src/ChannelForge/Public/Export-ChannelForgeM3UPlaylist.ps1) — renders a `Channel[]` to M3U text (`#EXTM3U`/`#EXTINF` with `tvg-id`/`tvg-name`/`tvg-logo`/`tvg-chno`/`group-title`) and writes it with no BOM and a fixed line ending, so the same channel set always produces the same bytes.
- [`Export-ChannelForgeXmltv`](../../src/ChannelForge/Public/Export-ChannelForgeXmltv.ps1) — writes deterministic XMLTV from merged local Programme records; `Build-Lineup.ps1` now wires configured local XMLTV sources into this path, while remote acquisition remains deferred.
- [`New-ChannelForgeChannel`](../../src/ChannelForge/Public/New-ChannelForgeChannel.ps1) / [`New-ChannelForgeBuildContext`](../../src/ChannelForge/Public/New-ChannelForgeBuildContext.ps1) — domain object constructors.
- [`ConvertTo-ChannelForgeNormalizedChannel`](../../src/ChannelForge/Public/ConvertTo-ChannelForgeNormalizedChannel.ps1) — applies normalization to a channel.

Private helpers in `src/ChannelForge/Private` support the application layer without being part of the public surface, e.g. [`Normalize-ChannelForgeName`](../../src/ChannelForge/Private/Normalize-ChannelForgeName.ps1), which strips quality tags and backup/alternate markers from playlist names.

### Infrastructure layer (planned)

File-format and output-target integrations: M3U, XMLTV, JSON, CSV, IPTVBoss, Dispatcharr, the file system, and HTTP. Today this is limited to local file parsing and writing (M3U in, M3U out, XMLTV in, XMLTV out, JSON via `Read-*` functions). HTTP fetch of provider or EPG sources and the IPTVBoss/Dispatcharr/Plex output writers described in the [Roadmap](../../ROADMAP.md), have not been implemented yet — see "Known limitations" below.

Per ADR 0003, domain objects must not reference infrastructure-specific concepts. `Channel` and `BuildContext` have no IPTVBoss-, Dispatcharr-, or Plex-specific fields; provider- and playlist-specific values are stored as plain strings supplied by the infrastructure layer.

### Write guardrails

`scripts/Build-Lineup.ps1` and `scripts/Backup-IPTVBoss.ps1` sit outside the module (they're standalone entry points, not part of the public API) but import it to call `Assert-ChannelForgeWritePath` and `Assert-ChannelForgePathExists` before any filesystem write, copy, or archive operation. This keeps the "what's allowed to write where" decision in one place rather than re-implemented per script. The same principle covers reads of operator-supplied configuration paths: `Assert-ChannelForgeReadPath` confines a resolved `local_playlist` value to `data/playlists/` before `Build-Lineup.ps1` ever opens it. See the [Developer Guide](../developer/DEVELOPER_GUIDE.md#write-guardrails) for the current write/read sites and what each guardrail checks.

## Data flow (current)

```text
provider.json (enabled + optional local_playlist)
        |
        v
  [enabled AND local_playlist set]
        |
        v
Import-ChannelForgeM3UPlaylist -> normalize -> alias -> dedup -> number
        |
        v
Export-ChannelForgeM3UPlaylist  --->  output/merged.m3u


epg_sources.json (enabled local XMLTV path entries)
        |
        v
  [enabled + supported + local XMLTV]
        |
        v
Import-ChannelForgeConfiguredXmltvSource
        |
        v
Merge-ChannelForgeXmltvProgrammes -> guarded staging -> safe promotion
        |
        v
Export-ChannelForgeXmltv  --->  output/merged.xml
```

This is the local-file build pipeline `scripts/Build-Lineup.ps1` runs via `Merge-ChannelForgeLineup` for M3U and the configured XMLTV import/merge/export commands for guide output. The branches remain separate: XMLTV is source-scoped and is not bound to M3U `Channel.TvgId` values. `BuildContext` exists as a domain object but this pipeline does not populate it yet; downstream output writers and Plex guide binding remain future work.

### Known limitations (issue #7 Phase 1)

- **HTTP provider/EPG fetch is deferred.** Local M3U and configured local XMLTV `.xml`, `.gz`, and single-entry `.zip` files are read; remote URL sources are classified as deferred and never dereferenced.
- **Build-Lineup XMLTV integration is local-only and fail-closed.** Import, source-aware deterministic merge, validation, and deterministic export are wired into the build. Malformed input, invalid intervals, conflicts, `NeedsReview`, or export/promotion failures produce a failed XMLTV status, leave the public `merged.xml` path absent, and preserve any prior artifact only in the non-published rollback area.
- **Plex EPG/guide binding remains deferred.** The build can produce `output/merged.xml`, but downstream channel-to-guide binding and automatic Plex refresh are separate work.
- **Category-to-numbering-block matching is intentionally simple.** A channel is numbered only if its M3U `group-title` exactly matches (case-insensitive) a `numbering_blocks.json` category. Smarter category inference is Confidence Engine territory (Roadmap Milestone 2), not this pipeline.

## Source of truth

Provider sources, EPG sources, and rules live in `data/` as declarative JSON/CSV files (see [ADR 0001](../adr/0001-source-of-truth.md)). Generated outputs under `output/` are disposable artifacts, not source data.

Every tracked JSON file under `data/` has a structural contract in `schemas/`, validated with PowerShell's built-in `Test-Json -SchemaFile` (run them all via `scripts/Validate-ConfigSchemas.ps1`). Schemas check shape — required/optional fields and types — not business content; they do not enumerate today's provider names, EPG roles, or categories, and they do not check URL trust-boundary rules, which remain a runtime concern in `Test-ChannelForgeSourceUrl`. See the [Developer Guide](../developer/DEVELOPER_GUIDE.md#configuration-schemas) for the full file-to-schema mapping and how the two validation layers relate.

## Related documents

- [ADR 0001 — ChannelForge owns the source of truth](../adr/0001-source-of-truth.md)
- [ADR 0003 — Use clean layered architecture](../adr/0003-clean-architecture.md)
- [Channel Identity Model](CHANNEL_IDENTITY_MODEL.md)
- [Developer Guide](../developer/DEVELOPER_GUIDE.md)
