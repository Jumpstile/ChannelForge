# Use ChannelForge with Plex

This page answers: **I already have an `output/merged.m3u` — how do I get it into Plex?**

If you haven't built a lineup yet, start at [Build Your First Lineup](Build-Your-First-Lineup.md) first.

## What you can test today

- Importing your channel list from `merged.m3u` into Plex.
- Playing each channel's real stream.
- Channel numbers, if your sources matched a `numbering_blocks.json` category (see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md) and the [Deterministic Lineup Generation](Concepts/Deterministic-Lineup-Generation.md) concept page).
- Channel logos, if your source M3U included them.
- That rebuilding is deterministic: re-run the build with the same inputs and the report's checksum won't change.

## What won't work yet

- **No automatic guide binding.** Plex will not consume ChannelForge's separate XMLTV output automatically; configure the guide path explicitly when using a local or remote XMLTV source. ChannelForge's remote XMLTV acquisition remains bounded HTTPS/443, but downstream Plex binding is separate.
- **No automatic refresh.** Re-running the build regenerates `output/merged.m3u`; pointing Plex at it (or refreshing if already pointed there) is a manual step in Plex.

## Point Plex at your lineup

In Plex: **Settings → Live TV & DVR → Set Up Plex Tuner** (or add another tuner if you already have one), choose "M3U Playlist" / a custom tuner, and point it at the absolute path to your `output/merged.m3u` (or serve it over HTTP from your own machine if Plex requires a URL rather than a local path — that's a Plex/network detail, not a ChannelForge one).

## The full walkthrough

For the complete step-by-step — including how to set up a real provider playlist and what to do when something doesn't show up — see [the Plex smoke test](PLEX_SMOKE_TEST.md), which exercises this same flow end to end and includes a troubleshooting section specific to it. This page is a quick-reference summary; that one is the detailed canonical walkthrough.

## Where to go next

- Something not working? → [Troubleshooting](TROUBLESHOOTING.md)
- Want to understand the local XMLTV boundary? → [Current Limitations](CURRENT_LIMITATIONS.md)
