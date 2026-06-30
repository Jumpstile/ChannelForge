# XMLTV

This page answers: **what is XMLTV, and why doesn't ChannelForge produce it yet?**

## What XMLTV is

XMLTV is the standard file format for TV program guide data — what gives Plex (or any tuner app) the "what's on now / what's on next" schedule information for each channel. It's a separate file from your channel list (`merged.m3u`); a channel list alone tells a player *what channels exist*, while XMLTV tells it *what's airing on each one*.

## Why ChannelForge doesn't generate it yet

ChannelForge has a hard rule: it does not fabricate data it can't verify (see [ADR 0005, evidence over assumptions](../../adr/0005-evidence-over-assumptions.md)). There is no program-guide data source wired up anywhere in ChannelForge today — EPG *source configuration* is read and validated, but the actual guide data behind those sources is never fetched. Generating an XMLTV file under those conditions would mean inventing schedule data, which ChannelForge refuses to do.

Every build is explicit about this rather than silent: `output/reports/build-summary.json` always reports `XMLTVGenerated: false`, with an `XMLTVDeferredReason` field explaining exactly why.

## What this means in practice

- `output/merged.m3u` is fully playable in Plex today — channels and streams work.
- Plex (or any tuner in front of it) will show no schedule data for those channels, because there's no guide file to bind.
- This is tracked as deferred, not abandoned — see [ROADMAP.md](../../../ROADMAP.md).

## Where to go next

- Full current-limitations breakdown → [Current Limitations](../CURRENT_LIMITATIONS.md)
- Using your channel list in Plex today → [Use ChannelForge with Plex](../Use-With-Plex.md)
