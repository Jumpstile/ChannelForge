# Local Playlists

This directory is the only approved location for `local_playlist` files referenced from `data/providers/*.json` (see issue #7 Phase 1 and `schemas/provider.schema.json`).

`Build-Lineup.ps1` validates every `local_playlist` path with `Assert-ChannelForgeReadPath`, confined to this directory. A path that resolves outside `data/playlists/` (via `..` traversal, an absolute path elsewhere on disk, a UNC path, or a drive root) is rejected with a clear error, not silently read.

## Real playlists are local-only

A real provider `.m3u` file can contain real stream URLs, which are treated as secrets the same way provider/EPG source URLs are (see [SECURITY.md](../../docs/reference/SECURITY.md)). Never commit one.

- Tracked/example files in this directory must use placeholder content only (e.g. `https://example.invalid/...` stream URLs).
- Real local playlists must use a `*.local.m3u` filename, which `.gitignore` excludes.

## Setup

See [First Plex Smoke Test](../../docs/user/PLEX_SMOKE_TEST.md) for the full walkthrough: copying a real `.m3u` file here, pointing a `local_playlist` field at it, and running `Build-Lineup.ps1`.
