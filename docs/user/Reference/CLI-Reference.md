# CLI Reference

ChannelForge has no GUI yet (see [Current Limitations](../CURRENT_LIMITATIONS.md)) — everything runs from PowerShell. This page lists the commands a user runs; for the full module API (functions used internally, like `Read-ChannelForgeProvider`), see the [Developer Guide](../../developer/DEVELOPER_GUIDE.md).

## `scripts/Build-Lineup.ps1`

The main build command. Run from the repository root:

```powershell
pwsh -File scripts/Build-Lineup.ps1
```

| Parameter       | Required | Default                            | Notes                                                                                                                                                                                        |
| --------------- | -------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Root`         | No       | Repository root                    | Where `data/` and `output/` are resolved from. You won't normally need to set this.                                                                                                          |
| `-ProviderPath` | No       | _(none — triggers auto-discovery)_ | Explicit override for which provider config file to use, relative to `data/providers/`. See [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md#advanced-pointing-at-a-specific-file). |

**Output:** `output/merged.m3u` (if at least one source has `enabled: true` and a `local_playlist`), `output/reports/build-summary.json`, `output/reports/lineup-plan.md`. See [Build Your First Lineup](../Build-Your-First-Lineup.md) for what these mean.

## `scripts/Build-My-Lineup.ps1`

The ChannelForge Guided Setup / Beginner Workflow entry point. It asks for an IPTV playlist (M3U), optionally asks for a TV guide (XMLTV), analyzes exact and ambiguous identities, and shows a proposal before publishing anything.

```powershell
pwsh -File scripts/Build-My-Lineup.ps1
```

A material ambiguous guide identity pauses for a choice: keep the channels but publish no guide, or cancel. The no-guide path is valid and never invents EPG data.

| Parameter          | Required | Notes                                                                                        |
| ------------------ | -------- | -------------------------------------------------------------------------------------------- |
| `-Root`            | No       | Repository root.                                                                             |
| `-M3UPath`         | No       | Playlist path. Omit it to be prompted.                                                       |
| `-XMLTVPath`       | No       | Optional guide path. Omit it, or answer blank at the prompt, for no guide.                   |
| `-Accept`          | No       | Publishes the reviewed lineup. Without it, only the proposal and result reports are written. |
| `-AmbiguousAction` | No       | `KeepWithoutGuide` or `Cancel`; omission prompts when ambiguity exists.                      |

**Output:** proposal and result reports under `output/reports/`; after explicit acceptance, use `output/guided-setup/accepted/lineup.m3u` and, when selected, `output/guided-setup/accepted/guide.xml`.

**Example — using an explicit provider file instead of auto-discovery:**

```powershell
pwsh -File scripts/Build-Lineup.ps1 -ProviderPath provider.local.json
```

## `scripts/Get-ChannelForgeSourceRefreshPlan.ps1`

Read-only planning evidence for configured provider and EPG sources. It reads configuration and validated disposable cache metadata without contacting any source.

```powershell
pwsh -File scripts/Get-ChannelForgeSourceRefreshPlan.ps1
```

For deterministic evaluation or a separate report location:

```powershell
pwsh -File scripts/Get-ChannelForgeSourceRefreshPlan.ps1 `
  -EvaluationTimeUtc 2026-01-01T00:00:00Z `
  -OutputRoot C:\private\reports
```

The plan reports `USE_VALID_CACHE`, `CONDITIONAL_REFRESH`, `FULL_REFRESH`, or `REVIEW`. It never creates a generation, publishes output, replaces the accepted pointer, or changes provider/downstream state.

**Output:** `output/reports/source-refresh-plan.json` and `output/reports/source-refresh-plan.md`.

## Verifying your environment

```powershell
Invoke-Pester ./tests/unit
```

Runs the full test suite. A clean run (`0` failures) confirms your environment matches what ChannelForge expects — see [INSTALL.md](../../reference/INSTALL.md).

```powershell
Import-Module ./src/ChannelForge/ChannelForge.psd1 -Force
```

Loads the ChannelForge module directly, useful if you want to call individual functions (like `Import-ChannelForgeM3UPlaylist`) yourself rather than running the full build.

## Other scripts

The repository has additional scripts (`Backup-IPTVBoss.ps1`, `Validate-Config.ps1`, `Validate-ConfigSchemas.ps1`, and other `Validate-*.ps1` quality-gate scripts) that are primarily developer/CI tooling rather than part of the everyday user workflow. See the [Developer Guide](../../developer/DEVELOPER_GUIDE.md#ci-quality-gates) if you need them.

## Where to go next

- Haven't run a build yet? → [Build Your First Lineup](../Build-Your-First-Lineup.md)
- Command failing? → [Troubleshooting](../TROUBLESHOOTING.md)
