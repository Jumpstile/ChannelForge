# XMLTV

This page answers: **what is XMLTV, and how does ChannelForge produce it safely today?**

## What XMLTV is

XMLTV is the standard file format for TV program guide data — what gives Plex (or any tuner app) the "what's on now / what's on next" schedule information for each channel. It's a separate file from your channel list (`merged.m3u`); a channel list alone tells a player _what channels exist_, while XMLTV tells it _what's airing on each one_.

## How ChannelForge produces XMLTV today

ChannelForge has a hard rule: it does not fabricate data it cannot verify (see [ADR 0005, evidence over assumptions](../../adr/0005-evidence-over-assumptions.md)). Build-Lineup accepts enabled local XMLTV `path` entries and remote HTTPS XMLTV `url` entries from `epg_sources.json`, with the optional `format` defaulting to `xmltv`. Local plain `.xml`, gzip `.gz`, and single-entry `.zip` files, plus remote plain XML and supported HTTP content codings, are streamed through the existing importer, merged source-aware and deterministically, and written as `output/merged.xml` only after validation and conflict checks succeed.

Remote HTTPS XMLTV entries are acquired only through the pinned transport on port 443, with no redirects, proxies, credentials, or retries. The disposable XMLTV fetch cache may avoid a fresh network fetch only within its fixed six-hour policy or after successful validator/hash evidence; stale or corrupt entries fail closed or are repaired. Plain XML and HTTP identity/gzip/x-gzip content codings are supported; ZIP-over-HTTP and suffix-inferred `.gz` remain unsupported. A remote source is published only after bounded acquisition, decompression, XMLTV validation, deterministic merge, and export all succeed.

A successful local or remote XMLTV build reports `XMLTVStatus: GENERATED`, `XMLTVGenerated: true`, and the project-relative `XMLTVPath`. A failed import, invalid interval, merge conflict, `NeedsReview` result, or export failure reports `XMLTVStatus: FAILED`, leaves the public `output/merged.xml` path absent, and preserves any prior artifact only in the non-published rollback area.

## What this means in practice

- `output/merged.m3u` remains the channel-list output; `output/merged.xml` is the separate guide-data output.
- XMLTV bindings remain source-scoped; this slice does not perform fuzzy station matching or bind XMLTV to M3U `Channel.TvgId` values.
- Downstream Plex guide binding and automatic refresh remain separate work.

## Where to go next

- Full current-limitations breakdown → [Current Limitations](../CURRENT_LIMITATIONS.md)
- Using your channel list in Plex today → [Use ChannelForge with Plex](../Use-With-Plex.md)
