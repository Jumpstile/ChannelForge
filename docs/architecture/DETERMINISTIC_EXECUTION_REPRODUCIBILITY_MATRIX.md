# ChannelForge Deterministic Execution and Reproducibility Matrix

## Purpose and relationship to ADR 0010

This document is the repository artifact for issue #77 and ADR 0010.

It defines the contracts required for deterministic execution, reproducible run records, and reproducible generated artifacts. It does not implement a feature or select a runtime design.

This document defines determinism and reproducibility contracts. It does not select a serialization format, artifact format, database, hash algorithm, build engine, scheduler, or publication mechanism.

ADR 0010 requires stable identifiers to be derived deterministically from canonical input content or keys, not from generation order, process timing, or incidental enumeration sequence, so that identical inputs produce identical identifiers across separate runs, not merely within one run. The rules below apply that decision to runs, inputs, records, mappings, and generated artifacts.

Feature implementation remains blocked. Updater work remains unauthorized.

## Deterministic run identity

- A run identity is derived from canonical run inputs, approved configuration and policy, relevant contract/version identifiers, and the defined input set.
- Run identity must not depend on generation order, process timing, incidental enumeration sequence, uncontrolled timestamps, random values, machine-local paths, or unrecorded environment state.
- The same canonical inputs, configuration, policy, and relevant contract versions must produce the same run identity across separate runs.
- A run record must retain the canonical inputs and references needed to explain and independently verify the identity.

## Deterministic input-set definition

- The input set is the explicit, canonical membership of the sources, records, configuration, policy, and other approved inputs used by a run.
- Membership decisions must be recorded with source references, provenance, inclusion or exclusion outcomes, and relevant evidence.
- Duplicate, missing, unavailable, rejected, and superseded inputs must have explicit deterministic handling.
- Provider or filesystem enumeration order must not implicitly define input membership.
- A cache cannot add, remove, replace, or reorder canonical inputs.

## Canonical ordering rules

- Inputs, normalized records, mappings, evidence references, and output components must use documented stable ordering rules.
- Ordering must be based on canonical keys or canonical content, with deterministic tie-breaking where required.
- Filesystem order, provider response order, dictionary/hash-map enumeration, network arrival order, process scheduling, and generation order are not canonical ordering sources.
- Any ordering-relevant version or rule must be recorded in the reproducible run/build record.

## Stable identifier rules

- Stable identifiers must be derived from canonical input content or keys.
- Identical canonical inputs must produce identical identifiers across separate runs.
- Identifiers must not be derived from generation order, process timing, incidental enumeration sequence, mutable cache state, uncontrolled timestamps, or random values.
- Identifier derivation must be documented well enough for independent verification and must preserve the authority of the owning abstraction.

## Artifact integrity and immutability

- Generated artifacts must use canonical content and serialization rules before integrity evidence is computed.
- Artifact integrity evidence must be recorded and independently verifiable under the selected implementation.
- Approved generated artifacts are immutable records. Corrections require governed replacement artifacts rather than in-place mutation.
- An artifact is not canonical state merely because it was generated or published.
- A failed, incomplete, unverifiable, or nondeterministic artifact must not replace an approved artifact.

## Reproducible run/build records

A reproducible run/build record must retain, as applicable:

- Deterministic run identity.
- Canonical input-set membership and source/provenance references.
- Approved configuration and policy references.
- Canonical ordering and identifier-rule versions.
- Relevant contract and environment/version inputs.
- Timestamp, randomness, and environment handling information.
- Cache use as non-canonical performance state.
- Generated artifact identifiers and integrity evidence.
- Verification results, failures, interruptions, and rejection reasons.
- Last-known-good comparison and replacement decisions.

The record must support comparison of independent runs without treating process-local incidental state as canonical.

## Timestamp, randomness, and environment handling

- Timestamps may describe execution history, observation time, or audit context, but uncontrolled timestamps must not alter canonical identity or canonical artifact content.
- Randomness must not influence canonical identifiers, ordering, membership, or artifact content unless it is explicitly governed, recorded, and part of the canonical input contract.
- Relevant runtime, dependency, configuration, and environment versions must be recorded when they can affect reproducibility.
- Machine-local paths, locale, timezone, process scheduling, network arrival timing, and ambient environment variables must not silently change canonical results.
- Differences that prevent reproducibility must be surfaced as verification failures or explicit non-canonical metadata, not silently repaired.

## Cache exclusion rules

- Caches are disposable performance state and are never canonical state.
- Caches must not define identity, ordering, canonical content, input membership, review decisions, or last-known-good results.
- Cache hits and misses must not change a deterministic result.
- A cache may be discarded and rebuilt without changing canonical output.
- Cache invalidation, staleness, corruption, and rebuild behavior must be covered by verification gates.

## Partial-failure and mutation rule

A partially completed, failed, interrupted, unverifiable, or nondeterministic run must not update approved artifacts, last-known-good state, identity mappings, review decisions, or publication records.

Preflight and certification paths are observation and verification paths only. They must fail closed or report an actionable result; they must not trigger repair, mutation, publication, replacement, or silent state correction.

## Last-known-good comparison rules

- Candidate results are compared with the approved last-known-good state using deterministic identifiers, canonical content, and integrity evidence.
- Comparisons must distinguish canonical content changes from informational metadata such as execution timestamps.
- A candidate may replace last-known-good state only after all required verification, review, and publication gates succeed.
- Failed, interrupted, partial, unverifiable, or nondeterministic candidates cannot replace last-known-good state.
- Rejected candidates and comparison evidence remain available for audit and explanation.

## Verification and test gates

- Repeat-run equality: identical canonical inputs and policy produce identical run identity and canonical results.
- Independent-run identifier stability: identifiers remain equal across separate processes or runs.
- Input-set verification: membership, exclusions, duplicates, and unavailable inputs are deterministic and evidenced.
- Ordering verification: canonical ordering is independent of provider, filesystem, dictionary, network, and scheduling order.
- Artifact verification: canonical serialization, integrity evidence, and immutable approval are independently checkable.
- Timestamp/randomness/environment isolation: incidental execution context cannot alter canonical results silently.
- Cache exclusion: cache hits, misses, invalidation, and rebuilds do not alter canonical results or last-known-good state.
- Partial-failure safety: incomplete or unverifiable runs do not mutate governed state or approved artifacts.
- Last-known-good comparison: only fully verified candidates can become replacements.
- Preflight/certification safety: verification paths do not repair or mutate state.
- Reproducible-record completeness: the run/build record contains the evidence needed for independent comparison.

## Forbidden nondeterminism sources

The following sources must not determine canonical execution or output:

- Generation order or process timing.
- Incidental enumeration sequence.
- Unstable provider, filesystem, dictionary, or network ordering.
- Uncontrolled timestamps or random values.
- Unrecorded environment, dependency, locale, timezone, or machine-path differences.
- Mutable or non-rebuildable caches.
- Hidden provider state copied into ChannelForge canonical state.
- Silent repair, mutation, or replacement during preflight or certification.
- Partial, failed, interrupted, unverifiable, or nondeterministic runs updating governed state.
- In-place mutation of approved generated artifacts.

## Issue #77 completion evidence mapping

This artifact satisfies the #77 governance requirements by defining:

- Deterministic run identity and input-set membership.
- Canonical ordering and stable identifier rules under ADR 0010.
- Artifact integrity, hashing expectations, and approved-artifact immutability.
- Reproducible run/build record contents.
- Timestamp, randomness, and environment handling.
- Cache exclusion and rebuildability rules.
- Last-known-good comparison and replacement rules.
- Verification/test gates and forbidden nondeterminism sources.
- Partial-failure and preflight/certification no-mutation rules.

#77 remains open until this artifact is reviewed and its issue checklist is reconciled. It does not close #72 or #61, authorize feature implementation, authorize updater work, or generate release artifacts.
