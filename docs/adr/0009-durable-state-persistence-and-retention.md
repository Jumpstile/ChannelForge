# ADR 0009: Durable state, persistence, migrations, caching, and retention

## Status

Proposed

## Context

ChannelForge requires database-backed state where appropriate for identity, evidence, decisions, source history, incremental work, and recovery. At the same time, declarative configuration, generated artifacts, caches, and provider-owned state must not be treated as interchangeable sources of truth.

## Decision

ChannelForge will define separate authorities for:

- Declarative configuration
- Operational run state
- Identity and mapping knowledge
- Evidence and provenance
- Source snapshots and caches
- Last-known-good state
- Generated artifacts
- Review and approval records
- Audit history
- Provider-owned state

Durable state must have explicit schema evolution, migration, retention, backup, recovery, and integrity expectations.

Generated artifacts must not silently become canonical state. Provider-owned state must remain with the provider.

## Consequences

- Repeated full rescans can be replaced by durable, indexed state where appropriate.
- Recovery can preserve known-good state across source failures.
- State lifecycle and retention become explicit architecture concerns.
- Persistence does not create a second provider system of record.

## Verification

- Every state category has one authority.
- File, database, cache, artifact, and provider-owned boundaries are documented.
- Migration and retention expectations are defined.
- Last-known-good state is explicitly represented.

## Related Issues

- #72
- #76
- #36
