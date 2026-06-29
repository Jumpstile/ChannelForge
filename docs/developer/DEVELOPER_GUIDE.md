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

## CI

GitHub Actions (`.github/workflows`) runs on every push and pull request to `main`:

1. **Secret scan** — Gitleaks scans the repository and available history for committed secrets before tests run.
2. **Tests** — installs Pester 5.7.1 on `windows-latest` and runs `Invoke-Pester ./tests/unit -CI`.

Both jobs must pass before a change is considered mergeable. See [SECURITY.md](../reference/SECURITY.md) for what to do if the secret scan finds something.

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

`schemas/provider.schema.json` and `schemas/epg_sources.schema.json` are JSON Schema (draft-07) contracts for `data/providers/*.json` and `data/epg/*.json` files (see issue #3). They validate **structure only** — required/optional fields, types, and the EPG `role` enum — using PowerShell's built-in `Test-Json -SchemaFile`, so there's no new dependency:

```powershell
Test-Json -Path data/providers/provider.example.json -SchemaFile schemas/provider.schema.json
Test-Json -Path data/epg/epg_sources.example.json -SchemaFile schemas/epg_sources.schema.json
```

What the schemas deliberately do **not** do: enforce the URL trust-boundary rules (scheme allowlist, no embedded credentials, no loopback/private/link-local hosts). That validation stays in `Test-ChannelForgeSourceUrl` and runs at read time in `Read-ChannelForgeProvider`/`Read-ChannelForgeEpgSource` regardless of whether a file already passed schema validation — a file can be schema-valid and still get rejected at runtime (see `tests/unit/ConfigSchemas.Tests.ps1`, which asserts exactly that for both fixtures). Schemas catch shape mistakes early (a contributor typo, a missing field) before a file ever reaches the parser; they are a second, earlier check, not a replacement for the trust-boundary one.

`schemas/` currently covers provider and EPG sources only. `data/lineup/*` and `data/rules/aliases.json` don't have schemas yet — that's deferred, not forgotten (see #3).

CI does not run schema validation yet; today it's enforced only through the Pester tests in `tests/unit/ConfigSchemas.Tests.ps1`, which run as part of the existing `Invoke-Pester ./tests/unit -CI` step. Adding a dedicated schema-validation CI step (so a malformed tracked config file fails fast, before the full test run) is in scope for issue #4 and hasn't been done here.

## Development workflow

Follow [CONTRIBUTING.md](../../CONTRIBUTING.md) for the branch, commit, and review workflow. This guide covers where code lives and how to verify it; CONTRIBUTING.md covers the process around a change.
