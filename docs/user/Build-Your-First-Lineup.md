# Build Your First Lineup

## What you need

- PowerShell 7.6 or newer (Core edition).
- One IPTV playlist file in M3U format.
- An XMLTV guide file if you want guide data. Press Enter at the guide prompt to continue without one.
- Git and Pester 5.7.1 only if you are validating the checkout.
  M3U is the channel playlist; XMLTV is optional programme and guide data.

Your playlist and guide are private input. Keep them local; never commit or paste their contents into an issue.

## One safe flow

The ChannelForge Guided Setup / Beginner Workflow asks for the two inputs, analyzes them, and creates a read-only candidate plan. The plan is eligible for saving only when native matching reports **Checked**: every playlist entry has exactly one guide identity match. Needs-attention, review-needed, blocked, checking, not-checked, stale, and unavailable states are save-blocking.

```text
IPTV playlist (M3U) + optional TV guide (XMLTV)
             │
             ▼
     candidate + read-only plan
             ├─ GUI: explicit acknowledgement → native acceptance boundary
             └─ CLI: -Accept → native acceptance boundary
```

The native acceptance boundary revalidates the candidate, accepted parent, input fingerprints, and preconditions before staging and publishing. React does not promote files, update an accepted pointer, or maintain a second accepted-state model.

Run it from the repository root:

```powershell
pwsh -File scripts/Build-My-Lineup.ps1
```

The script prompts for the playlist path and optional guide path. For a repeatable or automated run, provide the paths explicitly:

```powershell
pwsh -File scripts/Build-My-Lineup.ps1 `
  -M3UPath C:\private\playlist.m3u `
  -XMLTVPath C:\private\guide.xml
```

Review the proposal in `output/reports/guided-setup-plan.md`. Nothing is accepted yet. If it is correct, rerun with `-Accept`. For the CLI, a material ambiguous identity prompts whether to keep the channels but publish no guide or cancel; it never guesses which guide entry belongs to a channel. The GUI uses the native cancel-on-ambiguity boundary.
If an accepted lineup already has a guide, the safe result for a later ambiguous guide is cancellation; the existing accepted guide remains unchanged.

```powershell
pwsh -File scripts/Build-My-Lineup.ps1 `
  -M3UPath C:\private\playlist.m3u `
  -XMLTVPath C:\private\guide.xml `
  -Accept
```

For a deterministic no-guide run, omit `-XMLTVPath`:

```powershell
pwsh -File scripts/Build-My-Lineup.ps1 `
  -M3UPath C:\private\playlist.m3u `
  -Accept
```

## What you'll have at the end

- An accepted M3U lineup and, when selected, an accepted XMLTV guide.
- A concise proposal and success/failure summary in `output/reports/`.
- Stable consumer files: `output/guided-setup/accepted/lineup.m3u` and `output/guided-setup/accepted/guide.xml` when a guide is selected.
- Existing accepted output preserved when input, review, or publication fails.

The flow reuses the existing M3U/XMLTV importers and safe publication boundary. It does not modify provider accounts, provider state, or downstream players.
If the accepted lineup publishes but the stable consumer view cannot be refreshed, the accepted lineup remains authoritative; rerun the command to refresh the consumer files.

## GUI saved lineup

The GUI's Lineup Review page shows aggregate coverage first. Select **Prepare save** to request a native, read-only candidate plan. Only a **Checked** result with a ready plan enables **Save lineup**. Needs-attention (including guide-only coverage), review-needed, blocked, checking, not-checked, stale, or unavailable results cannot be saved.

**Save lineup** opens an accessible confirmation dialog. The save button remains disabled until you acknowledge that the aggregate review is correct. Cancel, Escape, closing the dialog, or leaving the acknowledgement unchecked performs no native acceptance call and does not mutate accepted state. On confirmation, the native bridge revalidates and owns staging, the journal, accepted pointer, recovery, and accepted-state authority.

After native success, the GUI exposes **Your saved lineup** as a read-only accepted-state view. It does not export, schedule, release, publish to a target, or distribute tester artifacts. The GUI never displays channel identities, programme titles, stream URLs, paths, hashes, generation IDs, provider credentials, or raw native output.

## Preview source refresh readiness

To see what a future refresh would need without contacting any provider, run:

```powershell
pwsh -File scripts/Get-ChannelForgeSourceRefreshPlan.ps1
```

The command reads configured sources and validated disposable cache metadata only. It writes `output/reports/source-refresh-plan.json` and `output/reports/source-refresh-plan.md`. A cache is a previously downloaded copy ChannelForge can safely reuse; a validator is ETag or Last-Modified information that can make a later remote check conditional.

This is a read-only plan. It does not fetch sources, publish a lineup, create a generation, replace the accepted pointer, or change provider or downstream state. Local and disabled sources are reported but are not planned for unattended network work.

## Run a one-shot source refresh

After configuring remote sources, refresh disposable source cache evidence without publishing a lineup:

```powershell
pwsh -File scripts/Invoke-ChannelForgeSourceRefresh.ps1
```

The command reuses fresh validated caches, performs a **conditional refresh** for expired caches with ETag or Last-Modified evidence, and performs a full refresh when no validator is available. A conditional refresh asks whether previously downloaded content changed. A **last-known-good** cache is the most recent validated source copy ChannelForge keeps using when a new refresh cannot be trusted.

If a request fails or its response is empty, malformed, unsafe, or otherwise invalid, the working last-known-good cache is preserved. The command writes `output/reports/source-refresh-result.json` and `output/reports/source-refresh-result.md`. It does not publish a lineup, create a generation, replace the accepted pointer, or change downstream state.

The JSON result uses `source-refresh-result/v2`. Each source has a machine-readable `Classification`: `AutoHandled` means validated cache evidence was reused or refreshed, `Degraded` means a failed refresh preserved last-known-good data, `ReviewNeeded` means no safe usable result remains, and `NoAction` means the source is intentionally disabled or local. `ReviewNeeded` and `ReviewNeededCount` summarize only sources classified as `ReviewNeeded`; cache data remains disposable and does not become accepted lineup authority.

## Preview the scheduled refresh plan

To evaluate the daily schedule and notification result without starting a scheduler or contacting a source, run:

```powershell
pwsh -File scripts/Get-ChannelForgeScheduledRefreshPlan.ps1
```

The planner uses `config/scheduled-refresh.local.json` when present and otherwise uses the safe tracked example policy. It consumes the existing `source-refresh-result/v2` report, validates its classifications and review counts, calculates the UTC cadence/window/jitter, and writes:

```text
output/reports/scheduled-refresh-plan.json
output/reports/scheduled-refresh-plan.md
```

This is report-only evidence. It does not acquire a lock, start a worker, fetch a source, mutate a cache, create accepted state or a generation, replace a pointer, or publish M3U/XMLTV output.

An explicit manual plan is allowed while scheduling is disabled and outside the scheduled window:

```powershell
pwsh -File scripts/Get-ChannelForgeScheduledRefreshPlan.ps1 `
  -TriggerKind Manual
```

Manual planning does not consume the next scheduled cadence slot. `AutoHandled` and `NoAction` remain quiet; `Degraded` becomes a warning only after its configured repeated-run threshold; `ReviewNeeded` interrupts for a new issue and remains active when an unchanged duplicate is suppressed.

## Expert/local configuration path

The lower-level `scripts/Build-Lineup.ps1` command remains available for configured multi-source builds. It reads the safe local provider configuration and writes the detailed build reports described below. Use it when you need multiple configured sources or technical controls.

## Repository validation

```powershell
git clone https://github.com/Jumpstile/ChannelForge.git
cd ChannelForge
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck
Invoke-Pester ./tests/unit
```

A clean test run (`0` failures) means your environment matches what ChannelForge expects.

## Step 1: Set up your provider configuration — locally, never tracked

**Never edit `data/providers/mybunny.json`.** That file is a tracked, public example/fixture — anything real you put in it could end up committed and exposed.

The short version: copy `data/providers/provider.example.json` to `data/providers/provider.local.json`, edit the copy with your real source(s), and ChannelForge will automatically use it instead of the tracked example — no flag, no edit to anything tracked. See [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md) for the full walkthrough, including what to do if you have more than one local config and how to avoid leaking secrets into reports.

## Step 2: Place your playlist file (local option)

Copy your `.m3u` file into `data/playlists/`, with a filename ending in `.local.m3u` (that suffix is what keeps Git from ever tracking it):

```text
data/playlists/sports.local.m3u
```

A real playlist file contains real stream URLs — treat it exactly like a password. Never commit it, paste it into an issue, or share it in chat.

Your `provider.local.json` source entry then needs `local_playlist` pointing at this file (see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md)). When `local_playlist` is omitted, an enabled source can instead use the configured remote M3U URL through the bounded HTTPS/443 path and disposable 24-hour cache; local input remains authoritative when both are present.

## Step 3: Run the build

From the repository root:

```powershell
pwsh -File scripts/Build-Lineup.ps1
```

## Step 4: Verify your output

```text
output/merged.m3u                       ← your playable lineup
output/reports/build-summary.json       ← machine-readable: channel count, SHA-256 checksum
output/reports/lineup-plan.md           ← human-readable summary
```

Check `build-summary.json` for `M3UGenerated: true` and a `ChannelCount` that looks right. The `M3USha256` checksum lets you confirm the file wasn't altered, and re-running the build from the same inputs always produces the identical file — that's what "deterministic" means in practice. Neither report contains a provider URL, account ID, or token, even though `merged.m3u` itself does (it has to, to be playable).

`output/` is disposable — it's fine to delete it and rebuild at any time.

## What success looks like

Here's a real `build-summary.json` from a successful run with one source and two channels (URLs are `example.invalid` placeholders for illustration — yours will have your real provider's data, which is exactly why this report never includes them):

```json
{
  "GeneratedAt": "2026-06-30T17:34:56",
  "Provider": "my-provider",
  "M3USources": 1,
  "EPGSources": 0,
  "LocalChannels": 1,
  "NumberingBlocks": 1,
  "M3UGenerated": true,
  "M3UPath": "output/merged.m3u",
  "M3USha256": "d938a228b2bcc2bfb91f3e25a7cf2431fa201daf2d2bf7aea014ef4a1918b998",
  "ChannelCount": 2,
  "DuplicateCount": 0,
  "WarningCount": 0,
  "XMLTVStatus": "NOT_CONFIGURED",
  "XMLTVGenerated": false,
  "XMLTVPath": null,
  "XMLTVSha256": null,
  "XMLTVDeferredReason": "No enabled XMLTV source is configured.",
  "XMLTVFailureReason": null,
  "Status": "M3U_GENERATED"
}
```

The signals that this M3U-only run succeeded are `"M3UGenerated": true`, `"Status": "M3U_GENERATED"`, a `ChannelCount` greater than zero, and a `M3USha256` value. This example intentionally has no enabled XMLTV source. An enabled local XMLTV path or a supported remote HTTPS XMLTV source instead produces `XMLTVStatus: GENERATED` and `XMLTVPath: output/merged.xml` after validation and deterministic merge/export.

The matching `lineup-plan.md` for the same run:

```markdown
# ChannelForge Build Summary

Generated: 2026-06-30T17:34:56

Merged M3U: output/merged.m3u (2 channels, 0 duplicates excluded, 0 warnings, SHA-256 d938a228b2bcc2bfb91f3e25a7cf2431fa201daf2d2bf7aea014ef4a1918b998)

## XMLTV Result

- XMLTV output: deferred. No enabled XMLTV source is configured.

Known limitations:

- Remote provider/EPG acquisition: bounded HTTPS on port 443 only; no redirects, proxies, credentials, retries, or stale/offline success.
- Target-specific Plex EPG/guide assignment: deferred; exact M3U/XMLTV identity bindings are reported separately and generated XMLTV remains a separate output.

## Provider M3U Sources

- Sports (enabled, local playlist configured)

## EPG Sources

- [10] Public EPG - primary

## Local Channels

- 2 - WCBS CBS New York

## Numbering Blocks

- 400-410: Sports - sports block
```

If your real run's `build-summary.json` matches this shape — `M3UGenerated: true`, a sensible `ChannelCount`, no `https://` anywhere in either report — your first lineup succeeded.

## What's next

- Want to see this in Plex? → [Use ChannelForge with Plex](Use-With-Plex.md)
- Curious what doesn't work yet? → [Current Limitations](CURRENT_LIMITATIONS.md) covers it honestly.

## If something goes wrong

- `Refusing to read from outside the approved location` — a path in your config points outside the folder it's allowed to (most often a `local_playlist` value). Fix the path; this check exists to stop accidental or malicious path traversal.
- `Multiple local provider files found` — you have more than one `data/providers/*.local.json`. Keep exactly one, or see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md#advanced-pointing-at-a-specific-file) for the explicit override.
- No channels in `merged.m3u` — check your source is `enabled: true` and has either a usable `local_playlist` or a supported remote `url`; an enabled source missing both fails closed with a configuration error instead of being silently skipped. This validation occurs before the build reports are created.
