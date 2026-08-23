# Providers

This page answers: **what's the difference between "my provider" and a "provider config file"?**

Your **provider** is the IPTV service or playlist source you subscribe to — the actual company or service. **Provider configuration** is ChannelForge's record of that provider's sources: a JSON file listing each category (Sports, Movies, News, ...) as a [source](Sources.md), with a name, URL, and enabled state.

## Where provider configuration lives

- `data/providers/mybunny.json` — a tracked example/fixture. Never put real data here.
- `data/providers/provider.local.json` (or any single `data/providers/*.local.json`) — where your real provider configuration goes. Auto-discovered and used automatically.

See [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md) for the full setup walkthrough — this page only explains the concept, not the steps.

## What ChannelForge does and doesn't do with your provider today

- **Does:** read and validate your provider's configured sources, including a URL trust-boundary check (so a malformed URL fails the build early).
- **Does:** read a local playlist file you've already downloaded from your provider.
- **Does:** acquire an enabled source without `local_playlist` through the bounded HTTPS/443 remote M3U path, with the disposable 24-hour fetch cache and the same parser used for local playlists.
- **Does not:** authenticate to providers, follow redirects, use proxies, or publish stale/degraded cache data. Guide acquisition and binding are separate source paths — see [Current Limitations](../CURRENT_LIMITATIONS.md).

## Why provider labels aren't the final word on channel identity

A provider's name for a channel (e.g. how it labels ESPN in its playlist) is treated as one piece of _evidence_, not as ground truth — see [Channel IDs](Channel-IDs.md) for why that distinction matters.

## Where to go next

- Set up your real provider → [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md)
- Full provider config file schema → [Configuration Reference](../Reference/Configuration-Reference.md)
