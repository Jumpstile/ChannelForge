# What Is ChannelForge?

## What is ChannelForge?

ChannelForge is a PowerShell tool that turns provider playlists, guide data, and local rules into a clean, deterministic television channel lineup — originally built for IPTVBoss, Dispatcharr, and Plex users who were tired of messy, drifting, untrustworthy channel data.

It doesn't blindly trust playlist names or provider metadata. It validates input, explains what it did, and never silently overwrites your data.

## Is it ready for me?

**Honestly: only if you're comfortable with PowerShell and an early, unfinished tool.**

ChannelForge is **Early Alpha**. There is no installer and no GUI yet — everything today runs from PowerShell scripts against a cloned copy of the repository. If that doesn't sound like your kind of weekend, it's not ready for you yet. If it does, [Build Your First Lineup](Build-Your-First-Lineup.md) will get you to a working result in about ten minutes.

## What does it do today?

- Parses real M3U provider playlists.
- Reads provider and EPG source configuration, importing enabled local XMLTV files while validating remote URL entries without fetching them.
- Resolves channel name aliases and assigns channel numbers deterministically (same input always produces the same output).
- Merges multiple local playlists into one clean, deduplicated `output/merged.m3u` file.
- Imports configured local XMLTV `.xml`, `.gz`, and single-entry `.zip` files and writes deterministic `output/merged.xml` after validation.
- Produces a human-readable build report and a machine-readable summary (with a checksum) for every build, so you can verify nothing silently changed.

## What doesn't it do yet?

- **No graphical interface.** Command line / PowerShell only.
- **No remote provider or EPG fetching over HTTP.** You supply local playlist and XMLTV files; remote URL entries are validated but not dereferenced in this slice.
- **No remote XMLTV acquisition or automatic guide binding.** Local XMLTV configuration can generate a validated guide file; remote acquisition and downstream binding remain deferred.
- **No automatic Plex refresh.** You re-run the build and refresh Plex's channel list yourself.

See [Current Limitations](CURRENT_LIMITATIONS.md) for the full, task-oriented breakdown of implemented vs. planned, or the [repository README](../../README.md#current-status) and [ROADMAP](../../ROADMAP.md) for the exact engineering-level state — this page only summarizes for a first-time reader.

## Why is remote XMLTV not yet available?

ChannelForge has a hard rule: it does not fabricate data it cannot verify (see [ADR 0005, evidence over assumptions](../adr/0005-evidence-over-assumptions.md)). Enabled local XMLTV paths are now imported, merged, and exported deterministically. Remote URL acquisition remains deferred pending the transport decision; those entries are validated without network access and reported as `DEFERRED_REMOTE_ONLY` when no local source is available.

## Where to go next

- Ready to try it? → [Build Your First Lineup](Build-Your-First-Lineup.md)
- Want the engineering detail behind any of this (architecture, ADRs, test suite)? Start at the [repository README](../../README.md).
