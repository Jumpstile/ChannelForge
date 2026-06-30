# Sources

This page answers: **what does ChannelForge mean by a "source"?**

A **source** is one entry in your provider configuration — typically one category of channels from your provider, like "Sports" or "Movies". Each source has:

- A `name` and `group` label (display only — see [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md#how-to-avoid-exposing-credentials) for why these aren't secret-safe).
- A `url` (the provider URL for this category — treated as a secret).
- An `enabled` flag.
- An optional `local_playlist` path, pointing at an `.m3u` file already saved to disk.

## Which sources participate in a build today

A source is included in `output/merged.m3u` only if it is **both** `enabled: true` **and** has a `local_playlist` set. A source missing either is silently skipped — not an error. This is intentional, not a bug: ChannelForge has no live HTTP fetch yet (see [Current Limitations](../CURRENT_LIMITATIONS.md)), so a source with no local file genuinely has nothing to read.

`output/reports/lineup-plan.md`'s "Provider M3U Sources" section lists every configured source and its enabled/playlist state, so you can always see why a source was or wasn't included.

## EPG sources are separate

Your provider's M3U sources (above) are a different list from EPG sources (`data/epg/epg_sources.json` or a local equivalent), which describe guide-data feeds rather than channel playlists. EPG sources are currently read and validated, but not fetched — see [XMLTV](XMLTV.md) for why.

## Where to go next

- Setting up your real sources? → [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md)
- Full schema for a source entry → [Configuration Reference](../Reference/Configuration-Reference.md)
