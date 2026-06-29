# Security

ChannelForge treats provider URLs, account IDs, API tokens, generated playlists, XMLTV data, logs, backups, and local deployment files as sensitive.

## Provider Secrets

Real provider URLs must never be committed. Provider subscription URLs often contain account IDs, usernames, passwords, or API tokens in the path or query string. Even if a URL looks harmless, treat it as a secret unless it is an obvious placeholder such as `https://example.invalid/...`.

Tracked provider and EPG files must use placeholder values only.

## Local Provider Files

Store real local provider configuration only in ignored local files:

- `data/providers/*.local.json`
- `data/providers/*.local.csv`
- `data/epg/*.local.json`
- `data/epg/*.local.csv`
- `data/playlists/*.local.m3u`
- `config/*.local.json`
- `config/*.local.csv`

A real local M3U playlist (referenced from a `local_playlist` field, see issue #7 Phase 1) can contain real stream URLs, which are exactly as sensitive as a provider source URL. See `data/playlists/README.md` and [the First Plex Smoke Test](../user/PLEX_SMOKE_TEST.md).

These files are for the local machine only. Do not copy real values into examples, tests, docs, build reports, or issue comments.

## Starting from the Example Templates

Tracked configuration files (`data/providers/mybunny.json`, `data/epg/epg_sources.json`, `data/providers/m3u_sources.csv`, `data/epg/epg_sources.csv`) already use `https://example.invalid/...` placeholders and double as Pester fixtures. Do not put real provider data in them.

To set up real local provider data:

1. Copy `data/providers/provider.example.json` to `data/providers/provider.local.json` (or `data/epg/epg_sources.example.json` to `data/epg/epg_sources.local.json`).
2. Replace the placeholder `url` and `provider`/`name` values with your real provider data in the copy only.
3. Never rename the copy to drop the `.local.` segment, and never stage it (`git add`) — the `.local.json`/`.local.csv` glob patterns in `.gitignore` exist so this is hard to do by accident, not as the only safeguard.

## Safe Examples

Examples should use reserved placeholder domains and obvious fake tokens:

- `https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports`
- `https://example.invalid/epg/ACCOUNT_ID/API_TOKEN/Sports.xml`

## Review Expectations

Before committing configuration changes:

- Check that no real provider host, account ID, token, username, password, or subscription URL is present.
- Check tests for hard-coded private URLs.
- Check generated reports and logs for leaked values.
- Prefer fixtures and placeholders over production data.

## Automated Secret Scanning

GitHub Actions runs Gitleaks before the Pester test suite on every push and pull request to `main`.

The scan checks the repository contents and Git history available to the workflow for common secrets, including API keys, access tokens, private keys, passwords, and credential-like URLs. It is a read-only gate: it reports findings and fails CI, but it does not modify repository files.

If Gitleaks reports a finding:

1. Treat the value as exposed.
2. Remove the secret from tracked files and replace it with a placeholder.
3. Move the real value into an ignored local file such as `data/providers/*.local.json`, `data/providers/*.local.csv`, `data/epg/*.local.json`, `data/epg/*.local.csv`, `config/*.local.json`, or `config/*.local.csv`.
4. Rotate the exposed credential with the provider or service.
5. Re-run the unit tests and open a clean pull request.

Do not suppress a finding unless the value is proven to be a harmless placeholder or test fixture.
