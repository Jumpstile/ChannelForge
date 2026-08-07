# ADR 0007: Modular boundaries and dependency direction

## Status

Proposed

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

Each module must have defined responsibilities, inputs, outputs, non-goals, and tests.

Domain concepts must remain target-neutral. Application entry points must orchestrate modules rather than contain their business logic. External providers and targets must remain behind explicit adapter or projection boundaries.

The project may retain one deployable PowerShell module initially. Physical module separation is not required until the logical contracts are proven.

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
