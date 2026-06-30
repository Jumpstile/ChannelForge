# First Plex Smoke Test

> Status: Living document

## Purpose

Walk through the first real, hands-on test of a ChannelForge-merged M3U in Plex, using your own local provider playlist. This exercises the Phase 1 pipeline from [issue #7](https://github.com/Jumpstile/ChannelForge/issues/7): local playlist in, deterministic `output/merged.m3u` out.

## Before you start

Read [SECURITY.md](../reference/SECURITY.md) and [data/playlists/README.md](../../data/playlists/README.md) first. A real M3U playlist can contain real stream URLs. Treat it like a password: never commit it, never paste it into an issue, chat, or this repository's docs.

## 1. Get a real local M3U file

You need an `.m3u` file already saved to disk. This guide does not fetch one for you — ChannelForge has no live HTTP fetch yet (see "What won't work yet" below). Export or download one from your existing provider/service however you normally would.

## 2. Place it under `data/playlists/`

Copy it into `data/playlists/`, and name it so it ends in `.local.m3u` — that suffix is what `.gitignore` excludes, so this is the only thing standing between you and accidentally committing a real playlist. For example:

```text
data/playlists/sports.local.m3u
```

`Build-Lineup.ps1` will refuse to read a `local_playlist` path that resolves outside `data/playlists/` — including `..` traversal, an absolute path elsewhere on disk, or a UNC path — so this is the only location that works.

## 3. Create a local provider config

Copy the template and point it at your file:

```powershell
Copy-Item data/providers/provider.example.json data/providers/provider.local.json
```

Edit `data/providers/provider.local.json`:

- Set `provider` to whatever you want (this is just a label — see the warning below).
- Replace the example `sources` array with one entry per playlist you're testing. At minimum, each needs `name`, `url` (still required by the schema and validated by `Read-ChannelForgeProvider` — use a real or placeholder URL consistent with your real setup, it isn't fetched in this phase), `enabled: true`, and `local_playlist` pointing at the file from step 2:

```json
{
  "provider": "my-smoke-test",
  "sources": [
    {
      "name": "Sports",
      "group": "Sports",
      "url": "https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports",
      "enabled": true,
      "local_playlist": "data/playlists/sports.local.m3u"
    }
  ]
}
```

`data/providers/provider.local.json` is already covered by `.gitignore` — do not rename it.

`Build-Lineup.ps1` automatically discovers and uses `data/providers/provider.local.json` (or any single `data/providers/*.local.json` file) in place of the tracked `mybunny.json` — you never need to edit `mybunny.json` or any other tracked file. Do not place more than one `*.local.json` file under `data/providers/`: the build fails loudly rather than guessing which one to use. (Advanced/CI users can also pass `-ProviderPath` to `scripts/Build-Lineup.ps1` to point at a specific file explicitly; see [DEVELOPER_GUIDE.md](../developer/DEVELOPER_GUIDE.md#provider-config-resolution-issue-20).)

> **Warning:** the `provider` label and each source's `name` are display fields that appear as-is in `output/reports/build-summary.json` and `lineup-plan.md`. Only `url` is stripped from those reports. Use a plain label like `my-smoke-test`, never a token, account ID, or other secret-shaped value, in `provider` or `name`.

## 4. Set up numbering and aliases (optional but recommended)

For your channels to get a `tvg-chno`, their M3U `group-title` must exactly match (case-insensitive) a category in `data/lineup/numbering_blocks.json`. This is intentionally a simple exact-string match for Phase 1, not smart category inference — see [DEVELOPER_GUIDE.md](../developer/DEVELOPER_GUIDE.md#lineup-build-pipeline-phase-1-issue-7). A channel with no matching category is still included in `merged.m3u`, just without a number.

Alias resolution (`data/rules/aliases.json`) is optional too — channels with no alias entry pass through under their normalized name unchanged.

## 5. Run the build

From the repository root:

```powershell
pwsh -File scripts/Build-Lineup.ps1
```

## 6. Find the output

```text
output/merged.m3u
```

`output/` is gitignored and disposable (see ADR 0001) — it's fine to delete and regenerate at any time. Check `output/reports/build-summary.json` for `M3UGenerated: true`, a `ChannelCount`, and a `M3USha256` you can use to confirm the file wasn't altered. Check `output/reports/lineup-plan.md` for a human-readable summary — neither report contains any URL, even though `merged.m3u` itself does.

## 7. Point Plex at it

In Plex: **Settings → Live TV & DVR → Set Up Plex Tuner** (or add another tuner if you already have one), choose "M3U Playlist" / custom tuner, and point it at the absolute path to your `output/merged.m3u` file (or serve it over HTTP from your own machine if Plex requires a URL rather than a local path — that's a Plex/network detail, not a ChannelForge one).

## What Plex can test now

- Channel list import from `merged.m3u`.
- Playback of each channel's real stream URL.
- Channel numbers, if `tvg-chno` was assigned (see step 4).
- Channel logos, if the source M3U had `tvg-logo`.
- Deterministic rebuilds: re-run step 5 and confirm `M3USha256` in the report doesn't change unless your input files did.

## What will not work yet

- **No program guide / EPG data.** XMLTV generation is deferred (see issue #7) — there is no programme/guide data source anywhere in ChannelForge yet, and generating fake guide data is explicitly against this project's evidence-over-assumptions principle (ADR 0005). Plex will show channels with no schedule information.
- **No live provider fetch.** Only the local file you placed in step 2 is read. If your provider's playlist changes, re-download it and re-run the build.
- **No automatic Plex refresh.** Re-running `Build-Lineup.ps1` regenerates `output/merged.m3u`; refreshing Plex's channel list afterward is a manual step in Plex's tuner settings.

## If something goes wrong

- `Refusing to read from outside the approved location` — your `local_playlist` value doesn't resolve under `data/playlists/`. Fix the path; don't work around the check.
- `Provider source '...' has a malformed or unsupported URL` — every source's `url` field still goes through the same validation as the live-fetch path will eventually use, even though nothing fetches it yet. Use a well-formed `https://` URL.
- No channels in `merged.m3u`, or fewer than expected — check that the source is `enabled: true` and `local_playlist` is set; a source missing either is skipped, not an error, and won't show up in the channel count.
