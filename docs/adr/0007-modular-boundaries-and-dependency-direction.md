# ADR 0007: Modular boundaries and dependency direction

## Status

Accepted

## Context

ChannelForge currently has conceptual layers, but the repository does not yet define enforceable module responsibilities, dependency direction, or contract ownership. Without that boundary, feature work can expand the central script and mix domain decisions, configuration, external integration, persistence, output, and UI behavior.

## Decision

ChannelForge will define logical modules before feature implementation expands the system.

The logical boundaries are:

- Domain
- Configuration and policy
- Ingestion
- Identity and matching
- Evidence and confidence
- Durable storage
- Application/build orchestration
- Provider and guide adapters
- Output and publication
- Operations and recovery
- Security and audit
- UI and coaching

ADR 0003 defines the three-layer architecture and dependency direction. ADR 0007 refines that model into twelve logical module boundaries; it does not replace the layers or create a fourth layer. Domain, identity and matching, and evidence and confidence refine the Domain layer. Configuration and policy, application/build orchestration, operations and recovery, and UI and coaching refine the Application layer. Ingestion, durable storage, provider and guide adapters, and output and publication refine the Infrastructure layer. Security and audit is a cross-cutting boundary that applies across the three layers while preserving ADR 0003's rule that domain objects do not depend on infrastructure-specific concepts. All module dependencies must preserve ADR 0003's inward dependency direction.

Each module must have defined responsibilities, inputs, outputs, non-goals, and tests.

The module contract matrix is the required acceptance artifact for this ADR. It must document the responsibilities, inputs, outputs, non-goals, tests, and dependency direction for all twelve logical module boundaries.

Domain concepts must remain target-neutral. Application entry points must orchestrate modules rather than contain their business logic. External providers and targets must remain behind explicit adapter or projection boundaries.

One deployable PowerShell module remains acceptable initially. Logical boundaries and contracts are required before feature work expands the system; physical module separation is not required until the contracts are proven.

## Consequences

- Feature work has explicit ownership boundaries.
- Provider and target integrations cannot redefine canonical domain state.
- Architecture can evolve without requiring immediate physical package splitting.
- Contract and dependency tests become part of architecture verification.

## Verification

- A module contract matrix exists.
- Each logical module has responsibilities, inputs, outputs, non-goals, and tests.
- Dependency direction is documented.
- Application entry points are limited to orchestration.

## Related Issues

- #72
- #74

## Related ADRs

- ADR 0003: Use clean layered architecture
