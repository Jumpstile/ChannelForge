# CLI Reference

ChannelForge has no GUI yet (see [Current Limitations](../CURRENT_LIMITATIONS.md)) — everything runs from PowerShell. This page lists the commands a user runs; for the full module API (functions used internally, like `Read-ChannelForgeProvider`), see the [Developer Guide](../../developer/DEVELOPER_GUIDE.md).

## `scripts/Build-Lineup.ps1`

The main build command. Run from the repository root:

```powershell
pwsh -File scripts/Build-Lineup.ps1
```

| Parameter | Required | Default | Notes |
|---|---|---|---|
| `-Root` | No | Repository root | Where `data/` and `output/` are resolved from. You won't normally need to set this. |
| `-ProviderPath` | No | *(none — triggers auto-discovery)* | Explicit override for which provider config file to use, relative to `data/providers/`. See [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md#advanced-pointing-at-a-specific-file). |

**Output:** `output/merged.m3u` (if at least one source has `enabled: true` and a `local_playlist`), `output/reports/build-summary.json`, `output/reports/lineup-plan.md`. See [Build Your First Lineup](../Build-Your-First-Lineup.md) for what these mean.

**Example — using an explicit provider file instead of auto-discovery:**

```powershell
pwsh -File scripts/Build-Lineup.ps1 -ProviderPath provider.local.json
```

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
