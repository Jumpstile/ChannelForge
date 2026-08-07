# ChannelForge Module Contract Matrix

## Purpose

This document is the required acceptance artifact for ADR 0007 and the primary contract artifact for issue #74.

It defines the responsibilities, boundaries, dependency direction, and verification expectations for ChannelForge's twelve logical modules.

## Relationship to ADR 0003 and ADR 0007

ADR 0003 defines ChannelForge's three-layer architecture and inward dependency direction.

ADR 0007 refines that architecture into twelve logical module boundaries. The twelve modules do not replace ADR 0003's layers or create a fourth layer. Each module must preserve ADR 0003's rule that domain concepts do not depend on infrastructure-specific concepts.

One deployable PowerShell module remains acceptable initially. The logical boundaries and contracts must be explicit before feature implementation expands the system, but physical module separation is not required at this stage.

## Matrix

| Module | ADR 0003 layer | Responsibilities | Inputs | Outputs | Non-goals | Allowed dependencies | Forbidden dependencies | Tests / verification gates |
|---|---|---|---|---|---|---|---|---|
| Domain | Domain | Own target-neutral concepts and domain invariants. | Canonical domain contracts and values. | Canonical domain objects and decisions. | No provider, target, persistence, transport, or UI ownership. | Domain contracts and approved shared value definitions. | Infrastructure-specific concepts, provider state, target-specific behavior, UI, direct persistence. | Domain isolation, invariant, and dependency-direction checks. |
| Identity and matching | Domain | Establish identity mappings and match candidates. | Normalized source records, domain concepts, and matching policy. | Match candidates, mappings, and identity decisions. | No provider-state ownership, target projection, publication, or UI behavior. | Domain, ingestion outputs, and configuration/policy contracts. | Output targets, provider service state, direct publication, UI behavior. | Deterministic matching, candidate explainability, and contract checks. |
| Evidence and confidence | Domain | Preserve provenance, evidence, confidence, inference, and user-choice distinctions. | Source facts, match candidates, evidence metadata, and review inputs. | Evidence records, confidence decisions, and review-relevant results. | No silent inference, canonical rewriting, or publication ownership. | Domain, ingestion metadata, identity/matching contracts, and security/audit contracts. | Target-specific rewriting, direct publication, unreviewed destructive action. | Evidence separation, provenance completeness, confidence contract, and reviewability checks. |
| Configuration and policy | Application | Own declarative configuration and policy interpretation. | Configuration sources and policy inputs. | Validated configuration and policy contracts. | No runtime-state ownership, provider behavior, or domain-decision ownership. | Domain and configuration/policy contracts. | Provider adapters, durable operational writes, external provider/network I/O, UI decisions, publication behavior. | Validation, precedence, source-of-truth, and contract checks. |
| Application/build orchestration | Application | Coordinate module execution and build flow. | Configuration, policies, module contracts, and run requests. | Orchestration results, run coordination, build plans, and change coordination. | No hidden domain logic or direct replacement of module responsibilities. | Explicit contracts for participating modules. | New canonical business rules, provider-specific logic, persistence internals, UI logic. | Orchestration-only checks, dependency direction, and contract integration checks. |
| Operations and recovery | Application | Coordinate run status, recovery, last-known-good handling, and operational diagnostics. | Run state, artifacts, recovery inputs, and operational policy. | Recovery results, run status, diagnostics, and last-known-good transitions. | No new canonical authority or provider service-state ownership. | Application orchestration, durable storage, output/artifact, and security/audit contracts. | Domain rule ownership, provider service state, silent destructive recovery. | Recovery, rollback, last-known-good, and diagnostic-separation checks. |
| UI and coaching | Application | Present evidence, decisions, review actions, and educational guidance. | Application results, evidence, confidence, and review contracts. | Review actions, user choices, and coaching output. | No domain decisions, direct provider writes, or persistence bypass. | Application, evidence, confidence, and review-action contracts. | Direct domain mutation, provider integration, direct durable writes, hidden automation. | Explainability, review-action, and user-decision boundary checks. |
| Ingestion | Infrastructure | Acquire and normalize external source records. | External source inputs and ingestion policy. | Normalized records, source metadata, and acquisition results. | No canonical identity decisions, publication, or UI behavior. | Configuration/policy, security/audit, and ingestion boundary contracts. | Target projections, publication, UI, provider-owned canonical state. | Malformed-input, normalization, source-boundary, and provenance checks. |
| Durable storage | Infrastructure | Persist approved operational, identity, evidence, review, audit, and recovery state. | Persistence contracts and approved state transitions. | Durable state, retrieval results, integrity results, and recovery inputs. | No domain business rules or provider-owned system of record. | Domain/state contracts, persistence boundaries, operations/recovery, and security/audit contracts. | Provider service state, hidden canonical rewrites, UI logic, unapproved destructive writes. | Authority, integrity, migration, retention, backup, recovery, and last-known-good checks. |
| Provider and guide adapters | Infrastructure | Isolate provider and guide integrations and external capabilities. | External provider/guide inputs, configuration, and adapter contracts. | Adapter results, normalized integration results, and target capability projections. | No canonical identity/evidence rewriting or provider-state ownership. | Explicit domain projection, ingestion, configuration, and security/audit contracts. | Hidden provider ownership, direct UI coupling, unreviewed publication, canonical model redefinition. | Adapter isolation, capability-boundary, trust, and contract checks. |
| Output and publication | Infrastructure | Produce target projections and controlled publication artifacts. | Canonical artifacts, target profiles, publication policy, and security evidence. | Target projections, generated artifacts, and publication results. | No canonical model mutation or unverified writes. | Canonical artifact, target-profile, provider/guide adapter, and security/audit contracts. | Identity/evidence rewriting, source ingestion, UI decisions, unverified publication. | Projection fidelity, artifact integrity, publication authorization, and write-safety checks. |
| Security and audit | Cross-cutting | Define trust, redaction, audit, and security-evidence controls across boundaries. | Boundary events, security evidence, sensitive values, and audit inputs. | Security decisions, audit records, redacted evidence, quarantine, or review requirements. | No fail-open bypass, silent trust inheritance, updater implementation, or ownership bypass of domain, storage, publication, or adapter contracts. | Explicit boundary contracts across all modules. | Unverified trust, secret leakage, unsafe writes, silent bypass, updater behavior. | Redaction, fail-closed, quarantine, audit completeness, path safety, backup, verification, and rollback checks. |

## What this satisfies for #74

This artifact satisfies the matrix portion of #74 by documenting, for all twelve modules:

- Responsibilities
- Inputs
- Outputs
- Non-goals
- ADR 0003 layer placement
- Allowed dependencies
- Forbidden dependencies
- Tests and verification gates

It also provides the explicit dependency-direction artifact required by ADR 0007 and confirms that application entry points remain orchestration-only.

## What remains before #72 can close

The matrix alone does not close #72. The parent governance gate still requires:

- #73 completion.
- #74 completion and approval of this matrix.
- #75 completion of canonical abstraction ownership and lifecycle definitions.
- #76 completion of state-category authority definitions.
- #77 completion of determinism contract and verification artifacts.
- #61 and #78 completion of security evidence gates.
- Confirmation that module, state, determinism, and security contracts are explicit.
- Confirmation that feature implementation remains blocked until the parent gate is complete.

This document authorizes no feature implementation, physical module split, updater behavior, or `pr-23-auto-update` merge.
