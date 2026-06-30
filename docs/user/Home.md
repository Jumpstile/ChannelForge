# ChannelForge User Documentation

**One source. Many outputs. Zero guesswork.**

ChannelForge turns provider playlists, guide data, and local rules into a deterministic television lineup. It is currently **Early Alpha — not production-ready**. This is the user-facing guide; for engineering details, architecture, and governance, the [repository README](../../README.md) is always the source of truth.

> This documentation lives in the repository (`docs/user/`) and is versioned and reviewed alongside the code, not published as a separate GitHub Wiki — GitHub Wiki is not available on the current plan. See [DOCUMENTATION.md](../../DOCUMENTATION.md) for why.

## What are you trying to do?

- **I want to understand what ChannelForge is.** → [What Is ChannelForge?](What-Is-ChannelForge.md)
- **I want to build my first lineup.** → [Build Your First Lineup](Build-Your-First-Lineup.md)
- **I want to configure my provider safely.** → [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md)
- **I want to use ChannelForge with Plex.** → *(dedicated guide coming soon — see [the Plex smoke test](PLEX_SMOKE_TEST.md) in the meantime)*
- **I want to troubleshoot a problem.** → [Troubleshooting](TROUBLESHOOTING.md)
- **I want to understand current limitations.** → [Current Limitations](CURRENT_LIMITATIONS.md)

This documentation set is being built incrementally, in reviewable commits. Pages not yet linked above will route directly here once written — see [Issue #12](https://github.com/Jumpstile/ChannelForge/issues/12) for progress.

## A note on safety

ChannelForge treats provider URLs, account IDs, and tokens as secrets. Nothing in this documentation will ever ask you to put real provider data into a tracked repository file. Real configuration always lives in an ignored, local-only file on your own machine — see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md) for how.
