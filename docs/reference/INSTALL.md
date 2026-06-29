# Install

> Status: Living document

## Purpose

Explain how to set up the ChannelForge development environment.

## Audience

Users and developers installing ChannelForge.

## Requirements

- **PowerShell 7 or later.** Check your version:

  ```powershell
  $PSVersionTable.PSVersion
  ```

  If it reports a major version below 7, install PowerShell 7 from [Microsoft's PowerShell releases](https://github.com/PowerShell/PowerShell/releases) and launch it as `pwsh` instead of `powershell`.

- **Git**, to clone the repository.

- **Pester 5.7.1**, the test framework ChannelForge uses. Install it for the current user:

  ```powershell
  Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck
  ```

## Clone the repository

```powershell
git clone https://github.com/Jumpstile/ChannelForge.git
cd ChannelForge
```

## Import the module

From the repository root:

```powershell
Import-Module ./src/ChannelForge/ChannelForge.psd1 -Force
```

If this succeeds without errors, the module's classes, private helpers, and public functions all loaded correctly.

## Run the tests

```powershell
Invoke-Pester ./tests/unit
```

A clean run with no failures means your environment matches what CI expects.

## Try a sample import

The repository ships a small fixture playlist for manual verification:

```powershell
Import-ChannelForgeM3UPlaylist -Path ./tests/fixtures/tiny.m3u
```

This should return `Channel` objects without errors.

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `Import-Module` reports a parse error | Wrong PowerShell version | Confirm `$PSVersionTable.PSVersion` is 7 or later |
| `Install-Module` fails with a trust prompt | PSGallery not yet trusted | Run `Set-PSRepository -Name PSGallery -InstallationPolicy Trusted` first |
| `Invoke-Pester` reports "command not found" | Pester not installed for this user, or wrong version | Re-run the install command above with `-Force` |
| A `Read-ChannelForge*` function throws "file not found" | Wrong working directory | Run commands from the repository root, or pass an absolute `-Path` |

If a problem isn't covered here, check [LESSONS_LEARNED.md](../../LESSONS_LEARNED.md) or open a GitHub Issue.
