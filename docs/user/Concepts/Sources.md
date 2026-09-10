# Sources

This page answers: **what does ChannelForge mean by a "source"?**

A **source** is one entry in your provider configuration — typically one category of channels from your provider, like "Sports" or "Movies". Each source has:

- A `name` and `group` label (display only — see [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md#how-to-avoid-exposing-credentials) for why these aren't secret-safe).
- A `url` (the provider URL for this category — treated as a secret).
- An `enabled` flag.
- An optional `local_playlist` path, pointing at an `.m3u` file already saved to disk. When present, it is authoritative over the URL.

## Which sources participate in a build today

A source is included in `output/merged.m3u` when it is `enabled: true` and has either a safe local playlist path or a supported remote URL. A local playlist is authoritative when both are present. An enabled source with neither a usable local path nor a supported remote URL fails closed; it is never silently skipped. Remote acquisition is bounded HTTPS on port 443 and uses the same streaming parser as local input.

`output/reports/lineup-plan.md`'s "Provider M3U Sources" section lists every configured source and its enabled/playlist state, so you can always see why a source was or wasn't included.

## EPG sources are separate

Your provider's M3U sources (above) are a different list from EPG sources (`data/epg/epg_sources.json` or a local equivalent), which describe guide-data inputs rather than channel playlists. Enabled local XMLTV path entries and supported remote HTTPS XMLTV entries use the XMLTV pipeline; M3U and XMLTV remain separate source types. See [XMLTV](XMLTV.md) for the current boundary.

## Guide evidence and source relationships

ChannelForge keeps guide evidence read-only until the normal candidate → review → explicit acceptance → immutable generation path runs. Evidence can come from provider display text, provider M3U metadata, XMLTV, a documented AED-derived XMLTV/M3U export, a future schedule source, or existing accepted ChannelForge knowledge.

Every evidence record carries a confidence state and source relationship. **Confirmed** means the available evidence is coherent; **safe candidate** means it is useful but provisional; **needs review** means a person must decide; **unresolved** means required identity or timing evidence is missing; **contradiction** means sources disagree; **stale source** means freshness has expired; and **source unavailable** means the source could not provide usable evidence. A mirror is not independent confirmation.

These states are evidence about a guide, not permission to overwrite an accepted lineup. Stale or unavailable evidence preserves accepted state and last-known-good output.

## Where to go next

- Setting up your real sources? → [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md)
- Full schema for a source entry → [Configuration Reference](../Reference/Configuration-Reference.md)
