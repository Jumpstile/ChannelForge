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
- `config/*.local.json`
- `config/*.local.csv`

These files are for the local machine only. Do not copy real values into examples, tests, docs, build reports, or issue comments.

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
