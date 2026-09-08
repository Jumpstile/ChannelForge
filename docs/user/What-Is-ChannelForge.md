# What Is ChannelForge?

## What is ChannelForge?

ChannelForge is a PowerShell tool that turns provider playlists, guide data, and local rules into a clean, deterministic television channel lineup — originally built for IPTVBoss, Dispatcharr, and Plex users who were tired of messy, drifting, untrustworthy channel data.

It doesn't blindly trust playlist names or provider metadata. It validates input, explains what it did, and never silently overwrites your data.

## Is it ready for me?

**Honestly: only if you're comfortable with PowerShell and an early, unfinished tool.**

ChannelForge is **Early Alpha**. There is no installer or complete GUI workflow yet. The repository includes a Tauri/React desktop shell with a safe native picker bridge that performs pre-parse availability checks and bounded structural checks for selected M3U playlists and local XMLTV guides. Playlist checks report only safe status, reason codes, and complete-entry counts; guide checks report only safe status, reason codes, channel counts, and programme counts. The GUI never opens or displays stream URLs, programme titles, or guide channel IDs. Guide checks support plain `.xml`/`.xmltv`, `.gz`, and single-guide `.zip` files with bounded local decompression only; guide matching, lineup creation, persistence, and automatic updates remain outside this GUI slice. If that doesn't sound like your kind of weekend, it's not ready for you yet. If it does, [Build Your First Lineup](Build-Your-First-Lineup.md) will get you to a working result in about ten minutes.

## What does it do today?

- Parses real M3U provider playlists.
- Reads provider and EPG source configuration, importing enabled local or bounded remote XMLTV sources and configured provider M3U sources.
- Resolves channel name aliases and assigns channel numbers deterministically (same input always produces the same output).
- Merges multiple local or configured remote playlists into one clean, deduplicated `output/merged.m3u` file.
- Imports configured local XMLTV `.xml`, `.gz`, and single-entry `.zip` files or supported remote XMLTV streams and writes deterministic `output/merged.xml` after validation.
- Produces a human-readable build report and a machine-readable summary (with a checksum) for every build, so you can verify nothing silently changed.

## What doesn't it do yet?

- **No complete graphical interface workflow.** Guided Setup can select local inputs and structurally check M3U playlists and local XMLTV guides in plain, gzip, or single-guide ZIP form, but it does not match guide content to playlists, create lineups, persist selections, export, or refresh targets.
- **No broad remote integration.** Supported remote provider M3U/XMLTV acquisition is limited to bounded HTTPS on port 443; there is no authentication, credentials, redirect, proxy, retry, remote ZIP, stale/offline success, or live-network CI.
- **No automatic target-specific guide assignment.** ChannelForge can generate validated deterministic M3U/XMLTV outputs and report exact identity bindings, but downstream guide configuration and automatic Plex refresh remain separate.
- **No automatic Plex refresh.** You re-run the build and refresh Plex's channel list yourself.

See [Current Limitations](CURRENT_LIMITATIONS.md) for the full, task-oriented breakdown of implemented vs. planned, or the [repository README](../../README.md#current-status) and [ROADMAP](../../ROADMAP.md) for the exact engineering-level state — this page only summarizes for a first-time reader.

## What remote acquisition does not do

ChannelForge has a hard rule: it does not fabricate data it cannot verify (see [ADR 0005, evidence over assumptions](../adr/0005-evidence-over-assumptions.md)). Remote sources are published only after the v5 pinned HTTPS transport, bounds, content policy, parser, and deterministic merge/export checks succeed. A stale or corrupt disposable cache is repaired or reported as failure; it is never silently published as current data.

## Where to go next

- Ready to try it? → [Build Your First Lineup](Build-Your-First-Lineup.md)
- Want the engineering detail behind any of this (architecture, ADRs, test suite)? Start at the [repository README](../../README.md).
