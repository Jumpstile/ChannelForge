# ADR-0006: Backup-First Auto-Update Standard

Status: Proposed
Date: 2026-07-01

## Context

ChannelForge will eventually be distributed to users who need safe, repeatable updates without losing local configuration, generated outputs, or user-authored rules.

The project already treats recoverability, determinism, and evidence as core engineering pillars. An updater must follow the same model.

TeknoParrot Manager is implementing the first Jumpstile backup-first updater. ChannelForge should use the same standard so future Jumpstile PowerShell tools behave consistently.

## Decision

ChannelForge will use a **manual, backup-first auto-update model**.

The updater may check GitHub Releases and report whether a newer release exists. It must not replace local files unless the user explicitly requests an update.

Before replacement, the updater must create a timestamped local backup of every file it intends to replace. If backup creation fails, the update must abort.

The first implementation should be a standalone helper script under `tools/` before any command or UX integration is added.

## Required properties

1. **Manual execution**
   - No silent self-update.
   - No scheduled updater.
   - No startup updater.
   - No background update service.

2. **Backup before modification**
   - Backups go under `UpdateBackups/<timestamp>/`.
   - The updater must fail closed if backup creation fails.

3. **GitHub Releases as source of truth**
   - Release metadata comes from the repository's GitHub Releases API.
   - Assets must come from the expected repository release URL prefix.
   - Arbitrary URLs are refused.

4. **No same-session execution of downloaded code**
   - After update, the user restarts the tool.
   - The current process does not import or execute the downloaded code.

5. **Config preservation**
   - User config, local rules, generated outputs, and evidence caches are not overwritten by updater code unless a future migration ADR explicitly permits it.

6. **Testability**
   - Version comparison must be testable without network access.
   - Asset-selection and URL validation must be testable without network access.
   - Backup behavior must be testable in a temporary folder.

## Consequences

- Updates are safer and more explainable, but not fully automatic.
- Release packaging becomes important because the updater depends on predictable assets.
- Future installer/package work can build on this standard rather than replacing it.

## Initial commands

Planned standalone helper:

```powershell
.\tools\Invoke-ChannelForgeAutoUpdate.ps1 -CheckOnly
.\tools\Invoke-ChannelForgeAutoUpdate.ps1 -Apply
```

## Non-goals

- No system-wide installer.
- No update daemon.
- No automatic scheduled update.
- No update from non-GitHub sources.
- No destructive cleanup of user data.
