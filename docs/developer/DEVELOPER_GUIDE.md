# Developer Guide

> Status: Living document

## Purpose

Explain how ChannelForge is organized and how developers should work in the repository.

## Audience

Developers and maintainers.

## Prerequisite

Read [ONBOARDING.md](../../ONBOARDING.md) and [FIRST_READ.md](FIRST_READ.md) before making changes. [QUICK_START.md](QUICK_START.md) walks through verifying your environment can run and test the module, if you haven't done that yet.

ChannelForge requires PowerShell 7.6 or newer, Core edition. PowerShell 7.6 supplies the supported .NET 10 or newer hosting runtime; no separate .NET installation is required.

## Module layout

```text
src/ChannelForge/
├── ChannelForge.psd1     Module manifest
├── ChannelForge.psm1     Module loader (loads Classes, then Private, then Public)
├── Classes/              Domain objects (Channel, BuildContext)
├── Private/              Internal helper functions, not exported
└── Public/                Exported functions
```

`ChannelForge.psm1` loads files in this order: classes first (PowerShell classes must exist before any function that references them), then private helpers, then public functions. Only the functions in `Public/` are exported via `Export-ModuleMember`.

## Adding a function

1. Decide whether the function belongs in `Public/` (used by callers outside the module) or `Private/` (an internal helper).
2. Use an approved PowerShell verb (see [STYLEGUIDE.md](../../STYLEGUIDE.md)).
3. Validate required inputs and throw a terminating error with a clear message when they are missing or malformed.
4. Add a Pester test in `tests/unit` covering the happy path and at least one failure case.
5. Update this guide or [ARCHITECTURE.md](../architecture/ARCHITECTURE.md) if the change affects module structure or layering.

## Tests

Tests live in `tests/unit` and use Pester 5.7.1. Fixtures live in `tests/fixtures`.

Run the full suite from the repository root:

```powershell
Invoke-Pester ./tests/unit
```

Run a single test file:

```powershell
Invoke-Pester ./tests/unit/ProviderParser.Tests.ps1
```

Every `Describe` block imports the module fresh with `Import-Module ... -Force`, so tests reflect the current state of `src/ChannelForge` rather than a previously loaded session.

## CI quality gates

GitHub Actions (`.github/workflows/powershell-ci.yml`) runs two jobs on every push and pull request to `main`. Both must pass before a change is considered mergeable.

**`secret-scan`** (Ubuntu) — Gitleaks scans the repository and available history for committed secrets. See [SECURITY.md](../reference/SECURITY.md) for what to do if it finds something.

**`quality-gates`** (Windows, runs after `secret-scan`) — installs Pester 5.7.1 and PSScriptAnalyzer 1.25.0, then runs these checks in order, fast/narrow ones first so an easy mistake fails quickly:

| Step             | What it checks                                                                                | Local command                            |
| ---------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------- |
| Config schemas   | Every tracked `data/*.json` file matches its schema in `schemas/`                             | `./scripts/Validate-ConfigSchemas.ps1`   |
| Markdown hygiene | No tracked `.md` file has the malformed-generator-artifact shape from the #2/#13/#16 incident | `./scripts/Validate-MarkdownHygiene.ps1` |
| Markdown links   | Every relative link in a tracked `.md` file resolves to a real file                           | `./scripts/Validate-MarkdownLinks.ps1`   |
| PSScriptAnalyzer | No Error-severity finding under `src/` or `scripts/`                                          | `./scripts/Validate-ScriptAnalyzer.ps1`  |
| Pester           | Full unit test suite                                                                          | `Invoke-Pester ./tests/unit -CI`         |

Run all five locally before pushing — they're the same commands CI runs, so a clean local run means a clean CI run for everything except the secret scan.

### What's schema-level vs. runtime/domain-level

These checks validate **shape** ahead of time. They deliberately do not replace the **runtime/domain** checks that already exist in the module — both layers stay in place:

| Layer                                                                                                                             | Where                                      | What it catches                                                                     |
| --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------- |
| Schema (`schemas/*.schema.json`, CI step "Config schemas")                                                                        | Before a file is ever read                 | Missing/extra fields, wrong types                                                   |
| Runtime trust boundary (`Test-ChannelForgeSourceUrl`, `Read-ChannelForgeProvider`/`Read-ChannelForgeEpgSource`)                   | When a file is actually loaded             | Malformed URLs, unsupported schemes, credentials, loopback/private/link-local hosts |
| Runtime write guardrails (`Assert-ChannelForgeWritePath`, `Assert-ChannelForgePathExists`, `Assert-ChannelForgeBackupSourcePath`) | When a script writes/reads/backs up a path | Writes outside an approved root, missing sources, overly broad backup sources       |
| Static analysis (PSScriptAnalyzer, CI step "PSScriptAnalyzer")                                                                    | Before code runs at all                    | Dangerous patterns, syntax-adjacent mistakes (Error severity only — see below)      |
| Tests (Pester)                                                                                                                    | On every change                            | Behavior regressions across all of the above                                        |

A file can pass schema validation and still be rejected at runtime — see `tests/unit/ConfigSchemas.Tests.ps1`'s "Schemas supplement, not replace, runtime validation" cases for a working example. Don't loosen a runtime check because "the schema already validates this"; they check different things.

### PSScriptAnalyzer: why only Error severity fails CI

`Validate-ScriptAnalyzer.ps1` runs at Error, Warning, and Information severity and prints everything, but only an **Error**-severity finding fails the check. As of this writing the codebase has ~50 accepted Warning/Information findings (`Write-Host` usage in `scripts/`, a few naming/`ShouldProcess` conventions in older functions) that aren't worth a sweeping unrelated refactor just to satisfy a new CI gate. Gating on Error severity still catches real mistakes without that noise. If you fix one of the existing Warning findings as part of unrelated work, that's welcome — just don't feel obligated to fix all of them to pass CI.

### Deferred: full Markdown style linting, anchor resolution, external link checks

Three related ideas were considered and intentionally **not** implemented, to keep this pipeline low-noise:

- **A general Markdown style linter** (e.g. markdownlint) would surface many pre-existing, unrelated heading/style inconsistencies across `docs/` and would need a dedicated cleanup pass before it could be a CI gate without immediately failing on day one. `Validate-MarkdownHygiene.ps1` is intentionally narrow instead — it only re-detects the exact failure shape from a real past incident.
- **Resolving `#anchor` fragments in links** (confirming a heading actually exists, not just the file) requires replicating the renderer's exact heading-to-slug rule, which is a common source of false positives. `Validate-MarkdownLinks.ps1` checks that the target file exists and explicitly ignores anchors.
- **Checking external `http(s)` links resolve** would make CI depend on network access and third-party sites' uptime, which is the opposite of deterministic. Not implemented; `Validate-MarkdownLinks.ps1` skips `http(s)`/`mailto` targets entirely.

## Public functions today

| Function                                  | Purpose                                                                                                |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `Read-ChannelForgeProvider`               | Load provider source definitions from `provider.json`                                                  |
| `Read-ChannelForgeEpgSource`              | Load EPG source definitions from `epg_sources.json`, sorted by priority                                |
| `Import-ChannelForgeM3UPlaylist`          | Parse a local M3U playlist into `Channel` objects through the shared streaming parser                  |
| `Import-ChannelForgeConfiguredM3USource`  | Acquire and parse one configured remote M3U through bounded HTTPS/443 and the disposable fetch cache   |
| `Resolve-ChannelForgeAlias`               | Deterministic, exact-match alias resolution                                                            |
| `Set-ChannelForgeChannelNumber`           | Assign `AssignedNumber` from numbering blocks by exact group/category match                            |
| `Merge-ChannelForgeLineup`                | Phase 1 end-to-end pipeline: parse, normalize, alias-resolve, dedup, number (issue #7)                 |
| `Export-ChannelForgeM3UPlaylist`          | Render a `Channel[]` to deterministic M3U text                                                         |
| `New-ChannelForgeChannel`                 | Construct a `Channel` domain object                                                                    |
| `New-ChannelForgeBuildContext`            | Construct a `BuildContext` domain object                                                               |
| `ConvertTo-ChannelForgeNormalizedChannel` | Apply name normalization to a `Channel`                                                                |
| `Assert-ChannelForgeWritePath`            | Throw unless a target path resolves under an explicitly approved root                                  |
| `Assert-ChannelForgeReadPath`             | Throw unless a configured read path (e.g. `local_playlist`) resolves under an explicitly approved root |
| `Assert-ChannelForgePathExists`           | Throw unless a required file/directory exists, with a clear description                                |
| `Assert-ChannelForgeBackupSourcePath`     | Throw if a backup source is a drive root or well-known system directory                                |

See [ARCHITECTURE.md](../architecture/ARCHITECTURE.md) for how these fit together.

## Write guardrails

`Assert-ChannelForgeWritePath`, `Assert-ChannelForgePathExists`, and `Assert-ChannelForgeBackupSourcePath` exist so that anything writing to disk — inside the module or in `scripts/` — has to state its intent rather than trusting a path by default (see issue #5, [ADR 0004](../adr/0004-self-healing-with-guardrails.md)). `scripts/Build-Lineup.ps1` and `scripts/Backup-IPTVBoss.ps1` both import the module and call these before every write:

- Every write target is checked with `Assert-ChannelForgeWritePath -Path <target> -AllowedRoot <root>`. There is no default root; the caller must name the approved area (e.g. the project's `output/` or `backups/` folder), so a write can never silently land somewhere unintended.
- Every required input path is checked with `Assert-ChannelForgePathExists` before it's read from or backed up, so a missing path fails with a clear error instead of producing an empty or corrupt downstream result.
- `Backup-IPTVBoss.ps1` additionally calls `Assert-ChannelForgeBackupSourcePath` to reject a backup source that exists but is dangerously broad (a drive root, or a well-known system directory directly under one) — existence alone doesn't catch a misconfigured path pointed at the whole machine.
- `Backup-IPTVBoss.ps1` refuses to overwrite an existing backup archive unless `-Force` is passed explicitly.
- `Assert-ChannelForgeReadPath -Path <target> -AllowedRoot <root>` is the read-side counterpart, added for issue #7 Phase 1: `Build-Lineup.ps1` calls it on every resolved `local_playlist` path with `data/playlists/` as the allowed root, before that path is ever opened. It reuses the same full-path containment check as `Assert-ChannelForgeWritePath` (`Test-ChannelForgeWritePath`), so `..` traversal, an absolute path elsewhere on disk, a UNC path, or a drive-root/system path are all rejected the same way a write outside an approved root would be.

## Scheduled refresh run implementation boundary

The manual run wrapper lives in `scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1`, not in the public module API. Manual mode remains the default; Windows Task Scheduler invokes the same wrapper with `-ScheduledInvocation`, which internally passes `TriggerKind=Scheduled` to the planner and accepts only `READY_SCHEDULED`.

The four lifecycle/status scripts own one opt-in Windows Task Scheduler task per canonical local repository root. The task uses an explicit UTC XML `StartBoundary`, an absolute PowerShell Core 7.6+ runtime, an absolute wrapper and root, an interactive least-privilege principal, no stored password, and `MultipleInstancesPolicy=IgnoreNew`. The task does not use `-TimeZone`, random delay, repetition, restart-on-failure, boot/logon triggers, or `ExecutionPolicy Bypass`.

Install/update requires the exact interactive phrase `ENABLE` or explicit `-Approve`; uninstall requires `REMOVE` or `-Approve`. Foreign or mismatched tasks are never replaced or removed. Registration and scheduled history evidence are redacted and digest-based; they exclude repository paths, provider data, URLs, credentials, headers, payloads, and child process text.

The lock's live exclusive handle is authoritative. The JSON marker is diagnostic evidence only and must never be deleted or adopted because of a timestamp or PID. Run reports use the fixed relative paths `output/reports/scheduled-refresh-run.json` and `output/reports/scheduled-refresh-run.md`; they must contain only redacted operational evidence.

The wrapper performs no network or direct cache operation. It must not mutate accepted state, generations, pointers, published outputs, provider state, or downstream state. `Degraded` and `ReviewNeeded` source rows map to `DEGRADED`; notification level carries the attention distinction. There is no always-on worker, daemon, service, autonomous retry loop, or cross-platform scheduler backend.

## Lineup build pipeline (M3U/XMLTV acquisition)

`scripts/Build-Lineup.ps1` produces a deterministic merged M3U from local provider playlists or configured remote M3U sources and, when configured, imports local XMLTV `.xml`, `.gz`, or single-entry `.zip` sources or bounded remote XMLTV sources and writes deterministic `output/merged.xml`. Remote acquisition uses the v5 pinned HTTPS/443 boundary — see "Known limitations" below.

A provider source in `provider.json` participates if it is `enabled` and has either a safe `local_playlist` field (a path to a local `.m3u` file, relative to the repository root) or a supported remote URL. When both are present, the local playlist is authoritative. An enabled source with neither usable input fails closed; it is not silently skipped. See `schemas/provider.schema.json`.

Provider and EPG source files are always loaded through `Read-ChannelForgeProvider`/`Read-ChannelForgeEpgSource`, never a raw `Get-Content | ConvertFrom-Json`, so the URL trust-boundary check in `Test-ChannelForgeSourceUrl` always runs. Validated remote URL values are passed only to the private configured-source adapters, which apply the v5 transport policy; they are never exposed through a public raw-URL ingestion command. `Build-Lineup.ps1` keeps exactly one raw read of `provider.json` solely to pull the top-level `provider` label string, which `Read-ChannelForgeProvider` intentionally doesn't return (it returns one record per source); every URL-bearing field still comes from the validated reader.

Each resolved `local_playlist` path is confined to `data/playlists/` via `Assert-ChannelForgeReadPath` before it is read (see "Write guardrails" above) — a `local_playlist` value is operator-supplied configuration, not trusted input, so the same containment logic that protects writes protects this read.

### Local XMLTV orchestration

Enabled sources are ordered by priority, name, and the configured relative path using ordinal comparisons. The resolved path is used only to open the configured file; it is not used in identifiers, reports, warnings, or artifact ordering. A failed import, merge conflict, `NeedsReview` result, or export/promotion failure fails the XMLTV branch, leaves the public `output/merged.xml` path absent, and preserves any prior artifact only in the non-published rollback area.

### Provider config resolution (issue #20)

`Build-Lineup.ps1` never requires editing a tracked provider file with real values. `Resolve-ChannelForgeProviderConfigPath` selects which file under `data/providers/` to read, in this exact precedence order:

1. An explicit `-ProviderPath` override, if `Build-Lineup.ps1` was called with one. Resolved relative to `data/providers/` and confined there the same way `local_playlist` is — an absolute path, a UNC path, `..` traversal, a directory, or a non-`.json` file is rejected, not silently coerced. An override bypasses local-file discovery entirely, including any ambiguity in it.
2. Exactly one non-recursive `data/providers/*.local.json` file, if no override was given and exactly one exists. More than one is an error naming the conflicting files — the build never guesses which one to use (see ADR 0005).
3. The tracked `data/providers/mybunny.json` (today's example/fixture file), if neither of the above applies.

`Resolve-ChannelForgeProviderConfigPath` only selects a path; it does not read or validate the file. Once a path is selected, `Build-Lineup.ps1` reads it with no fallback: a selected file that is missing, malformed, or fails the URL trust-boundary check in `Read-ChannelForgeProvider` fails the whole build loudly, it never falls back to the tracked file. See `tests/unit/ProviderConfigResolution.Tests.ps1` for the resolver's unit tests and `tests/unit/BuildLineupScript.Tests.ps1`'s "provider config resolution" `Describe` block for the end-to-end behavior.

For each participating source, `Build-Lineup.ps1` calls `Merge-ChannelForgeLineup`, which:

1. Uses configuration order as a path/URL-independent `OrderKey`; local sources are parsed with `Import-ChannelForgeM3UPlaylist`, while remote sources arrive already parsed by `Import-ChannelForgeConfiguredM3USource` through the same streaming core.
2. Normalizes names (`ConvertTo-ChannelForgeNormalizedChannel`) and resolves aliases (`Resolve-ChannelForgeAlias`).
3. Deduplicates: a channel sharing a `tvg-id` (or, if no `tvg-id`, the same display name) with an earlier channel is marked `IsDuplicate` and excluded from the output. "Earlier" is decided entirely by the configuration `OrderKey`, followed by in-file parse order, never by a machine-local path or remote URL.
4. Assigns channel numbers (`Set-ChannelForgeChannelNumber`) by exact (case-insensitive) match between a channel's `Group` and a `numbering_blocks.json` category. No match means no number, plus a warning — never a guess.
5. Sorts the final set: numbered channels first by number, then unassigned channels by name.

`Export-ChannelForgeM3UPlaylist` then renders that set to `output/merged.m3u`: `#EXTM3U` header, one `#EXTINF` line per channel with whichever of `tvg-id`/`tvg-name`/`tvg-logo`/`tvg-chno`/`group-title` are present, followed by the stream URL line. The file is written as UTF-8 with no BOM and a fixed line ending, so the same channel set always produces the same bytes — `tests/unit/MergeChannelForgeLineup.Tests.ps1` and `tests/unit/BuildLineupScript.Tests.ps1` both assert byte/hash stability across repeated runs, not just "doesn't throw."

Every field `Export-ChannelForgeM3UPlaylist` writes is passed through the private `ConvertTo-ChannelForgeSafeM3UText` helper immediately before being written, never earlier — the domain `Channel` object keeps its original, unsanitized value. M3U has no formal escaping standard, so untrusted provider text (M3U attributes, alias-resolved names) could otherwise corrupt the file's structure: an embedded `"` would break a quoted attribute, and an embedded CR/LF could make later text look like a second, fake `#EXTINF`/URL pair. The helper replaces `"` with `'` and collapses any `\r`/`\n` run to a single space. Ordinary commas are left untouched — the M3U parser locates the display name with `LastIndexOf(',')`, so commas don't need escaping. See `tests/unit/MergeChannelForgeLineup.Tests.ps1`'s `Export-ChannelForgeM3UPlaylist` sanitization cases.

### Known limitations

- **Remote provider M3U/XMLTV fetch: bounded and fail-closed.** Only HTTPS on port 443 is accepted; redirects, proxies, credentials, authentication, retries, remote ZIP, stale/offline success, and live-network CI are outside this slice. Malformed input, unsupported content/encoding, bounds failures, conflicts, `NeedsReview`, or output failures report `FAILED` and do not claim an old artifact is current.
- **Remote fetch cache: disposable and source-specific.** Provider M3U uses `output/cache/remote-m3u/` with a fixed 24-hour TTL, conditional validation, and decompressed-content hash fallback. Corrupt or stale entries are repaired or refetched; they never become a stale success path.
- **Target-specific Plex EPG/guide assignment: deferred.** `output/merged.m3u` and optional `output/merged.xml` are generated artifacts; exact M3U/XMLTV identity bindings are reported separately, while downstream Plex assignment and automatic refresh remain separate work.

See [PLEX_SMOKE_TEST.md](../user/PLEX_SMOKE_TEST.md) for the end-to-end walkthrough of testing a real local playlist in Plex under this Phase 1 boundary.

## Report redaction

Generated reports (`output/reports/build-summary.json`, `output/reports/lineup-plan.md`) must never contain full provider/EPG/stream URLs, tokens, account IDs, credentials, local-only file paths, or other secret-like values (see [SECURITY.md](../reference/SECURITY.md)). `Build-Lineup.ps1` lists provider sources by name, enabled state, and local/remote playlist state only — never by `url` — and reports the merged playlist's path as a project-relative string (`output/merged.m3u`, never an absolute or UNC path) plus its SHA-256 hash rather than its contents. Remote acquisition summaries may include only safe operational fields such as an opaque cache key, status, normalized content type, encodings, bounded byte counts, parsed count, and validator-presence booleans. The Pester suite asserts this directly using fixture data shaped like real token-bearing and stream URLs.

This redaction rule does not apply to `output/merged.m3u` itself: stream URLs are the actual playable content of that file, not a secret to strip (see `Export-ChannelForgeM3UPlaylist` and the Channel class's `Url` field).

Display fields are not redacted, only URLs/tokens are: the top-level `provider` label and each source's `name` _do_ appear in `build-summary.json` (`Provider` field) and `lineup-plan.md` ("Provider M3U Sources" list). These are display-only fields, not validated as opaque, so do not put a secret-shaped value (a token, account ID, or credential) in a `provider` or source `name` field — only in `url`, which is the field the redaction rule actually strips.

## Private helpers today

- `Normalize-ChannelForgeName` — strips quality tags (`HD`, `4K`, ...) and backup/alternate markers from playlist channel names.
- `Test-ChannelForgeSourceUrl` — validates provider/EPG source URLs (scheme, host, no embedded credentials, no loopback/private/link-local targets).
- `Test-ChannelForgeDisallowedIpAddress` — IP-range check used by `Test-ChannelForgeSourceUrl`.
- `Test-ChannelForgeWritePath` — path-safety check used by `Assert-ChannelForgeWritePath`.
- `Test-ChannelForgeBackupSourcePath` — rejects drive roots and well-known system directories, used by `Assert-ChannelForgeBackupSourcePath`.
- `ConvertTo-ChannelForgeSafeM3UText` — sanitizes a text value for safe inclusion in M3U output, used by `Export-ChannelForgeM3UPlaylist`.

## Configuration schemas

Every tracked source-of-truth JSON file under `data/` has a JSON Schema (draft-07) contract in `schemas/` (see issue #3):

| Data file                                                             | Schema                                 |
| --------------------------------------------------------------------- | -------------------------------------- |
| `data/providers/mybunny.json`, `data/providers/provider.example.json` | `schemas/provider.schema.json`         |
| `data/epg/epg_sources.json`, `data/epg/epg_sources.example.json`      | `schemas/epg_sources.schema.json`      |
| `data/lineup/locals.json`                                             | `schemas/locals.schema.json`           |
| `data/lineup/numbering_blocks.json`                                   | `schemas/numbering_blocks.schema.json` |
| `data/lineup/categories.json`                                         | `schemas/categories.schema.json`       |
| `data/rules/aliases.json`                                             | `schemas/aliases.schema.json`          |

They validate **structure only** — required/optional fields and types — using PowerShell's built-in `Test-Json -SchemaFile`, so there's no new dependency:

```powershell
Test-Json -Path data/providers/provider.example.json -SchemaFile schemas/provider.schema.json
```

Validate every tracked file at once with the dedicated entry point:

```powershell
pwsh -File scripts/Validate-ConfigSchemas.ps1
```

This script is deterministic (no network access, no secrets, same result every run) and throws — making `pwsh` exit non-zero — on the first set of failures it finds, the same convention every other script under `scripts/` follows. CI runs this on every push and pull request (see [CI quality gates](#ci-quality-gates)).

What the schemas deliberately do **not** do:

- **Enforce URL trust-boundary rules** (scheme allowlist, no embedded credentials, no loopback/private/link-local hosts). That stays in `Test-ChannelForgeSourceUrl` and runs at read time in `Read-ChannelForgeProvider`/`Read-ChannelForgeEpgSource` regardless of whether a file already passed schema validation — a file can be schema-valid and still get rejected at runtime (see `tests/unit/ConfigSchemas.Tests.ps1`'s "Schemas supplement, not replace, runtime validation" cases).
- **Enumerate today's specific values** — provider names, source names, EPG roles, categories, stations, networks, canonical channel names. These schemas check shape and type, not business content, so a new provider, a new EPG role, or a new category doesn't require a schema change. `tests/unit/ConfigSchemas.Tests.ps1` includes an explicit "not overfit" case per schema proving an unfamiliar value is still accepted.
- **Check cross-entry semantics** — e.g. that a numbering block's `end` is greater than or equal to its `start`, that aliases don't collide across entries, or that local channel numbers are unique. These are deferred as a later, separate concern, not done here.

Schemas catch shape mistakes early (a contributor typo, a missing field) before a file ever reaches a parser; they are a second, earlier check, not a replacement for runtime trust-boundary validation.

## Development workflow

Follow [CONTRIBUTING.md](../../CONTRIBUTING.md) for the branch, commit, and review workflow. This guide covers where code lives and how to verify it; CONTRIBUTING.md covers the process around a change.

## GUI foundation

The isolated `gui/` application is the desktop-shell slice for issue #35. It is a Tauri 2 and React/TypeScript shell with design tokens, guided Workbench and Guided Setup layouts, semantic status components, privacy-safe workspace identity display, display-safe workspace/playlist/guide selection states, a Rust-owned native picker bridge, and a deterministic synthetic state gallery. Guided Setup invokes the native bridge sequentially for workspace, playlist, and guide; the bridge discards native selections and returns only safe status DTOs. It does not validate, read, parse, import, persist, or use provider files for lineup work, and it does not package a tester release.

### GUI status tally

| Area                           | Status                  |
| ------------------------------ | ----------------------- |
| Workbench shell and navigation | Works now               |
| Guided Setup layout            | Preview only            |
| Native file-picker bridge      | Works now               |
| Display-safe selection state   | Works now               |
| Lineup review and saved lineup | Planned / not built yet |
| Automatic updates              | Planned / not built yet |
| File selection and validation  | Blocked / needs review  |

Use Node.js 22 LTS with npm 10, Rust/Cargo, the Tauri CLI, and WebView2:

```powershell
Set-Location gui
npm ci
npm run typecheck
npm test
npm run test:e2e
npm run test:visual
npm run build
cargo test --manifest-path src-tauri/Cargo.toml
npm run tauri build -- --no-bundle
```

The GUI owns presentation and the approved native picker boundary only at this stage. Do not add a second source-of-truth model, provider credential, or backend operation from this foundation slice. Any later operational integration must preserve the existing PowerShell behavior and redaction boundaries, and must be separately reviewed.
