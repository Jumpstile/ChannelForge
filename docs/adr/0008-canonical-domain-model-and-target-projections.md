# ADR 0008: Canonical domain model versus target projections

## Status

Accepted

## Context

ChannelForge must aggregate provider and guide information while preserving provider-owned systems as the systems of record. Without canonical, target-neutral abstractions, identity, evidence, user decisions, and target-specific behavior can become duplicated or coupled to one provider or output target.

## Decision

ChannelForge will define canonical abstractions for:

- Station identity
- Channel mappings
- Match candidates
- Evidence records
- Confidence decisions
- Review actions
- Build plans
- Change sets
- Published artifacts
- Target compatibility profiles
- Run records
- Last-known-good snapshots

Canonical abstractions must remain target-neutral. Provider-owned playback, DVR, scheduling, entitlement, account, billing, storage, and service-specific state remain outside ChannelForge ownership.

Target profiles and output projections may transform or omit canonical facts for a target, but must not rewrite canonical identity or evidence.

Evidence, inference, and user choice must remain distinguishable.

## Consequences

- One canonical model can support multiple output projections.
- Provider-specific and target-specific behavior remains at integration boundaries.
- Unsupported target behavior remains visible rather than silently becoming canonical state.
- Review and explainability can refer to stable concepts.

## Verification

- Each abstraction has one owner and lifecycle.
- Canonical and target-specific concepts are separated.
- Provider-owned state is explicitly excluded.
- Evidence, inference, and user choice are separately represented.

## Related Issues

- #72
- #75
