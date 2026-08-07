# ChannelForge Durable State and Persistence Matrix

## Purpose

This document is the repository artifact for issue #76 and ADR 0009.

It defines persistence boundaries, state-category ownership, authority rules, lifecycle expectations, and verification gates for ChannelForge durable state.

This document defines persistence boundaries and authority rules. It does not select a database, file format, cache technology, migration framework, or backup implementation.

It does not implement features or authorize updater work.

## Governing boundaries

Durable storage enforces persistence contracts but does not own the business meaning of every state category.

Provider services remain the source of truth for provider-owned state. ChannelForge must not create a second provider system of record.

Approved publication artifacts are immutable records. Corrections create governed replacement artifacts rather than mutating approved artifacts in place.

## State and persistence matrix

| State category | Owner module / business meaning | Authority / source of truth | Allowed creators | Allowed mutators | Allowed consumers | Persistence requirement | Retention expectation | Migration/versioning expectation | Backup/recovery expectation | Last-known-good behavior | Integrity/hash expectations | Audit/security requirements | Tests / verification gates |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Declarative configuration | Configuration and policy | Approved declarative configuration | Configuration and policy through approved configuration inputs | Configuration and policy through governed policy changes | Application/build orchestration, ingestion, identity/matching, adapters, output/publication | Preserve according to configuration authority; do not silently copy into operational state | Governed by configuration lifecycle and repository policy | Version configuration semantics; migration framework is intentionally unspecified | Back up through configuration/repository controls; recovery restores an approved configuration state | Last-known-good configuration remains identifiable when a change is rejected or rolled back | Integrity evidence for approved configuration where required | Exclude secrets and credentials; audit policy and approval changes | Source-of-truth, precedence, validation, integrity, and rollback checks |
| Operational run state | Application/build orchestration | Durable run records and approved run transitions | Application/build orchestration | Application/build orchestration and Operations/recovery through explicit transitions | Operations/recovery, evidence/confidence, durable storage, UI/coaching, output/publication | Durable where required for repeatability, recovery, and audit | Retain according to operational lifecycle and recovery needs | Version run records and transitions; migration mechanism unspecified | Back up and restore run state with integrity verification | Preserve a known-good run or last successful transition when a run fails | Stable run identity and integrity evidence; hash expectations defined by contract | Record actor, transition, source inputs, trust, and failure evidence | Legal transition, reproducibility, recovery, and audit checks |
| Identity and mapping knowledge | Identity and matching | Canonical identity and approved mapping state | Identity/matching through domain contracts and approved review actions | Identity/matching and authorized review actions only | Evidence/confidence, target/profile, output/publication, UI/coaching | Durable persistence expected where mappings affect future runs | Retain history needed to explain mapping changes and recover known-good mappings | Version identity/mapping records without selecting a schema or migration framework | Back up approved mappings and support governed recovery | Preserve last-known-good mapping state when new evidence is rejected | Deterministic identity and mapping integrity expectations | Preserve evidence, reviewer choice, provenance, and redaction | Target neutrality, deterministic identity, ownership, and reviewability checks |
| Evidence and provenance | Evidence and confidence | Evidence records and provenance chain | Ingestion, adapters, and review-controlled evidence paths | Append/reconcile through evidence rules; no silent rewrite | Confidence/review, orchestration, output/publication, security/audit | Durable where evidence affects decisions, recovery, or future runs | Retain according to decision, provenance, and audit requirements | Version evidence records and provenance relationships; mechanism unspecified | Back up evidence with integrity and redaction controls | Preserve evidence supporting the last-known-good decision | Hash or integrity evidence where required to detect alteration | Redaction, source attribution, freshness, trust, and audit context required | Provenance completeness, evidence/inference separation, freshness, and redaction checks |
| Source snapshots | Ingestion | Ingestion-owned captured source evidence used for repeatability and provenance | Ingestion | Ingestion and governed recovery/re-capture paths | Normalized records, evidence/confidence, Operations/recovery | Persist when needed for repeatability, provenance, recovery, or incremental work | Retain according to provenance and repeatability needs; expiration must be explicit | Version captured-source representation; migration mechanism unspecified | Back up where required for repeatability and recovery; restore with integrity checks | Preserve the source snapshot supporting an approved or last-known-good decision | Detect alteration or truncation where integrity matters | Redact sensitive values and record source trust and capture context | Capture, normalization, provenance, retention, integrity, and replay checks |
| Caches | Ingestion or the module producing the derived performance state | Derived performance state; never the canonical source of truth | Owning producer through an explicit cache contract | Owning producer; cache invalidation and rebuild are governed | Modules consuming the derived performance result | Disposable and rebuildable; persistence is optional and must not become canonical state | Explicit expiration, invalidation, and rebuild expectations | Cache versioning and invalidation rules are explicit; migration framework unspecified | Recovery may discard and rebuild caches; cache restore must not override canonical state | Last-known-good state must not depend solely on a cache | Detect stale, corrupt, or mismatched cache content where needed | Do not cache secrets or credentials; avoid sensitive logging | Rebuildability, invalidation, staleness, and canonical-state isolation checks |
| Last-known-good state | Operations and recovery | Explicit approved last-known-good record | Operations/recovery from approved run, artifact, or state transitions | Operations/recovery through governed rollback or replacement | Orchestration, output/publication, security/audit, review surfaces | Durable persistence required | Retain until explicitly superseded under governed policy | Version references to the state, run, and artifact that established it | Back up, restore, verify, and roll back without silent mutation | Failed or unverified work must not replace last-known-good state | Verify references and hashes for the protected state/artifact | Record approval, rollback reason, evidence, and actor | Failure recovery, rollback, integrity, and replacement-gate checks |
| Generated artifacts | Output and publication | Approved generated artifact and publication record; artifact is not canonical state | Output/publication after approved inputs and policy | No in-place mutation after approval; governed replacement only | Targets, Operations/recovery, security/audit, review surfaces | Persist approved artifacts and their publication records where required | Retain according to publication, rollback, and last-known-good needs | Version artifact schema/serialization; migration framework unspecified | Back up approved artifacts and verify before restore or publication | Preserve the approved last-known-good artifact when a replacement is rejected | Stable serialization, content hash, and integrity verification required | Redact secrets; record approval, publication, backup, and rollback evidence | Deterministic content, immutable approval, safe writes, backup, and rollback checks |
| Review and approval records | Evidence and confidence | Review and approval history | Evidence/confidence and explicit authorized review actions | Governed review transitions only | Orchestration, output/publication, UI/coaching, security/audit | Durable persistence required where decisions affect future runs or publication | Retain decision, actor, evidence basis, and transition history | Version review states and decision transitions; mechanism unspecified | Back up and recover without changing the recorded decision history | Last-known-good approval remains identifiable after rejected or failed changes | Integrity evidence protects review history from silent alteration | Record actor, reason, evidence, trust, and redaction context | Explainability, legal transitions, reviewer attribution, and audit checks |
| Audit history | Security and audit | Audit history and security evidence | Security/audit boundary and authorized module events | Append-only or governed correction paths | Security/audit, Operations/recovery, review, durable storage | Durable persistence required | Explicit retention, redaction, access, and integrity expectations | Version event schema and retention rules; mechanism unspecified | Back up and restore with integrity verification | Preserve audit evidence for last-known-good and rollback decisions | Tamper detection and event-chain integrity expectations where required | Redaction, least-privilege access, trust-boundary evidence, and review required | Completeness, redaction, fail-closed, quarantine, and integrity checks |
| Provider-owned state | Provider service, outside ChannelForge ownership | Provider service remains the source of truth | Provider service | Provider service under provider rules | ChannelForge adapters consume permitted provider capabilities and references | Not persisted as duplicated ChannelForge state; only governed references/evidence may be retained | Provider controls retention; ChannelForge does not impose a second lifecycle | Provider owns schema and migration; ChannelForge does not migrate provider state | Provider owns backup/recovery; ChannelForge records integration/recovery evidence only | Provider remains authoritative; ChannelForge cannot silently substitute its own last-known-good provider state | Verify references and evidence without claiming provider-state ownership | Do not copy secrets, tokens, private connection details, or service state into normal artifacts | Ownership-boundary, capability, trust, and non-duplication checks |

## Secrets and credentials exclusion

Secrets, credentials, provider tokens, and private connection details are not normal durable state in this matrix.

They must be handled by a separate secrets-management boundary and must not be:

- Committed.
- Cached.
- Logged.
- Included in generated artifacts.
- Treated as canonical configuration data.
- Copied into provider-owned or ChannelForge-owned state without an approved security boundary.

## Forbidden storage shortcuts

The following shortcuts are prohibited:

- Durable storage becoming the business owner of every state category.
- Generated artifacts becoming canonical state.
- Caches or source snapshots becoming the source of truth.
- ChannelForge duplicating provider service state.
- UI bypassing persistence contracts.
- Approved publication artifacts being mutated in place.
- Preflight/certification paths triggering repair or mutation.
- Unverified or unaudited state transitions.
- Persistence logic silently rewriting canonical identity, evidence, or review decisions.
- Secrets or credentials being committed, cached, logged, or included in artifacts.

## Issue #76 completion evidence

This artifact satisfies the state-boundary portion of #76 by defining, for each state category:

- Owner module and business meaning.
- Authority/source of truth.
- Allowed creators, mutators, and consumers.
- Persistence requirement.
- Retention expectation.
- Migration/versioning expectation.
- Backup/recovery expectation.
- Last-known-good behavior.
- Integrity/hash expectations.
- Audit/security requirements.
- Tests and verification gates.

#76 remains open until this artifact is reviewed, approved, and its issue checklist is reconciled. This artifact does not close #72 or #61, authorize feature implementation, or authorize updater work.
