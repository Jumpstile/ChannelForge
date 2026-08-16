# Build Your First Lineup

This walks you from a fresh clone to a real, playable `merged.m3u` file, using your own provider playlist — without ever touching a tracked repository file.

```text
your provider's M3U file              ChannelForge                 what you get
──────────────────────────  ──►  scripts/Build-Lineup.ps1  ──►  output/merged.m3u
  (saved locally,                 (parses, dedupes,                + a build report
   never committed)                 numbers, merges)                  you can verify
```

## What you'll have at the end

- A deterministic, deduplicated `output/merged.m3u` file built from your own playlist(s).
- A build report telling you exactly what happened — channel counts, a checksum, and any warnings — with no secrets in it.
- Nothing written to a tracked repository file, and nothing committed.

## Before you start

You need:

- **PowerShell 7.6 or newer, Core edition**, **Git**, and **Pester 5.7.1**.
- A real M3U playlist file already saved to disk (exported or downloaded from your provider however you normally would — ChannelForge doesn't fetch it for you yet).

Full install steps and a troubleshooting table are in [INSTALL.md](../reference/INSTALL.md) — this page won't repeat them, only summarize:

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

## Step 2: Place your playlist file

Copy your `.m3u` file into `data/playlists/`, with a filename ending in `.local.m3u` (that suffix is what keeps Git from ever tracking it):

```text
data/playlists/sports.local.m3u
```

A real playlist file contains real stream URLs — treat it exactly like a password. Never commit it, paste it into an issue, or share it in chat.

Your `provider.local.json` source entry then needs `local_playlist` pointing at this file (see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md)).

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
  "EPGSources": 1,
  "LocalChannels": 1,
  "NumberingBlocks": 1,
  "M3UGenerated": true,
  "M3UPath": "output/merged.m3u",
  "M3USha256": "d938a228b2bcc2bfb91f3e25a7cf2431fa201daf2d2bf7aea014ef4a1918b998",
  "ChannelCount": 2,
  "DuplicateCount": 0,
  "WarningCount": 0,
  "XMLTVStatus": "DEFERRED_REMOTE_ONLY",
  "XMLTVGenerated": false,
  "XMLTVPath": null,
  "XMLTVSha256": null,
  "XMLTVDeferredReason": "Remote XMLTV acquisition is deferred; no local XMLTV source was processed.",
  "XMLTVFailureReason": null,
  "Status": "M3U_GENERATED"
}
```

The signals that this M3U-only run succeeded are `"M3UGenerated": true`, `"Status": "M3U_GENERATED"`, a `ChannelCount` greater than zero, and a `M3USha256` value. Because the example uses only a remote EPG URL, `"XMLTVStatus": "DEFERRED_REMOTE_ONLY"` and `"XMLTVGenerated": false` are expected. An enabled local XMLTV path instead produces `XMLTVStatus: GENERATED` and `XMLTVPath: output/merged.xml`.

The matching `lineup-plan.md` for the same run:

```markdown
# ChannelForge Build Summary

Generated: 2026-06-30T17:34:56

Merged M3U: output/merged.m3u (2 channels, 0 duplicates excluded, 0 warnings, SHA-256 d938a228b2bcc2bfb91f3e25a7cf2431fa201daf2d2bf7aea014ef4a1918b998)

## XMLTV Result

- XMLTV output: deferred. Remote XMLTV acquisition is deferred; no local XMLTV source was processed.

Known limitations:

- Live HTTP provider/EPG fetch: deferred. Only local M3U and configured local XMLTV files are read.
- Plex EPG/guide binding: deferred; generated XMLTV is a separate output.

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
- No channels in `merged.m3u` — check your source is `enabled: true` and has a `local_playlist` set; a source missing either is silently skipped (not an error) in the current build pipeline.
