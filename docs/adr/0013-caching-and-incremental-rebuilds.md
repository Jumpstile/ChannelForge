# ADR 0013: Caching and incremental rebuild strategy (implementation-scope extension of ADR 0009)

## Status

Proposed

## Context

[ADR 0009](0009-durable-state-persistence-and-retention.md) (Accepted) already decides that ChannelForge separates authorities for declarative configuration, operational run state, identity/mapping knowledge, evidence/provenance, **source snapshots and caches**, last-known-good state, generated artifacts, review/approval records, audit history, and provider-owned state. It also states that "repeated full rescans can be replaced by durable, indexed state where appropriate."

**This ADR does not re-decide any of that.** ADR 0009 owns the authority model. This ADR is an implementation-scope extension: it works out, specifically for provider/EPG fetch (Milestone 4) and in light of [ADR 0012](0012-performance-and-scaling-targets.md)'s build-time targets, what "source snapshots and caches" concretely means for ChannelForge's fetch pipeline — key format, change-detection method, expiry defaults, and storage location — without introducing a new authority category or altering ADR 0009's boundaries.

ChannelForge's current pipeline (`Merge-ChannelForgeLineup`) fully re-parses and re-processes every configured local source on every run; there is no cache anywhere in `src/` today (confirmed by search). That remains correct for the Milestone 0-3 local-file scope. Milestone 4 adds HTTP fetch, at which point "redownload and reparse everything, every time" starts to threaten ADR 0012's build-time budget as source counts or EPG windows grow — which is the specific problem this ADR addresses.

ADR 0005 (evidence over assumptions) and ADR 0001 (source of truth) both bear on this: a cache is, by definition, data that might be stale relative to the true source. A caching design must make staleness visible rather than silently trusting old data as if it were fresh evidence.

## Decision

### Where this fits among ADR 0009's authorities

To avoid conflating categories ADR 0009 already keeps separate, this ADR distinguishes five kinds of state relevant to the fetch/build pipeline:

| Category | Example in ChannelForge | Authority | Cacheable? |
|---|---|---|---|
| **a. Declarative source truth** | `data/provider.json`, `data/epg_sources.json`, `numbering_blocks.json`, local playlists under `data/playlists/` | The working tree (ADR 0001) | No — always read live; already local and cheap |
| **b. Durable incremental/source-snapshot state** | Longer-lived indexed state ADR 0009 anticipates (e.g. identity/mapping knowledge built up across runs) | ADR 0009's "identity and mapping knowledge" / "source snapshots" authority | Out of scope for this ADR — ADR 0009 owns it |
| **c. Disposable fetch cache** | Parsed provider listing or EPG payload from a fetched URL, held only to avoid re-fetching/re-parsing an unchanged source | This ADR (implementation detail of ADR 0009's "source snapshots and caches" category) | Yes — this is what this ADR specifies |
| **d. Generated artifacts** | `output/merged.m3u`, build summaries | ADR 0009's "generated artifacts" authority | No — never treated as input |
| **e. Provider-owned state** | Entitlements, account state, anything the provider is system-of-record for | Stays with the provider (ADR 0009, CONSTITUTION.md) | Never ChannelForge-cached as if owned |

This ADR's scope is **(c) only**: the disposable fetch cache for provider/EPG source data. It does not define, redefine, or implement (b), and it does not authorize ChannelForge to treat any cache as (b)'s durable/indexed state.

### Fetch cache design

- **Provider source metadata** (parsed contents of a fetched M3U/JSON provider listing) may be cached between runs, keyed by source URL/path plus a content fingerprint.
- **EPG source data** (parsed XMLTV/JSON programme data) may be cached the same way, since EPG payloads are typically large relative to how often their content actually changes.
- Local playlists and local rule files (category a, above) are never cached — reading them is already cheap, and ADR 0001 makes the working tree always authoritative.

**When a full fetch is still required regardless of cache state:**
- First run for a given source (no cache entry exists).
- Any explicit `-Force`/full-rebuild flag from the user — the user must always be able to force ground truth.
- Any change to `data/provider.json`, `data/epg_sources.json`, or `numbering_blocks.json` that alters which sources are enabled or how they're configured.
- Any cache entry that fails validation (see invalidation, below).

**Change detection.** Reused (cached) data must be based on positive evidence that the underlying source has not changed, not merely on the presence of a cache file:
- Where supported, use HTTP conditional requests (`ETag`/`If-None-Match` or `Last-Modified`/`If-Modified-Since`) to ask the provider directly whether content changed.
- Where conditional requests are unsupported or unreliable, fall back to a content hash of the fetched payload: fetch is still required, but reparse/downstream processing (alias resolution, dedup, numbering) is skipped when the hash matches the cached hash.
- A cache entry always records: source identifier, fetch timestamp, ETag/Last-Modified if known, content hash, and the ChannelForge schema/parser version that produced it.

**Safe invalidation:**
- Every cache entry has a maximum age (proposed default: 24 hours for provider listings, 6 hours for EPG data, both configurable) after which it is treated as expired even without a change-detection check.
- A cache entry whose recorded parser/schema version doesn't match the current version is invalidated unconditionally.
- Falling back to a full fetch when a cache entry is missing, expired, mismatched, or corrupt is a safe automatic repair under ADR 0004 and requires no user approval.
- Cache storage lives under a clearly disposable location (e.g. `output/cache/`, not `data/`), consistent with category (c) above, so deleting it entirely is always a safe, supported recovery action.

### Guardrail: caching must not create a degraded success path

Cache use exists to avoid redundant work, not to change what "success" means. A stale or missing cache entry must never silently substitute for a required refresh. When a fetch is required and cannot be completed, ChannelForge must fail, warn, or route to review the same way it would with no cache involved at all — normal failure and diagnostic behavior applies; the cache is not a fallback data source that produces a quieter, degraded-but-successful build.

If ChannelForge later wants to support genuinely offline or degraded runs served from cache, that is a distinct feature requiring its own explicit design decision and user-visible reporting (e.g., a build clearly marked as served from stale/offline data). It is not authorized by this ADR and must not be implemented as an implicit side effect of the caching mechanism described here.

### Determinism (ADR 0010)

Per [ADR 0010](0010-deterministic-runs-and-reproducible-artifacts.md), cache hits, cache misses, and any caching-driven optimization or incremental execution path must produce identical meaningful artifacts, ordering, identifiers, warnings, and decisions to an equivalent full fetch/parse. Whether a given source was served from cache is operational metadata — it may appear in diagnostics and build summaries, but it must never change canonical output content or ordering. A build must be indistinguishable in its meaningful results whether every source was a cache hit or every source required a full fetch.

## Consequences

- Milestone 4 design must include a cache-entry schema (likely under `schemas/`, consistent with existing config validation) and a defined cache directory that write-guardrails (ADR 0004, `Assert-ChannelForgeWritePath`) cover the same way other generated output is covered.
- `BuildContext` will need fields or a companion structure to record which sources were served from cache vs. freshly fetched, so build summaries stay explainable.
- This ADR does not implement caching or expand ADR 0009's authority model; it constrains how Milestone 4 must implement the "source snapshots and caches" category ADR 0009 already anticipates, scoped narrowly to disposable fetch caching. If Milestone 4 ships and ADR 0012's targets are still met without caching, caching should not be added speculatively — this matches issue #60's "no speculative framework work should delay a functioning product."

## Verification

- Tests: cache hit/miss/expiry/version-mismatch behavior should each have a focused unit test once implemented, following the existing `tests/unit/*ConfigResolution*`-style pattern. A determinism test confirming identical output between a cache-hit run and a full-fetch run of the same inputs is required before this ADR's caching behavior ships.
- CI checks: none required beyond normal test coverage.
- Documentation: ARCHITECTURE.md's "Infrastructure layer (planned)" section should be updated when HTTP fetch and caching land.
- Runtime behavior: build summary output should report cache hit/miss counts per source, giving users direct evidence of whether caching is working rather than an implicit assumption.

## Related Issues

- Roadmap Milestone 4 - Provider/EPG Engine
- [ADR 0001](0001-source-of-truth.md), [ADR 0004](0004-self-healing-with-guardrails.md), [ADR 0005](0005-evidence-over-assumptions.md)
- [ADR 0009](0009-durable-state-persistence-and-retention.md) — parent decision this ADR extends
- [ADR 0010](0010-deterministic-runs-and-reproducible-artifacts.md) — determinism contract this ADR must satisfy
- [ADR 0012](0012-performance-and-scaling-targets.md) — build-time targets this ADR helps meet
- #60 (Product priority: Deliver a robust, useful IPTV enthusiast MVP without overengineering)
