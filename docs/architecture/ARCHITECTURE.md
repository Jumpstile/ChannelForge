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
- [`Import-ChannelForgeM3UPlaylist`](../../src/ChannelForge/Public/Import-ChannelForgeM3UPlaylist.ps1) — parses a local M3U playlist into `Channel` objects, including the stream URL, through the shared streaming parser used by configured remote M3U acquisition.
- [`Import-ChannelForgeConfiguredM3USource`](../../src/ChannelForge/Public/Import-ChannelForgeConfiguredM3USource.ps1) — acquires one configured remote provider M3U through the v5 bounded HTTPS/443 path, optionally uses the disposable 24-hour fetch cache, and returns the same `Channel` objects as the local parser without exposing a raw URL ingestion command.
- [`Resolve-ChannelForgeAlias`](../../src/ChannelForge/Public/Resolve-ChannelForgeAlias.ps1) — deterministic, exact-match alias lookup; falls back to the input name when no alias is known.
- [`Set-ChannelForgeChannelNumber`](../../src/ChannelForge/Public/Set-ChannelForgeChannelNumber.ps1) — assigns `AssignedNumber` from `numbering_blocks.json` by exact (case-insensitive) match against a channel's `Group`; leaves a channel unassigned with a warning rather than guessing a category mapping.
- [`Merge-ChannelForgeLineup`](../../src/ChannelForge/Public/Merge-ChannelForgeLineup.ps1) — the lineup pipeline: parses local playlists or accepts already-parsed configured remote channels, normalizes, alias-resolves, deduplicates by tvg-id (or display name), numbers, and returns a deterministically ordered channel set plus duplicate/warning counts.
- [`Export-ChannelForgeM3UPlaylist`](../../src/ChannelForge/Public/Export-ChannelForgeM3UPlaylist.ps1) — renders a `Channel[]` to M3U text (`#EXTM3U`/`#EXTINF` with `tvg-id`/`tvg-name`/`tvg-logo`/`tvg-chno`/`group-title`) and writes it with no BOM and a fixed line ending, so the same channel set always produces the same bytes.
- [`Export-ChannelForgeXmltv`](../../src/ChannelForge/Public/Export-ChannelForgeXmltv.ps1) — writes deterministic XMLTV from merged Programme records; `Build-Lineup.ps1` wires configured local and bounded remote XMLTV sources into this path.
- [`New-ChannelForgeChannel`](../../src/ChannelForge/Public/New-ChannelForgeChannel.ps1) / [`New-ChannelForgeBuildContext`](../../src/ChannelForge/Public/New-ChannelForgeBuildContext.ps1) — domain object constructors.
- [`ConvertTo-ChannelForgeNormalizedChannel`](../../src/ChannelForge/Public/ConvertTo-ChannelForgeNormalizedChannel.ps1) — applies normalization to a channel.

Private helpers in `src/ChannelForge/Private` support the application layer without being part of the public surface, e.g. [`Normalize-ChannelForgeName`](../../src/ChannelForge/Private/Normalize-ChannelForgeName.ps1), which strips quality tags and backup/alternate markers from playlist names.

Stage A guide intelligence adds read-only domain contracts for volatile event-guide evidence. `GuideEvidenceRecord` carries sanitized provider display text, M3U metadata, XMLTV, AED-derived, schedule, and accepted-knowledge evidence with source relationship, freshness, confidence state, and event metadata. `GuideReadinessRecord` and `Get-ChannelForgeGuideReadiness` project those records without changing accepted state or publishing output; every result remains `CandidateOnly` and requires the existing explicit acceptance boundary.

`New-ChannelForgeGuideEvidence` is the constructor for this Stage A evidence surface. It accepts logical source identifiers and structured event fields, normalizes ISO-8601 instants to UTC, rejects invalid identifiers, downgrades low-confidence confirmations, and excludes URLs, stream URLs, credentials, tokens, private paths, parser errors, candidate hashes, and generation IDs from the record.

Stage B native event-pattern inference adds `GuidePatternExample`, `GuidePatternFieldCandidate`, `GuideEventPatternRule`, and `GuidePatternInferenceResult` contracts. `Invoke-ChannelForgeGuidePatternInference` accepts representative provider-name examples or Stage A `GuideEvidenceRecord` objects and returns a deterministic, read-only candidate. The candidate stores semantic grammar segments, field candidates, per-example extraction preview, confidence, reason codes, and safe provenance fingerprints; it does not expose an opaque regex rule.

Timezone interpretation is explicit: callers provide safe abbreviation mappings or a default timezone, and yearless dates use an injected reference instant. Duplicate timezone clauses and Stage A timestamps are normalized to canonical UTC and marked as agreement or contradiction. Cross-source assessment counts only independent source relationships; mirrors remain provenance and never create independent confirmation. A supplied existing rule is compared by deterministic rule identity, and drift remains `NeedsReview` with adoption `NotApplied`.

Inference is a read-only analysis boundary. It does not write provider state, downstream configuration, guide output, accepted state, or a generation. Every result is `CandidateOnly`, has `CanPublish = false`, and retains the existing explicit acceptance/promotion boundary for any later consumer.
Stage C adds the beginner review projection: [`GuidePatternReviewReport`](../../src/ChannelForge/Classes/GuidePatternReviewReport.ps1) and [`Get-ChannelForgeGuidePatternReview`](../../src/ChannelForge/Public/Get-ChannelForgeGuidePatternReview.ps1). It consumes only the Stage B inference result and returns an object, deterministic JSON, or beginner-readable Markdown. The projection translates semantic candidates and review reason codes into plain-language fields and next actions without exposing regex, raw examples, or sensitive source data. `CandidateOnly`, `CanPublish = false`, and `AcceptedStateMutation = None` are fixed safety invariants; the command has no provider, downstream, filesystem, guide-publication, or accepted-state mutation path.

Stage C is therefore a coaching/readability boundary, not an adoption boundary. Confirmed output still requires the existing explicit acceptance/promotion contract, while contradiction, stale, unavailable, unresolved, and drift states remain visible and blocked from automatic adoption.

Stage D wires this contract into the beginner workflow at [`scripts/Build-My-Lineup.ps1`](../../scripts/Build-My-Lineup.ps1). `-EventPatternPreview` accepts representative event-channel display names or Stage A evidence, invokes the Stage B inference and Stage C review boundaries, and writes deterministic redacted JSON, Markdown, and text reports under `output/reports/`. Interactive examples are pipe-separated when the parameter is omitted; callers can provide event type/group, timezone mappings or a default offset, reference instant, date order, minimum example count, and an existing rule/candidate for deterministic drift comparison without writing a regex.

The workflow rejects `-EventPatternPreview -Accept` before candidate staging. The preview report is always `CandidateOnly`, `CanPublish = false`, requires `ExplicitAcceptance`, and records `AcceptedStateMutation = None`; it has no guide-publication, provider, downstream, or accepted-state mutation path. Confirmed and safe-candidate reviews are informational only, while missing, contradictory, stale, unavailable, or unresolved evidence remains blocked.

The first slice is ephemeral: rule audit fields (`CreatedUtc`, `ValidatedUtc`, and `LastSuccessfulValidationUtc`) remain empty because no learned-rule store is introduced. Deterministic rule identity and extraction output do not depend on wall-clock time.

Stage E adds [`Get-ChannelForgeGuidePatternAcceptancePlan`](../../src/ChannelForge/Public/Get-ChannelForgeGuidePatternAcceptancePlan.ps1), a deterministic read-only projection over Stage B inference or Stage C/D review output. It explains detected patterns, matched examples, confidence, provenance, freshness, drift, proposed future rule identity when Stage B is supplied directly, eligibility, blocked reasons, and the safety boundary. Stable title/time/pattern identity is explicitly separate from volatile enrichment. Volatile facts are eligible for current presentation only when source identity/type, fetched and source-data timestamps, freshness TTL, season/competition context, subject identity, confidence, and non-contradictory provenance prove eligibility; otherwise they are omitted or marked for review. This is an evaluator boundary, not a volatile-fact producer: the current Stage A/B path does not synthesize statistics, rosters, standings, or schedule descriptions, and absent optional safe metadata produces `NotProvided`. Stage C/D-only input explicitly reports that the opaque identity is unavailable because those review formats omit candidate hashes. It returns an object, compact JSON, distinct beginner-readable Markdown, or plain text. It never accepts, adopts, publishes, writes files, mutates provider/downstream state, or changes accepted state; `PlanOnly`, `CandidateOnly`, `CanPublish = false`, `CanAcceptNow = false`, and `Adoption = NotApplied` are fixed invariants.

### Infrastructure layer

File-format, transport, and output-target integrations: M3U, XMLTV, JSON, CSV,
IPTVBoss, Dispatcharr, the file system, and HTTP. M3U/XMLTV local parsing and
writing are joined by the approved bounded HTTPS/443 acquisition path for
configured remote provider M3U and XMLTV sources; the IPTVBoss/Dispatcharr/Plex
output writers described in the [Roadmap](../../ROADMAP.md) remain future work —
see "Known limitations" below.

Per ADR 0003, domain objects must not reference infrastructure-specific concepts.
`Channel` and `BuildContext` have no IPTVBoss-, Dispatcharr-, or Plex-specific
fields; provider- and playlist-specific values are stored as plain strings
supplied by the infrastructure layer.

### Web-first local UI and deployment boundary

ChannelForge's primary UI architecture is a browser-based local web UI served by
the ChannelForge engine. The browser talks to the engine's documented HTTP/API
boundary; the engine remains responsible for configuration, source acquisition,
candidate generation, review, immutable acceptance, reports, and generated
outputs.

The foundation slice provides a read-only loopback HTTP server with a beginner
status shell and safe health/status JSON. When `gui/dist` contains a Vite build,
the server serves only its `index.html` and allowlisted static asset types.
Without that build output, `/` falls back to the safe placeholder shell. Static
requests are confined to the configured `gui/dist` subtree, do not list
directories, and do not expose accepted-generation contents or provider files.
The built landing surface consumes `GET /api/status` from the same origin and
projects only its validated running, lineup, next-action, and read-only facts
into beginner copy. The browser retains no raw status payload and has no
state-changing API capability; unavailable, failed, or invalid status responses
render a safe degraded message.

The primary deployment modes are:

- **Docker container** — the engine serves the web UI and API from one container,
  with operator-provided persistent mounts for configuration, disposable source
  cache, immutable generations, accepted pointers, reports/logs, and generated
  M3U/XMLTV outputs.
- **Windows server/service install** — the installed engine serves the same web UI
  and API from a local server/service process with persistent storage for the same
  state, reports, and outputs.

Native/local development may serve the same UI/API without Docker. Docker,
Windows server/service, and native/local modes must share the same engine
commands, accepted-generation contract, and safety boundaries. A native wrapper
is optional future packaging only; it is not a second product UI or a second
state authority.

Docker, Windows service, full HTTP/API behavior, and appearance modes remain
future work. The local server foundation does not change those deployment claims.

#### Reuse existing GUI work

The existing `gui/` React/TypeScript/Tauri work is reusable UI work, not disposable architecture. Preserve or adapt its visual layout direction, design tokens, accessible component patterns, Guided Setup / Beginner Workflow structure, playlist and guide selection UX, validation and review surfaces, saved-lineup concepts, and beginner-facing copy and terminology when building the web UI.

#### Re-evaluate native assumptions

Before web UI implementation, re-evaluate every Tauri-specific shell command, native file-picker assumption, direct filesystem access assumption, local process invocation, and state-changing behavior that currently sits outside an engine HTTP/API boundary. The web UI must not reproduce native-only behavior by granting the browser direct filesystem or process authority. State-changing operations must route through documented engine commands and the immutable acceptance boundary.

The current Tauri implementation remains preserved and is useful as a design and behavior reference. Its native bridge is not the deployment contract for the web UI.

### Write guardrails

`scripts/Build-Lineup.ps1` and `scripts/Backup-IPTVBoss.ps1` sit outside the module (they're standalone entry points, not part of the public API) but import it to call `Assert-ChannelForgeWritePath` and `Assert-ChannelForgePathExists` before any filesystem write, copy, or archive operation. This keeps the "what's allowed to write where" decision in one place rather than re-implemented per script. The same principle covers reads of operator-supplied configuration paths: `Assert-ChannelForgeReadPath` confines a resolved `local_playlist` value to `data/playlists/` before `Build-Lineup.ps1` ever opens it. See the [Developer Guide](../developer/DEVELOPER_GUIDE.md#write-guardrails) for the current write/read sites and what each guardrail checks.

## Data flow (current)

```text
provider.json (enabled + local_playlist or supported remote URL)
        |
        v
  [enabled + local_playlist] ----> Import-ChannelForgeM3UPlaylist
        |
        v
  [enabled + no local + remote URL] -> Import-ChannelForgeConfiguredM3USource
        |
        v
  shared M3U parser -> normalize -> alias -> dedup -> number
        |
        v
Export-ChannelForgeM3UPlaylist  --->  output/merged.m3u


epg_sources.json (enabled local XMLTV path or supported remote URL entries)
        |
        v
  [enabled + supported local or remote XMLTV]
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

```text
event-channel examples or Stage A guide evidence
        |
        v
Invoke-ChannelForgeGuidePatternInference
        |
        v
Get-ChannelForgeGuidePatternReview
        |
        v
plain-language object / JSON / Markdown review
        |
        +--> review/confidence/provenance/drift only
        +--> no guide publication, provider mutation, downstream mutation,
             filesystem write, or accepted-state mutation
```

This is the build pipeline `scripts/Build-Lineup.ps1` runs via `Merge-ChannelForgeLineup` for local or remote M3U and the configured XMLTV import/merge/export commands for guide output. The branches remain separate: XMLTV is source-scoped and is not bound to M3U `Channel.TvgId` values. `BuildContext` exists as a domain object but this pipeline does not populate it yet; downstream output writers and Plex guide binding remain future work.

### Known limitations (issue #7 Phase 1)

- **Remote provider M3U/XMLTV acquisition is bounded and fail-closed.** Only HTTPS on port 443 is accepted; redirects, proxies, credentials, retries, remote ZIP, stale/offline success, and live-network CI are outside this slice. Unsupported content, encodings, malformed input, bounds failures, conflicts, `NeedsReview`, or export/promotion failures produce a failed source/build status.
- **Remote fetch caching is disposable, not authoritative.** Provider M3U uses a separate 24-hour cache namespace and XMLTV uses its fixed policy; invalid or stale entries require successful validation or a full refetch and never substitute stale data.
- **Plex EPG/guide binding remains deferred.** The build can produce `output/merged.xml`, but downstream channel-to-guide binding and automatic Plex refresh are separate work.
- **Category-to-numbering-block matching is intentionally simple.** A channel is numbered only if its M3U `group-title` exactly matches (case-insensitive) a `numbering_blocks.json` category. Smarter category inference is Confidence Engine territory (Roadmap Milestone 2), not this pipeline.
- **Native event-pattern inference and review are read-only and bounded.** Stage B analyzes supplied examples or Stage A evidence; Stage C projects that result as beginner-readable object, JSON, or Markdown output. Schedule-source adapters, documented IPTVBoss AED JSON import, persistent learned-rule storage, expert regex override, unattended event refresh, automatic relearning/adoption, and guide publication remain future work.

## Scheduled refresh run boundary

`scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1` is a manual foreground entry point by default. The same wrapper has a scheduler-owned `-ScheduledInvocation` mode that invokes the report-only planner with `TriggerKind=Scheduled`, accepts only a fresh `READY_SCHEDULED` plan, and invokes `scripts/Invoke-ChannelForgeSourceRefresh.ps1` at most once. A deterministic jitter delay is one bounded foreground wait, not a worker or retry loop.

The opt-in Windows registration is owned by the four `scripts/*ScheduledRefresh*.ps1` lifecycle/status commands. It registers one daily CalendarTrigger under `\ChannelForge\` with an explicit UTC `StartBoundary`, an absolute PowerShell Core 7.6+ executable, least-privilege interactive principal, and `MultipleInstancesPolicy=IgnoreNew`. Registration and history evidence under `output/operations/` contain digests and bounded statuses only.

The lock handle, not the marker file, establishes ownership. Marker fields are diagnostic crash evidence and contain only an owner-token hash, process timing, plan digest, and bounded state. A failed lock acquisition never deletes or adopts a stale marker. A successful acquisition may record a prior `Running` marker as abandoned before starting the new run.

The run reports under `output/reports/` are operational evidence. The wrapper itself performs no network request and writes no cache directly. The existing source-refresh executor may update disposable source cache according to its established contract. Accepted state, generations, pointers, published M3U/XMLTV output, provider state, and downstream state remain outside this boundary. ChannelForge does not provide a daemon, service, worker, autonomous retry loop, or cross-platform scheduler backend.

## Source of truth

Provider sources, EPG sources, and rules live in `data/` as declarative JSON/CSV files (see [ADR 0001](../adr/0001-source-of-truth.md)). Generated outputs under `output/` are disposable artifacts, not source data.

Every tracked JSON file under `data/` has a structural contract in `schemas/`, validated with PowerShell's built-in `Test-Json -SchemaFile` (run them all via `scripts/Validate-ConfigSchemas.ps1`). Schemas check shape — required/optional fields and types — not business content; they do not enumerate today's provider names, EPG roles, or categories, and they do not check URL trust-boundary rules, which remain a runtime concern in `Test-ChannelForgeSourceUrl`. See the [Developer Guide](../developer/DEVELOPER_GUIDE.md#configuration-schemas) for the full file-to-schema mapping and how the two validation layers relate.

### Durable source-set authority

`state/source-enrollment.json` is the single server-owned durable source-set authority for guided local sources. Its current schema is `source-enrollment/v2`; it stores ordered playlist records, guide records, and explicit guide-to-playlist bindings in one canonical document. A playlist may have multiple guides, a guide may serve one or many playlists, and `AppliesToAll` is explicit rather than inferred from enumeration order. With one playlist, omitted bindings auto-bind each guide to that playlist; with multiple playlists, omitted bindings leave guides unbound and actionable. Binding revisions and canonical binding identities are part of the source-set hash.

Each record has a stable server-derived source ID independent of content bytes and enumeration order. Managed files are retained below `state/managed-sources/`; supported public sources are represented as non-tokenized HTTPS URLs validated by the existing URL trust boundary. Safe status projections omit URLs, managed paths, content hashes, and accepted-state hashes. Tokenized or credential-bearing URLs are unsupported.

The legacy `source-enrollment/v1` document remains readable through a deterministic in-memory compatibility projection; it is not a second authority and is not silently discarded. Existing refresh planning consumes that compatibility input projection, enumerates every enabled playlist and guide record, reuses unchanged managed bytes, and leaves public descriptors review-only in this slice. The source-set authority is separate from accepted lineup state, candidate generations, and disposable fetch caches, so refresh review never mutates accepted state.

### Headless multi-source proposal authority

`POST /api/guided-setup/proposal` retains the exact v1 browser envelope and
also accepts the headless `schemaVersion: 2` source-set envelope. V2 stages
1–8 playlists and 0–8 guides, validates explicit selected/all guide bindings,
and produces one candidate through the same candidate-only path. Request
references are not authoritative identities: SourceId and binding identities
are derived by the server. Omitted bindings auto-bind every guide only when
there is exactly one playlist; with multiple playlists, omitted guides remain
enrolled and actionable but are not applied to the accepted guide output until
an explicit binding is reviewed. The response never exposes source URLs,
filenames, paths, hashes, or raw content.

Managed uploads and one-time acquired public HTTPS bytes are staged under
server-derived source IDs. Acceptance promotes managed records into the
durable source-set authority and preserves public HTTPS descriptors without
redesigning remote refresh. Browser multi-row selection, unattended remote
refresh, and accepted-state semantics remain outside this slice.

## Related documents

- [ADR 0001 — ChannelForge owns the source of truth](../adr/0001-source-of-truth.md)
- [ADR 0003 — Use clean layered architecture](../adr/0003-clean-architecture.md)
- [ADR 0016 — Web-first local UI and server-first deployment](../adr/0016-web-first-local-ui.md)
- [Channel Identity Model](CHANNEL_IDENTITY_MODEL.md)
- [Developer Guide](../developer/DEVELOPER_GUIDE.md)
