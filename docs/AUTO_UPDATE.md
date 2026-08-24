# ChannelForge Auto-Update System

Status: merged standard and helper; current implementation documented below

ChannelForge uses a **manual, backup-first auto-update model**.

The updater checks GitHub Releases, reports whether a newer version exists, creates backups before replacement, validates downloaded release assets, and tells the user to restart after update.

## Current implementation status

The initial backup-first updater standard and standalone helper were merged in
[PR #23](https://github.com/Jumpstile/ChannelForge/pull/23). The implementation
and test coverage described below are the current repository state. Future
changes require normal scoped review and CI; this document is not release
certification or release evidence.

1. **No-release handling -- fixed**
   - `Get-ChannelForgeLatestReleaseInfo` catches a 404 from the releases/latest endpoint and returns `Found = $false` instead of throwing.
   - Verified live against `Jumpstile/ChannelForge` (which has no releases yet): `-CheckOnly` prints "No GitHub release is available yet for this repository." and exits 0.

2. **Broken zip copy path -- fixed**
   - `Copy-ChannelForgeUpdatePackageContent` enumerates extracted children with `Get-ChildItem -LiteralPath` and copies each one individually with `-LiteralPath`, instead of `Copy-Item -LiteralPath (Join-Path $extractPath '*')` (which silently copied zero files, since `-LiteralPath` does not expand `*`).

3. **Protected-data enforcement -- fixed**
   - `Test-ChannelForgeUpdateAllowedPath` is a fail-closed allowlist (`src`, `tools`, `scripts`, `schemas`, `engineering`, `docs`, `VERSION`, `README.md`, `LICENSE`, `CHANGELOG.md`). Any extracted top-level entry not on this list (including `data/`, `config/`, `output/`, `backups/`, secrets, and env files) is skipped and reported, never copied over the install root.
   - `New-ChannelForgeUpdateBackup` backs up only the same allowed names, so backup scope matches what an update can actually touch.
   - Verified with a real download+extract+copy run: pre-existing protected data (a fixture provider config under `data/`) survived untouched while allowed content was updated.

4. **Testability -- fixed**
   - All logic besides argument parsing and top-level orchestration now lives in `tools/ChannelForgeAutoUpdate.Core.psm1`, a side-effect-free module. `tools/Invoke-ChannelForgeAutoUpdate.ps1` is a thin orchestrator that imports it.
   - `tests/unit/ChannelForgeAutoUpdate.Core.Tests.ps1` covers no-release behavior, version parsing, asset selection, URL validation (URI-parsed, not `-like`), backup creation, protected-data allow/deny behavior, and an `-Apply -WhatIf` case asserting zero backup/download/replacement occurs.

## Destructive-path validation (`tests/unit/ChannelForgeAutoUpdate.DestructivePath.Tests.ps1`)

Nine tests, all passing, deliberately induce failure conditions and verify protected data is never modified, allowed content still installs correctly, a failure leaves the installation consistent, the backup remains usable, and temp files do not leak:

1. Corrupt zip -- rejected, install root and protected data untouched, backup preserved.
2. Missing expected package paths (zip has no recognized top-level content) -- reports "Skipped", correctly avoids claiming anything was updated, install root unchanged.
3. Attempted overwrite of protected `data/`/`config/` paths -- both are skipped and reported; pre-existing protected data (a fixture provider secret) survives byte-for-byte while allowed `src/` content from the same package still installs.
4. Read-only destination -- **documented finding, not a defect** (same underlying behavior as the TPM sibling module): `Copy-Item -Force` clears the `ReadOnly` attribute and overwrites the file rather than failing closed.
5. Backup failure -- aborts before any download; install root untouched.
6. Extraction failure (valid zip, corrupted entry payload) -- rejected, install root and protected data untouched, backup preserved.
7. Copy failure (destination file locked by another handle) -- rejected; protected data and backup intact.
8. No GitHub release still exits cleanly -- confirmed no exception, no filesystem changes.
9. Module-scope error-action regression guard -- **a real, previously undetected bug found while writing test 7**: this module's `$ErrorActionPreference` was never set explicitly, and is snapshotted from the caller at _import_ time. The orchestrator intentionally imports without `-Force` (to stay mockable), so an already-loaded module instance (e.g. from a test harness's own earlier import) silently kept whatever preference was active back then -- 'Continue' by default. Under 'Continue', a locked destination file during `Copy-ChannelForgeUpdatePackageContent`'s `Copy-Item` call printed a non-terminating warning and **the tool reported "Update installed successfully" while actually leaving the old file in place**. Fixed two ways: `$ErrorActionPreference = 'Stop'` is now set explicitly at the top of `ChannelForgeAutoUpdate.Core.psm1` itself (independent of import history), and `Copy-ChannelForgeUpdatePackageContent` now verifies each copied item actually exists at the destination afterward as defense in depth, matching the equivalent check already present in `New-TpmUpdateBackup`/`New-ChannelForgeUpdateBackup`.

## Safety model

ChannelForge must never silently replace files.

A check is read-only. An update is a deliberate user action.

## Required behavior

1. Show the local version.
2. Query the latest GitHub Release.
3. If no release exists yet, report that clearly and exit without failure noise.
4. Normalize release tags by trimming a leading `v`.
5. Compare local version and latest release version.
6. If current, report no update needed.
7. If newer, show release tag/name and selected asset.
8. On apply, create `UpdateBackups/<timestamp>/`.
9. Download the release asset to a temporary path.
10. Validate that the download exists and is non-empty.
11. Replace only allowed update targets.
12. Print backup path and restart instruction.

## Protected data

The updater must not overwrite or delete:

- user configs
- provider configs
- local rules
- generated lineups
- generated reports
- evidence caches
- secrets
- environment files

## Initial helper

The first helper is intentionally standalone:

```powershell
.\tools\Invoke-ChannelForgeAutoUpdate.ps1 -CheckOnly
.\tools\Invoke-ChannelForgeAutoUpdate.ps1 -Apply
```

This allows the behavior to be tested before adding user-facing command integration.

## Future integration

After packaging stabilizes, expose the helper through a normal ChannelForge command such as:

```powershell
Update-ChannelForge
```

That command should still be manual and backup-first.

## Relationship to TeknoParrot Manager

TeknoParrot Manager is the first implementation target for the Jumpstile backup-first updater pattern.

ChannelForge adopts the same standard, with additional protection for ChannelForge-specific local configuration and generated evidence artifacts.
