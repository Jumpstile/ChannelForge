# Windows packaging (developer)

This page covers the Windows x64 portable bundle. For install steps as a user, see [INSTALL-WINDOWS.md](../user/INSTALL-WINDOWS.md).

## What the build script does

`scripts/Build-ChannelForgeWindowsPackage.ps1`:

1. Checks that the source tree is a git checkout and that `HEAD` matches `-SourceCommitSha` (if given). It refuses a dirty tree unless you pass `-AllowDirty` (local development only).
2. Gets the pinned PowerShell win-x64 portable ZIP (the official release download, or the file you give with `-PowerShellRuntimeZipPath`) and checks its SHA-256.
3. Copies the shipped files into a staging folder, and scans the staged text for credential URLs and tokens. A hit fails the build.
4. Runs the bundled `pwsh.exe` once, then writes `package-manifest.json` with the length and SHA-256 of every file.
5. Re-checks the staged folder against the manifest, then writes a deterministic ZIP and a `.evidence.json` file next to it.

At start, `Start-ChannelForge.ps1` checks the bundled `pwsh.exe` against the manifest (length and SHA-256 only, not the whole runtime). A mismatch stops with "The bundled PowerShell does not match this ChannelForge package. Reinstall ChannelForge." A folder with no manifest (a developer checkout) skips the check.

## How to run it

Build the GUI first (`npm run build` in `gui`), commit your changes, then from the repo root in PowerShell 7:

```powershell
./scripts/Build-ChannelForgeWindowsPackage.ps1
```

Output goes to `output/packages/` by default (`-OutputRoot` changes it). The ZIP is named `ChannelForge-v<VERSION>-alpha.1-windows-x64.zip`.

## What ships

- `src/ChannelForge`, `gui/dist`, `schemas`, `tools`
- `data/rules/aliases.json` and `data/lineup/numbering_blocks.json`
- the bundle scripts, the four `.cmd` launchers, `README.md`, `LICENSE`, `VERSION`
- the user docs listed in the build script, and only the screenshots those docs reference
- `runtime/pwsh` (the pinned PowerShell) and `package-manifest.json`

## What must never ship

State, config, output, cache and log folders, test results, `.git`, `node_modules`, local data files such as provider files, any build-machine path, and any credential. The build tests below check these.

## No release, no tag

The script only writes files under the output folder. It never creates a release or a tag, and it does not upload anything. Publishing is a separate, owner-approved step.

## Run the build tests

From the repo root in PowerShell 7 with Pester 5:

```powershell
Invoke-Pester -Path tests/unit/ChannelForgeWindowsPackageBuild.Tests.ps1
Invoke-Pester -Path tests/unit/ChannelForgeWindowsPackage.Tests.ps1
Invoke-Pester -Path tests/unit/ChannelForgeLauncher.Tests.ps1
```

The build tests use a temp copy of the source and a copy of the running pwsh as the runtime, so they do not download anything and never change your checkout. They do not replace a smoke test on a clean Windows PC; that is still pending.
