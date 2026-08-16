# ADR 0012: Performance and scaling targets

## Status

Proposed

## Context

ChannelForge merges provider playlists, EPG sources, and local rules into a lineup. Milestone 0-3 work established architecture, alias resolution, and confidence scoring; Milestone 4 (Provider/EPG Engine) will add live HTTP ingestion of provider and EPG sources, and Milestone 5 will add production build outputs. Both widen the amount of data a build touches on every run.

No repository document currently states how large a lineup ChannelForge is expected to handle, how long a build should take, or what resource use is acceptable. `Merge-ChannelForgeLineup` today re-parses and re-processes every configured local playlist in full on each run (see [ARCHITECTURE.md](../architecture/ARCHITECTURE.md#data-flow-current)). That is reasonable at today's scale but has no documented ceiling, and Milestone 4/5 work should not be designed against a guess.

CONSTITUTION.md treats user experience, self-healing, and deterministic behavior as engineering responsibilities, not decoration. A build that is slow, hangs, or consumes unbounded memory is a user-experience failure in the same way a wrong channel number is — it just fails silently until someone waits long enough to notice. Performance is therefore a product requirement: ChannelForge is meant to run unattended and repeatedly (Roadmap Milestone 5, "guarded production outputs"), and an enthusiast rerunning a slow build loses trust in it the same way they would lose trust in a nondeterministic one.

[ADR 0010](0010-deterministic-runs-and-reproducible-artifacts.md) establishes the determinism contract (module load order, tie-breaking, stable identifiers, canonical serialization) that identical inputs must satisfy. This ADR does not restate that contract; it adds the constraint that performance work must not be the thing that breaks it.

## Decision

ChannelForge adopts the following practical, personal/enthusiast-scale targets. These are **future engineering targets to design and test against, not current measured evidence** — no benchmark at this scale has been run yet (per ADR 0005, this ADR states that plainly rather than presenting an estimate as a result). They are not hard contractual limits, and should be replaced with measured numbers, and revised if evidence (real provider data, user reports, actual benchmarks) shows they are wrong.

**Measurement boundary**
Any future benchmark against these targets must scope what it measures explicitly, because "channel count" and "source count" alone do not bound the work:

- **In scope:** local parse, normalize, alias-resolve, dedupe, number, and export — the work `Merge-ChannelForgeLineup` and `Export-ChannelForgeM3UPlaylist` already perform today (see [ARCHITECTURE.md](../architecture/ARCHITECTURE.md#data-flow-current)).
- **Out of scope but must be reported, not hidden:** provider/EPG network fetch latency (Milestone 4). This is provider-dependent and cannot be bounded by ChannelForge's own design; it must appear in build output as its own reported figure rather than being folded into, or excluded silently from, the build-time budget below.
- **Must be measured separately, not assumed from channel/source counts:** EPG programme volume (programme-count and date-range can vary independently of channel count) and raw input byte size (a provider file can be large without having many channels, e.g. dense metadata or malformed/bloated markup). A benchmark that reports only "N channels, M seconds" without also reporting programme count and input bytes has not established evidence for this ADR's targets.

**Target lineup size**

- Primary target: up to 5,000 channels merged from up to 20 provider/local-playlist sources.
- EPG: up to 5,000 channels x 14 days of programme data per source, tracked as its own figure per the measurement boundary above.
- These figures reflect a well-provisioned IPTV enthusiast setup (multiple providers, regional/local channels, several EPG sources), not a commercial aggregator scale.

**Acceptable build time**

- Target (not yet measured): a full local build (in-scope work only, per the measurement boundary above) at the target lineup size should complete in under 60 seconds on typical enthusiast hardware (consumer NAS or desktop-class CPU, with either spinning-disk or SSD storage).
- A build several times smaller (a few hundred channels, one or two sources) should complete in a few seconds, since that is the common case exercised on most runs.
- Once Milestone 4 adds HTTP fetch, network latency to provider/EPG endpoints is excluded from this budget; it is a separate, provider-dependent cost that must be reported to the user (progress or timing output), not hidden inside a silent hang.

**Memory and CPU**

- Target (not yet measured): a full build at target scale should stay within roughly 500 MB of working memory and should not require sustained high CPU use beyond the build's own duration (no background polling, no idle spin).
- ChannelForge is not expected to run well on severely constrained hardware; "practical" means typical home-server or desktop resources, not embedded devices.

**Deterministic output under performance work**

- Any performance optimization (parallelism, streaming parsers, caching per ADR 0013) must preserve ADR-level determinism: the same inputs produce the same meaningful outputs, including stable ordering of `Export-ChannelForgeM3UPlaylist` output. Speed must never be purchased by making output order or content depend on timing, thread scheduling, or partial/incomplete reads.
- If an optimization cannot preserve determinism, it is not acceptable as designed and must be redesigned or documented as an explicit, isolated exception per the Constitution's "deterministic behavior" principle.

**Why performance is a product requirement, not just an optimization**

- ChannelForge's stated audience is IPTV enthusiasts who will rerun builds routinely (Roadmap Milestone 5's "guarded production outputs," issue #60's "detect channel additions and removals automatically" and "rerun and update results without requiring full manual reconfiguration"). A slow or resource-heavy rebuild directly undermines that workflow and pushes users back toward manual, error-prone alternatives — the exact failure mode ChannelForge exists to prevent.
- Self-healing and automatic reconciliation (ADR 0004) only remain trustworthy if they are also fast enough to run unattended and often; a repair mechanism nobody dares to run because it takes too long is not a repair mechanism.

## Consequences

- Milestone 4 (Provider/EPG Engine) and Milestone 5 (Production Build) design work should be evaluated against these targets before implementation, not after.
- Performance regressions become reviewable: a change that measurably worsens build time or memory at target scale is a defect, not a style preference.
- These targets do not, by themselves, require caching or incremental rebuilds — see ADR 0013 for when that tradeoff is justified.
- Targets are practical estimates, not benchmarked guarantees. They should be replaced with measured numbers once representative provider/EPG fixtures exist at target scale (tracked as follow-up work, not blocking this ADR).

## Verification

- Tests: a future benchmark/regression test at approximate target scale (e.g., a large synthetic fixture) once Milestone 4 fixtures exist.
- CI checks: none yet; add a timing assertion only once real hardware baselines are established, to avoid flaky CI on shared runners.
- Documentation: this ADR, referenced from ARCHITECTURE.md and ROADMAP.md Milestone 4/5 sections when that work begins.
- Runtime behavior: `Build-Lineup.ps1` should report elapsed time as part of its build summary so drift from these targets is visible without a dedicated benchmark harness.

## Related Issues

- Roadmap Milestone 4 - Provider/EPG Engine
- Roadmap Milestone 5 - Production Build
- [ADR 0010](0010-deterministic-runs-and-reproducible-artifacts.md) — deterministic runs and reproducible artifacts
- [ADR 0013](0013-caching-and-incremental-rebuilds.md) — caching and incremental rebuild strategy
- #60 (Product priority: Deliver a robust, useful IPTV enthusiast MVP without overengineering)
