# ChannelForge Security and Trust Boundary Matrix

## Purpose and relationship to ADR 0011 and #61

This document is the repository artifact for issue #78, ADR 0011, and the Security & Trust Boundaries epic #61.

It defines security, trust, authorization, redaction, quarantine, audit, and publication-boundary contracts for ChannelForge. It does not implement features or select security technologies.

This document defines security and trust boundary contracts. It does not select a secrets manager, scanner, logging stack, quarantine implementation, audit store, policy engine, updater mechanism, or security vendor.

All writes, publication actions, quarantine releases, trust promotions, and state transitions are denied by default unless an explicit boundary contract authorizes them.

Feature implementation remains blocked. Updater implementation remains unauthorized, and `pr-23-auto-update` remains outside scope.

## Trust-boundary inventory

| Boundary | Trust posture | Authority and responsibility | Required controls |
|---|---|---|---|
| UI and coaching | User-facing and untrusted for direct state ownership | Presents explanations and requests governed actions | No direct mutation of canonical identity, evidence, durable state, provider state, or approved publication artifacts |
| Configuration and policy | Controlled input subject to validation and review | Owns declarative policy and authorization inputs | Validate, preserve provenance, exclude secrets, and deny unauthorized changes |
| Ingestion | External and source-dependent | Captures source evidence and provenance | Classify, validate, preserve snapshots where authorized, and quarantine unsafe input |
| Identity/matching and evidence/confidence | Domain trust boundary | Owns canonical identity, evidence, confidence, and review contracts | Do not promote untrusted evidence or rewrite ownership through adapters or UI |
| Durable storage | Persistence enforcement boundary | Persists authorized state without owning all business meaning | Enforce authorization, integrity, audit, and state-transition contracts |
| Provider and guide adapters | External integration boundary | Consumes permitted provider capabilities and evidence | Treat responses as untrusted; do not duplicate provider state or rewrite canonical decisions |
| Output and publication | External write and target boundary | Owns publication authorization and immutable approved artifacts | Verify, authorize, audit, and use governed replacements rather than in-place mutation |
| Operations and recovery | Recovery and last-known-good boundary | Coordinates authorized recovery transitions | No silent repair, mutation, or replacement from verification-only paths |
| Security and audit | Cross-cutting control boundary | Preserves trust, authorization, redaction, and audit evidence | Enforce fail-closed behavior and ownership contracts without becoming business owner of other modules |
| External providers, guides, network, and filesystem | Outside ChannelForge trust | Remain external authorities or untrusted resources | Validate, classify, constrain, and retain only governed evidence or references |
| Updater | Deferred and out of scope | No updater ownership is defined here | No implementation, updater-state ownership, or `pr-23-auto-update` expansion is authorized |

## Input and source trust classifications

Every external or user-supplied input must have an explicit trust classification before it can influence a governed decision:

- **Trusted:** validated evidence or state from an authorized ChannelForge boundary with intact integrity and provenance.
- **Verified external:** external data that passed the applicable validation and integrity gates but remains externally sourced.
- **Unverified:** data received without sufficient validation, provenance, or integrity evidence.
- **Stale:** data whose freshness or applicability window is exceeded or unknown.
- **Conflicting:** data that conflicts with authoritative state or other evidence and requires review.
- **Malformed or unsafe:** data that fails parsing, path, integrity, authorization, or security checks.
- **Quarantined:** data isolated from canonical state pending an authorized review or disposition.
- **Unavailable:** expected data that cannot be obtained or verified; absence must not be silently treated as approval.

Trust promotions require explicit evidence, an authorized boundary, and an auditable transition. Unknown trust is not trusted by default.

## Provider and guide adapter trust boundaries

- Provider and guide responses are external inputs and must be validated and classified before use.
- Adapters may translate permitted capabilities, references, and evidence into ChannelForge contracts.
- Adapters must not rewrite canonical identity, evidence confidence, review decisions, durable state ownership, or publication authorization.
- Provider services remain authoritative for provider-owned state; ChannelForge must not create a second provider system of record.
- Credentials, tokens, private URLs, and provider connection details must not be copied into normal logs, caches, durable state, or generated artifacts.
- Provider inconsistency, unavailable evidence, failed validation, or ambiguous ownership requires quarantine or review escalation.

## Secrets and credential handling boundary

Secrets, credentials, provider tokens, and private connection details are outside normal durable state and generated artifacts. They require a separate secrets-management boundary.

Sensitive values include provider URLs containing credentials, API keys, tokens, cookies, private guide URLs, account identifiers where sensitive, local filesystem paths where sensitive, private network addresses where sensitive, and any user-supplied secret or credential-like value.

Sensitive values must not be committed, cached, logged, displayed, included in generated artifacts, or copied across module boundaries without an explicit authorized security contract. This document does not select the secrets-management implementation.

## Redaction and logging rules

- Redact sensitive values before logging, displaying, persisting, or publishing diagnostic context.
- Redaction must cover direct values, embedded credentials, tokens, cookies, private URLs, sensitive paths, and credential-like user input.
- Logs and audit evidence must not retain raw secrets, credentials, private tokens, or sensitive payloads.
- Redaction failure is a security failure and must fail closed for the affected operation.
- Diagnostic metadata may be retained only when it does not become canonical state or expose protected values.

Audit evidence must preserve enough context to explain and investigate decisions without retaining raw secrets, credentials, private tokens, or sensitive payloads.

## Path safety and filesystem write boundaries

- Paths must be canonicalized and validated before access.
- Reads and writes must be constrained to explicitly authorized locations and artifact types.
- Traversal, ambiguous paths, unsafe links, unexpected destinations, private locations, and unauthorized overwrites must be rejected or quarantined.
- Publication and durable-state writes require explicit authorization, integrity evidence, and audit evidence.
- UI, adapters, preflight, certification, and arbitrary callers must not bypass path or write contracts.
- A path-validation failure must not be repaired silently or converted into an alternate write destination.

## Quarantine behavior

- Malformed, untrusted, conflicting, stale where material, unverifiable, or security-suspicious inputs and outputs must be isolated from canonical state.
- Quarantine records preserve source, trust classification, reason, integrity evidence, and required review context without retaining prohibited sensitive values.
- Quarantine is not approval and must not promote data automatically.
- Release, rejection, or replacement from quarantine requires an explicit authorized boundary and auditable decision.
- Preflight and certification paths may report or verify quarantine state but cannot release, repair, mutate, or publish it.

## Fail-closed requirements

The following conditions must fail closed: unknown trust, missing authorization, failed integrity, hash mismatch, unsafe path, redaction failure, ambiguous ownership, invalid transition, unavailable required evidence, and publication or audit-evidence failure.

Fail-closed behavior must not publish, mutate approved artifacts, update last-known-good state, rewrite identity or evidence decisions, release quarantine, or bypass audit. Partial, failed, interrupted, or unverifiable operations must leave governed state unchanged.

## Audit and security evidence requirements

Authorized transitions must record, as applicable, the actor or boundary, source, trust classification, authorization basis, decision, evidence references, integrity result, redaction result, quarantine disposition, publication result, failure reason, and timestamp as non-canonical audit context.

Audit history must be durable where required, protected against silent alteration, access-controlled, redacted, and sufficient for review, recovery, and investigation. Audit evidence must preserve enough context to explain and investigate decisions without retaining raw secrets, credentials, private tokens, or sensitive payloads.

## Publication and write authorization boundary

- All writes and publication actions are denied by default unless an explicit boundary contract authorizes them.
- Output and publication owns target-boundary contracts and approved publication records.
- Approved generated artifacts are immutable. Corrections create governed replacement artifacts rather than mutating approved artifacts in place.
- Publication requires validated inputs, sufficient trust, integrity evidence, authorization, and audit evidence.
- Durable storage enforces persistence contracts but does not authorize business actions by itself.
- UI, adapters, preflight, certification, and security/audit cannot bypass the owning publication or state-transition contract.

## Updater exclusion and deferred trust boundary

No updater implementation, updater-state ownership, updater security contract, or `pr-23-auto-update` expansion is authorized by this artifact. Any future updater work requires a separately scoped trust-boundary review, architecture decision, authorization model, and verification evidence.

## Preflight and certification no-mutation boundary

Preflight and certification paths are observation and verification paths only. They may validate, report, fail closed, or request review. They must not trigger repair, mutation, publication, replacement, quarantine release, trust promotion, or silent state correction.

## Review-needed escalation rules

Escalate for review when trust is ambiguous, evidence conflicts, integrity fails, a hash mismatches, authorization is missing, a path is unsafe, redaction is uncertain, a provider response conflicts with authority, quarantine disposition is requested, publication evidence is incomplete, or ownership is unclear.

Review escalation must preserve unresolved state and evidence. It must not silently convert uncertainty into approval or authorize a mutation outside the owning contract.

## Forbidden security shortcuts

The following shortcuts are prohibited:

- Trusting external or user-supplied input by default.
- Treating provider responses as canonical ChannelForge state.
- Committing, caching, logging, displaying, or publishing secrets and credentials.
- Retaining raw secrets, credentials, private tokens, or sensitive payloads in audit evidence.
- Bypassing redaction or treating redaction failure as harmless.
- Writing outside authorized filesystem paths or silently changing destinations.
- Publishing without validation, authorization, integrity evidence, or audit evidence.
- Mutating approved artifacts in place.
- Allowing UI or adapters to bypass module ownership contracts.
- Treating quarantine as approval.
- Failing open on unknown trust, missing authorization, integrity failure, or ambiguous ownership.
- Letting preflight or certification repair, mutate, publish, release, or promote state.
- Copying updater state into normal ChannelForge state.
- Bypassing audit and security evidence requirements.

## Verification and test gates

- Trust classification, provenance, and promotion checks.
- Secret detection, redaction, and sensitive-value exclusion checks.
- Path traversal, unsafe-link, authorized-location, and unauthorized-write checks.
- Quarantine isolation, evidence preservation, and release-approval checks.
- Fail-closed behavior for authorization, integrity, redaction, path, ownership, and audit failures.
- Audit completeness, access control, redaction, and tamper-evidence checks.
- Publication authorization, immutable-artifact, and governed-replacement checks.
- Provider and guide adapter ownership-boundary and non-duplication checks.
- Preflight/certification no-mutation checks.
- Review escalation and unresolved-state preservation checks.
- Updater exclusion and `pr-23-auto-update` scope checks.

## Issue #78 and #61 completion evidence mapping

This artifact satisfies the #78 governance requirements by defining:

- Trust boundaries and input/source classifications.
- Provider and guide adapter trust limits.
- Secrets, credentials, sensitive-value, redaction, and audit-without-secret-retention rules.
- Path safety, filesystem write, quarantine, and fail-closed contracts.
- Publication authorization, immutability, and governed replacement rules.
- Deferred updater scope and preflight/certification no-mutation rules.
- Review escalation, forbidden shortcuts, and verification gates.

#78 remains open until this artifact is reviewed and its issue checklist is reconciled. #61 and #72 remain open until separately reconciled. This artifact does not authorize feature implementation, updater work, or release artifacts.
