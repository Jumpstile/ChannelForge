# ADR 0010: Deterministic runs, clocks, identifiers, ordering, and serialization

## Status

Accepted

## Context

ChannelForge's core value depends on repeatable, explainable outputs. Runtime timestamps, random identifiers, unstable enumeration, incomplete tie-breaking, locale-dependent behavior, or non-canonical serialization can make identical inputs produce different results.

## Decision

Identical approved inputs, configuration, and knowledge state must produce identical meaningful artifacts and decisions.

The determinism contract must define:

- Module loading order
- Source and record ordering
- Complete tie-breaking
- Locale-independent normalization
- Stable identifiers
- Runtime clocks
- Canonical serialization
- Warning and error ordering
- Artifact hashing
- Separation of deterministic artifacts from volatile diagnostics

Stable identifiers must be derived deterministically from canonical input content or keys, not from generation order, process timing, or incidental enumeration sequence, so that identical inputs produce identical identifiers across separate runs, not merely within one run.

Volatile metadata may be recorded for operations and diagnostics but must not alter deterministic artifacts.

## Consequences

- Builds can be compared and reproduced.
- Evidence-backed changes can be reviewed reliably.
- Deterministic behavior becomes testable rather than aspirational.
- Runtime metadata must be deliberately separated from canonical output.

## Verification

- Ordering and tie-breaking rules are complete.
- Time and random identifiers cannot change deterministic artifacts.
- Normalization and serialization rules are explicit.
- Artifact determinism is tested independently from diagnostic metadata.

## Related Issues

- #72
- #77
