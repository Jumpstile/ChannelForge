# Security

ChannelForge treats provider URLs, account IDs, API tokens, generated playlists, XMLTV data, logs, backups, and local deployment files as sensitive.

## Provider Secrets

Real provider URLs must never be committed. Provider subscription URLs often contain account IDs, usernames, passwords, or API tokens in the path or query string. Even if a URL looks harmless, treat it as a secret unless it is an obvious placeholder such as `https://example.invalid/...`.

Tracked provider and EPG files must use placeholder values only.

Historical note: an earlier tracked provider token existed in repository history, including commit `91a3913`. That token was revoked/rotated on 2026-06-28. Current tracked provider and EPG files use placeholder/example values only; do not treat the historical value as active.

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

## Remote M3U Disposable Cache

An enabled provider source without `local_playlist` may be acquired through the bounded HTTPS/443 transport. The disposable cache under `output/cache/remote-m3u/` stores decompressed M3U payload bytes, so it may contain playable stream URLs or provider-issued tokenized URLs and must be treated as sensitive local data. It is ignored generated output, not a source snapshot or durable provider store; deleting it is a safe recovery operation.

Remote M3U cache metadata is an ignored, disposable, cache-private operational record. It may contain raw ETag and Last-Modified validators required for conditional requests; those values must never appear outside that cache-private metadata. In particular, they must not appear in build reports or evidence, Programme/Channel objects, generated M3U/XMLTV artifacts, logs or diagnostics, cache directory/file names, user-visible source identity, or Git-tracked data/configuration. The metadata itself excludes provider URLs, query strings, stream URLs, response bodies, credentials, selected addresses, and absolute paths. Build evidence contains only the opaque cache key and bounded operational fields such as outcome, status, normalized content type, encoding list, byte counts, parsed channel count, and validator-presence booleans. This slice performs no authentication, credential handling, proxying, redirect following, or stale/offline publication.

## Native Guide Inference and Review Reports

`Invoke-ChannelForgeGuidePatternInference` and `Get-ChannelForgeGuidePatternReview` treat provider display text and Stage A evidence as untrusted input. Their candidate, preview, review items, provenance, JSON, and Markdown retain only sanitized event text, logical source identifiers, and fingerprints of sanitized examples where a safe provenance label is needed. URL/stream URL, credential/token, private-path, parser-error, candidate-hash, generation-ID, raw examples, and implementation metadata are excluded from rendered values. The fixed `RedactedFields` declaration names omitted categories only; it does not carry source values. The review command is read-only; use ignored local files for real guides and playlists, and never paste their raw contents into a fixture, report, or issue.

The beginner workflow's `-EventPatternPreview` uses the same boundary. It may read provider-supplied display names from operator input, but its JSON, Markdown, and text outputs under `output/reports/guided-event-pattern-preview.*` are deterministic and redacted: raw examples, provider and stream URLs, query strings, credentials, tokens, account IDs, private paths, parser errors, hashes, and generation IDs must not appear. Treat the generated reports as review artifacts rather than a place to store source evidence. The preview is report-only, cannot be combined with `-Accept`, and does not publish XMLTV or mutate provider, downstream, or accepted state.

Stage E acceptance plans use the same redaction boundary. Their JSON,
Markdown, and plain-text output contains only safe pattern descriptions,
matched-example counts, sanitized representative values, logical provenance,
freshness, drift, and blocked reasons. Volatile enrichment is represented by
safe fact type/subject/source metadata, timestamps, TTL, context, decision, and
reason codes; raw volatile values are never retained or rendered. Raw examples,
provider or stream URLs, credentials, tokens, account IDs, private paths,
parser errors, candidate hashes, and generation IDs must not appear.
When Stage B input is supplied directly, the proposed future rule identity is
an opaque deterministic `pattern-` identifier; Stage C/D-only input reports that
identity as unavailable rather than exposing candidate hashes. Markdown and
plain text are distinct renderers. The plan is review evidence only:
`PlanOnly`, `CandidateOnly`, `CanPublish = false`, `CanAcceptNow = false`,
`Adoption = NotApplied`, and all provider, downstream, guide-publication,
filesystem, and accepted-state mutation flags remain disabled.

## Starting from the Example Templates

Tracked configuration files (`data/providers/mybunny.json`, `data/epg/epg_sources.json`, `data/providers/m3u_sources.csv`, `data/epg/epg_sources.csv`) already use `https://example.invalid/...` placeholders and double as Pester fixtures. Do not put real provider data in them.

To set up real local provider data:

1. Copy `data/providers/provider.example.json` to `data/providers/provider.local.json` (or `data/epg/epg_sources.example.json` to `data/epg/epg_sources.local.json`).
2. Replace the placeholder `url` and `provider`/`name` values with your real provider data in the copy only.
3. Never rename the copy to drop the `.local.` segment, and never stage it (`git add`) — the `.local.json`/`.local.csv` glob patterns in `.gitignore` exist so this is hard to do by accident, not as the only safeguard.

`scripts/Build-Lineup.ps1` automatically discovers `data/providers/provider.local.json` (or any single `data/providers/*.local.json` file) and uses it in place of the tracked `mybunny.json` — no tracked file ever needs editing to run a real build. Do not place more than one `*.local.json` file in `data/providers/`: the build fails loudly rather than guessing which one to use. For advanced or CI use, an explicit `-ProviderPath` parameter overrides discovery; it is confined to `data/providers/` the same way (absolute paths, UNC paths, `..` traversal, directories, and non-`.json` files are all rejected). See [DEVELOPER_GUIDE.md](../developer/DEVELOPER_GUIDE.md#provider-config-resolution-issue-20) for the full precedence order.

The `provider` label and each source's `name` are display fields, not validated as opaque, and do appear in build reports (`output/reports/build-summary.json` and `lineup-plan.md`). Only the `url` field is stripped from reports. Do not put a token, account ID, or other secret-shaped value in a `provider` or source `name` field.

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

## Historical Token Exposure (Transparency Note)

The original scaffold commit (`91a3913`) tracked a real provider subscription token in `data/providers/mybunny.json` and related files, instead of a placeholder. That token was rotated/revoked with the provider on 2026-06-28. Current tracked provider and EPG files contain only `https://example.invalid/...` placeholders.

The old value still exists in Git history but is no longer a live credential. Per the Product Owner decision recorded in `LESSONS_LEARNED.md` (Issue #19), Git history has not been rewritten to remove it. Do not treat the historical value as an active credential, and do not attempt to use it.
