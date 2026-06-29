# Developer Guide

> Status: Living document

## Purpose

Explain how ChannelForge is organized and how developers should work in the repository.

## Audience

Developers and maintainers.

## Prerequisite

Read [ONBOARDING.md](../../ONBOARDING.md) and [FIRST_READ.md](FIRST_READ.md) before making changes.

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

| Step | What it checks | Local command |
|---|---|---|
| Config schemas | Every tracked `data/*.json` file matches its schema in `schemas/` | `./scripts/Validate-ConfigSchemas.ps1` |
| Markdown hygiene | No tracked `.md` file has the malformed-generator-artifact shape from the #2/#13/#16 incident | `./scripts/Validate-MarkdownHygiene.ps1` |
| Markdown links | Every relative link in a tracked `.md` file resolves to a real file | `./scripts/Validate-MarkdownLinks.ps1` |
| PSScriptAnalyzer | No Error-severity finding under `src/` or `scripts/` | `./scripts/Validate-ScriptAnalyzer.ps1` |
| Pester | Full unit test suite | `Invoke-Pester ./tests/unit -CI` |

Run all five locally before pushing — they're the same commands CI runs, so a clean local run means a clean CI run for everything except the secret scan.

### What's schema-level vs. runtime/domain-level

These checks validate **shape** ahead of time. They deliberately do not replace the **runtime/domain** checks that already exist in the module — both layers stay in place:

| Layer | Where | What it catches |
|---|---|---|
| Schema (`schemas/*.schema.json`, CI step "Config schemas") | Before a file is ever read | Missing/extra fields, wrong types |
| Runtime trust boundary (`Test-ChannelForgeSourceUrl`, `Read-ChannelForgeProvider`/`Read-ChannelForgeEpgSource`) | When a file is actually loaded | Malformed URLs, unsupported schemes, credentials, loopback/private/link-local hosts |
| Runtime write guardrails (`Assert-ChannelForgeWritePath`, `Assert-ChannelForgePathExists`, `Assert-ChannelForgeBackupSourcePath`) | When a script writes/reads/backs up a path | Writes outside an approved root, missing sources, overly broad backup sources |
| Static analysis (PSScriptAnalyzer, CI step "PSScriptAnalyzer") | Before code runs at all | Dangerous patterns, syntax-adjacent mistakes (Error severity only — see below) |
| Tests (Pester) | On every change | Behavior regressions across all of the above |

A file can pass schema validation and still be rejected at runtime — see `tests/unit/ConfigSchemas.Tests.ps1`'s "Schemas supplement, not replace, runtime validation" cases for a working example. Don't loosen a runtime check because "the schema already validates this"; they check different things.

### PSScriptAnalyzer: why only Error severity fails CI

`Validate-ScriptAnalyzer.ps1` runs at Error, Warning, and Information severity and prints everything, but only an **Error**-severity finding fails the check. As of this writing the codebase has ~50 accepted Warning/Information findings (`Write-Host` usage in `scripts/`, a few naming/`ShouldProcess` conventions in older functions) that aren't worth a sweeping unrelated refactor just to satisfy a new CI gate. Gating on Error severity still catches real mistakes without that noise. If you fix one of the existing Warning findings as part of unrelated work, that's welcome — just don't feel obligated to fix all of them to pass CI.

### Deferred: full Markdown style linting, anchor resolution, external link checks

Three related ideas were considered and intentionally **not** implemented, to keep this pipeline low-noise:

- **A general Markdown style linter** (e.g. markdownlint) would surface many pre-existing, unrelated heading/style inconsistencies across `docs/` and would need a dedicated cleanup pass before it could be a CI gate without immediately failing on day one. `Validate-MarkdownHygiene.ps1` is intentionally narrow instead — it only re-detects the exact failure shape from a real past incident.
- **Resolving `#anchor` fragments in links** (confirming a heading actually exists, not just the file) requires replicating the renderer's exact heading-to-slug rule, which is a common source of false positives. `Validate-MarkdownLinks.ps1` checks that the target file exists and explicitly ignores anchors.
- **Checking external `http(s)` links resolve** would make CI depend on network access and third-party sites' uptime, which is the opposite of deterministic. Not implemented; `Validate-MarkdownLinks.ps1` skips `http(s)`/`mailto` targets entirely.

## Public functions today

| Function | Purpose |
|---|---|
| `Read-ChannelForgeProvider` | Load provider source definitions from `provider.json` |
| `Read-ChannelForgeEpgSource` | Load EPG source definitions from `epg_sources.json`, sorted by priority |
| `Import-ChannelForgeM3UPlaylist` | Parse an M3U playlist into `Channel` objects |
| `Resolve-ChannelForgeAlias` | Deterministic, exact-match alias resolution |
| `New-ChannelForgeChannel` | Construct a `Channel` domain object |
| `New-ChannelForgeBuildContext` | Construct a `BuildContext` domain object |
| `ConvertTo-ChannelForgeNormalizedChannel` | Apply name normalization to a `Channel` |
| `Assert-ChannelForgeWritePath` | Throw unless a target path resolves under an explicitly approved root |
| `Assert-ChannelForgePathExists` | Throw unless a required file/directory exists, with a clear description |
| `Assert-ChannelForgeBackupSourcePath` | Throw if a backup source is a drive root or well-known system directory |

See [ARCHITECTURE.md](../architecture/ARCHITECTURE.md) for how these fit together.

## Write guardrails

`Assert-ChannelForgeWritePath`, `Assert-ChannelForgePathExists`, and `Assert-ChannelForgeBackupSourcePath` exist so that anything writing to disk — inside the module or in `scripts/` — has to state its intent rather than trusting a path by default (see issue #5, [ADR 0004](../adr/0004-self-healing-with-guardrails.md)). `scripts/Build-Lineup.ps1` and `scripts/Backup-IPTVBoss.ps1` both import the module and call these before every write:

- Every write target is checked with `Assert-ChannelForgeWritePath -Path <target> -AllowedRoot <root>`. There is no default root; the caller must name the approved area (e.g. the project's `output/` or `backups/` folder), so a write can never silently land somewhere unintended.
- Every required input path is checked with `Assert-ChannelForgePathExists` before it's read from or backed up, so a missing path fails with a clear error instead of producing an empty or corrupt downstream result.
- `Backup-IPTVBoss.ps1` additionally calls `Assert-ChannelForgeBackupSourcePath` to reject a backup source that exists but is dangerously broad (a drive root, or a well-known system directory directly under one) — existence alone doesn't catch a misconfigured path pointed at the whole machine.
- `Backup-IPTVBoss.ps1` refuses to overwrite an existing backup archive unless `-Force` is passed explicitly.

## Report redaction

Generated reports (`output/reports/build-summary.json`, `output/reports/lineup-plan.md`) must never contain full provider/EPG URLs, tokens, account IDs, credentials, or other secret-like values (see [SECURITY.md](../reference/SECURITY.md)). `Build-Lineup.ps1` lists provider sources by name and enabled state only — never by `url` — and the Pester suite asserts this directly (`tests/unit/BuildLineupScript.Tests.ps1`) using fixture data shaped like a real token-bearing URL, so a regression that reintroduces a URL into the report fails CI.

## Private helpers today

- `Normalize-ChannelForgeName` — strips quality tags (`HD`, `4K`, ...) and backup/alternate markers from playlist channel names.
- `Test-ChannelForgeSourceUrl` — validates provider/EPG source URLs (scheme, host, no embedded credentials, no loopback/private/link-local targets).
- `Test-ChannelForgeDisallowedIpAddress` — IP-range check used by `Test-ChannelForgeSourceUrl`.
- `Test-ChannelForgeWritePath` — path-safety check used by `Assert-ChannelForgeWritePath`.
- `Test-ChannelForgeBackupSourcePath` — rejects drive roots and well-known system directories, used by `Assert-ChannelForgeBackupSourcePath`.

## Configuration schemas

Every tracked source-of-truth JSON file under `data/` has a JSON Schema (draft-07) contract in `schemas/` (see issue #3):

| Data file | Schema |
|---|---|
| `data/providers/mybunny.json`, `data/providers/provider.example.json` | `schemas/provider.schema.json` |
| `data/epg/epg_sources.json`, `data/epg/epg_sources.example.json` | `schemas/epg_sources.schema.json` |
| `data/lineup/locals.json` | `schemas/locals.schema.json` |
| `data/lineup/numbering_blocks.json` | `schemas/numbering_blocks.schema.json` |
| `data/lineup/categories.json` | `schemas/categories.schema.json` |
| `data/rules/aliases.json` | `schemas/aliases.schema.json` |

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
