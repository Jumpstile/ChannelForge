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
- [`Import-ChannelForgeM3UPlaylist`](../../src/ChannelForge/Public/Import-ChannelForgeM3UPlaylist.ps1) — parses an M3U playlist into `Channel` objects.
- [`Resolve-ChannelForgeAlias`](../../src/ChannelForge/Public/Resolve-ChannelForgeAlias.ps1) — deterministic, exact-match alias lookup; falls back to the input name when no alias is known.
- [`New-ChannelForgeChannel`](../../src/ChannelForge/Public/New-ChannelForgeChannel.ps1) / [`New-ChannelForgeBuildContext`](../../src/ChannelForge/Public/New-ChannelForgeBuildContext.ps1) — domain object constructors.
- [`ConvertTo-ChannelForgeNormalizedChannel`](../../src/ChannelForge/Public/ConvertTo-ChannelForgeNormalizedChannel.ps1) — applies normalization to a channel.

Private helpers in `src/ChannelForge/Private` support the application layer without being part of the public surface, e.g. [`Normalize-ChannelForgeName`](../../src/ChannelForge/Private/Normalize-ChannelForgeName.ps1), which strips quality tags and backup/alternate markers from playlist names.

### Infrastructure layer (planned)

File-format and output-target integrations: M3U, XMLTV, JSON, CSV, IPTVBoss, Dispatcharr, the file system, and HTTP. Today this is limited to local file parsing (M3U, JSON via `Read-*` functions). HTTP fetch of provider or EPG sources, and the IPTVBoss/Dispatcharr/Plex output writers described in the [Roadmap](../../ROADMAP.md), have not been implemented yet.

Per ADR 0003, domain objects must not reference infrastructure-specific concepts. `Channel` and `BuildContext` have no IPTVBoss-, Dispatcharr-, or Plex-specific fields; provider- and playlist-specific values are stored as plain strings supplied by the infrastructure layer.

## Data flow (current)

```text
provider.json / epg_sources.json / *.m3u
        |
        v
Read-ChannelForgeProvider / Read-ChannelForgeEpgSource / Import-ChannelForgeM3UPlaylist
        |
        v
Channel objects  --->  Resolve-ChannelForgeAlias  --->  ConvertTo-ChannelForgeNormalizedChannel
        |
        v
BuildContext (aggregated channels, warnings, errors, statistics)
```

Build orchestration that assembles a `BuildContext` end to end, and the output writers for IPTVBoss/Dispatcharr/Plex, are future work (see [Roadmap](../../ROADMAP.md) Milestones 4 and 5).

## Source of truth

Provider sources, EPG sources, and rules live in `data/` as declarative JSON/CSV files (see [ADR 0001](../adr/0001-source-of-truth.md)). Generated outputs under `output/` are disposable artifacts, not source data.

## Related documents

- [ADR 0001 — ChannelForge owns the source of truth](../adr/0001-source-of-truth.md)
- [ADR 0003 — Use clean layered architecture](../adr/0003-clean-architecture.md)
- [Channel Identity Model](CHANNEL_IDENTITY_MODEL.md)
- [Developer Guide](../developer/DEVELOPER_GUIDE.md)
