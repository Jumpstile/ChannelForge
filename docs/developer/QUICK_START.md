# Quick Start

> Status: Living document

## Purpose

Verify your development environment can run and test the ChannelForge module — tests pass, the module imports, and a sample playlist parses correctly. This is a developer/contributor environment check, not a guide to building a real lineup; for that, see [Build Your First Lineup](../user/Build-Your-First-Lineup.md).

## Audience

Developers and contributors setting up the repository for the first time.

## Before you begin

Complete the setup in [INSTALL.md](../reference/INSTALL.md): PowerShell 7+, Git, Pester 5.7.1, and a local clone of the repository. Then read [ONBOARDING.md](../../ONBOARDING.md) and [FIRST_READ.md](FIRST_READ.md).

## 1. Open PowerShell 7

Launch `pwsh` (not the older Windows PowerShell `powershell.exe`). Confirm the version:

```powershell
$PSVersionTable.PSVersion
```

You should see major version 7 or higher.

## 2. Move into the repository

```powershell
cd path\to\ChannelForge
```

Replace `path\to\ChannelForge` with wherever you cloned the repository.

## 3. Run the tests

```powershell
Invoke-Pester ./tests/unit
```

**What success looks like:** every test reports `Passed`, with `0` failures in the summary at the end. This confirms the module behaves the way the project expects on your machine.

## 4. Import the module

```powershell
Import-Module ./src/ChannelForge/ChannelForge.psd1 -Force
```

**What success looks like:** the command returns with no output and no errors.

## 5. Run the sample M3U parser

```powershell
Import-ChannelForgeM3UPlaylist -Path ./tests/fixtures/tiny.m3u
```

**What success looks like:** the command prints one or more `Channel` objects with fields like `DisplayName`, `TvgId`, and `Group` populated from the sample playlist.

## If something fails

- Re-read the command for typos, especially the `-Path` value.
- Confirm you're running from the repository root (`./tests/fixtures/tiny.m3u` must resolve).
- Check [INSTALL.md](../reference/INSTALL.md)'s troubleshooting table.
- If the problem persists, open a GitHub Issue describing what you ran and what happened.

## What's next

- Read [THE_CHANNELFORGE_WAY.md](../user/THE_CHANNELFORGE_WAY.md) to understand the project's mindset.
- Read [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md) before making changes.
