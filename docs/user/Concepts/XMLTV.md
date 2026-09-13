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
- XMLTV bindings remain source-scoped. ChannelForge now reports exact, ordinal M3U `Channel.TvgId` to XMLTV channel-id matches separately from the canonical `merged.m3u` and `merged.xml` outputs. Missing IDs, missing XMLTV identities, duplicate/ambiguous IDs, and XMLTV-only channels remain explicit report records; no fuzzy station matching is performed.
- Downstream target-specific Plex guide assignment and automatic refresh remain separate work.

## Event guides are evidence-backed

XMLTV can describe an event programme, but XMLTV plumbing alone does not prove that a volatile sports or PPV event is correct. ChannelForge's guide-intelligence contract keeps the channel, event title, time, timezone, status, source freshness, confidence, and provenance together as read-only evidence.

Supported evidence types include provider display text, provider M3U metadata, XMLTV, documented AED-derived XMLTV/M3U exports, future schedule sources, and accepted ChannelForge knowledge. An AED-derived export is a bootstrap or migration input, not a second accepted authority. Conflicting times, missing identities, stale guides, and unavailable sources remain review or degraded conditions.

The readiness projection never publishes a guide. It reports `CandidateOnly` and requires explicit acceptance through the existing immutable generation boundary. It does not display stream URLs, credentials, private paths, parser errors, candidate hashes, or generation IDs.

Native event-pattern inference is the complementary read-only path for volatile channel names. It accepts representative provider names or Stage A evidence and returns structured channel/title/date/time/timezone/participant/league/sport candidates with confidence and safe provenance. It does not write `merged.xml`, publish a guide, mutate provider or downstream state, or replace accepted state. A documented AED-derived XMLTV/M3U export can be supplied as evidence while native inference is evaluated.
For a beginner-facing explanation of those inference results, run `Get-ChannelForgeGuidePatternReview` with `-OutputFormat Markdown` or `-OutputFormat Json`. The review surface is intentionally separate from XMLTV generation: it reads the Stage B candidate, returns deterministic redacted output, and never writes `merged.xml`, changes provider/downstream state, or changes accepted state. `CandidateOnly` and `CanPublish = false` remain true until a future explicit acceptance workflow exists.

The beginner workflow exposes this as a report-only preview with `scripts/Build-My-Lineup.ps1 -EventPatternPreview`. Supply representative IPTV event-channel names and, when needed, an explicit event type, timezone mapping, or reference instant. The workflow writes `guided-event-pattern-preview.json`, `.md`, and `.txt` under `output/reports/`; it does not write `output/merged.xml`, alter the M3U/XMLTV source pipeline, publish a guide, or change provider, downstream, or accepted state. A confirmed pattern is still candidate evidence and requires a future explicit acceptance workflow before it could drive guide generation.

## Where to go next

- Full current-limitations breakdown → [Current Limitations](../CURRENT_LIMITATIONS.md)
- Using your channel list in Plex today → [Use ChannelForge with Plex](../Use-With-Plex.md)
