# Blocker #2 contract artifact

This directory is the stable repository artifact for the accepted Blocker #2 design. It is design/review evidence only. It authorizes no implementation, branch, pull request, merge, deployment, or release decision.

The source contract is the published standalone contract in GitHub issue #60, comment 5410735336. PART-A, PART-B, and PART-C are verbatim section moves from that contract; the contract wording is not rewritten. SYMBOL-CLOSURE.md contains only the nine known closure definitions requested after architectural acceptance. In blocker-2-contract/v2, PART-B section 5 and section 6 carry the bounded raw occurrence digest amendment recorded under Revision history; no other contract wording is rewritten.

## File map

- [PART-A-canonical-foundation.md](./PART-A-canonical-foundation.md) — authority, paths, canonical bytes, domains, source identity, and safe text.
- [PART-B-semantic-schemas.md](./PART-B-semantic-schemas.md) — M3U, XMLTV, candidate, review, decision, and accepted-state projections.
- [PART-C-promotion-recovery.md](./PART-C-promotion-recovery.md) — immutable promotion, journal protocol, recovery classification, fault hooks, and tests.
- [SYMBOL-CLOSURE.md](./SYMBOL-CLOSURE.md) — the additive closure definitions and the validation inventory.

The three contract parts are read together. A later part cannot weaken an earlier definition. The closure document is normative only for the symbols it defines; it does not redesign or regenerate the contract.

## Symbol-closure rule

Every referenced hash domain, enum, schema, property order, projection, and recovery classification must have exactly one definition across this directory. Duplicate definitions are invalid, and an unresolved reference is invalid. The closure inventory at the end of SYMBOL-CLOSURE.md is the review checklist for this rule.

## Scope boundary

No product implementation, database, scheduler, GUI, provider adapter, NAS behavior, or release certification is included in this artifact.

## Governance and freeze control

Accountable owner: ChannelForge Product Owner. The owner is accountable for contract scope, reviewer coordination, supersession, and freeze approval.

Approver: ChannelForge Architecture Authority. The approver grants architecture acceptance and freeze approval after the required technical, adversarial, and governance reviews are complete.

Canonical artifact location: docs/adr/blocker-2-contract/. The contract revision identifier is ContractRevisionId = blocker-2-contract/v2. This identifier denotes the exact five-file v2 contents at the canonical artifact location; a branch name, draft, or working-tree state is not a revision identifier. The immediately prior revision is blocker-2-contract/v1, frozen at commit af9d5da3dc81fc4d484a9f475bc0da884d0d880c, and it is superseded by this revision.

The supersession and change-control authority is the Accountable Contract Owner acting with the Approver. Any proposed change must identify the prior ContractRevisionId, describe the targeted delta, and produce a new versioned revision. No amendment may silently modify a frozen revision.

The mandatory review sequence is ordered as follows:

1. Technical preservation review confirms that the accepted technical content is preserved and that any delta is bounded.
2. Adversarial review checks determinism, safety, recovery, and unresolved contract gaps.
3. Governance review confirms ownership, scope, authority, and change-control compliance.
4. Architecture acceptance approves the complete versioned revision.
5. Freeze approval records the ContractRevisionId, Accountable Contract Owner, reviewers, approval results, and approval date.

Implementation is unblocked only when a versioned contract revision exists, all required reviewers have approved it, freeze approval is recorded, and the frozen ContractRevisionId is referenced by the implementation work. Any contract modification after freeze automatically invalidates the freeze and requires the review sequence and freeze approval to run again for the new revision.

Every implementation or release work item must reference the frozen ContractRevisionId. Implementation is prohibited against a draft, a superseded revision, or an amendment that has not completed the required approvals and freeze. This governance artifact remains review evidence only and is not release certification or release evidence.

## Freeze approval record

- ContractRevisionId: `blocker-2-contract/v2`
- Contract artifact location: `docs/adr/blocker-2-contract/`
- Prior ContractRevisionId: `blocker-2-contract/v1`
- Prior frozen commit SHA: `af9d5da3dc81fc4d484a9f475bc0da884d0d880c`
- Prior freeze approval date: 2026-08-25
- Accountable owner: ChannelForge Product Owner
- Approver: ChannelForge Architecture Authority
- Independent reviewers:
  - OMP Desktop — independent specification and consistency reviewer
  - OMP Arcade — independent adversarial, determinism, and recovery reviewer
- Approval results:
  - Technical preservation review: pending
  - OMP Desktop: pending
  - OMP Arcade: pending
  - ChannelForge Architecture Authority: pending
- Freeze approval date: pending
- Frozen commit SHA: pending
- Freeze status: not frozen. The blocker-2-contract/v1 freeze is invalidated by this revision. Implementation, release work, and PR merges against blocker-2-contract/v2 remain prohibited until every approval above is recorded and this record names the frozen commit SHA.

## Revision history

### blocker-2-contract/v2

Prior revision: blocker-2-contract/v1, frozen commit af9d5da3dc81fc4d484a9f475bc0da884d0d880c.

Defect corrected: v1 PART-B section 5 excluded only the digest field itself from the RawM3UOccurrenceDigest projection, while SourceLocalOrdinal was a declared RawM3UOccurrence property and the first key of the canonical ordinal sort tuple. Ordinal assignment and digest computation therefore each required the other, and no conforming implementation existed. v1 also asserted that equal complete raw occurrences have identical digests, which is unsatisfiable while a per-occurrence ordinal is a digest input, and it never defined the RawXMLTVOccurrenceDigest or RawProgrammeDigest projections even though both XMLTV ordinal sort tuples use those digests as the final tie-breaker.

Bounded delta:

1. PART-B section 5 excludes SourceLocalOrdinal from the RawM3UOccurrenceDigest projection and states that projection exactly.
2. PART-B section 6 excludes StructuralOccurrenceOrdinal from the RawXMLTVOccurrenceDigest and RawProgrammeDigest projections and states both projections exactly.
3. README records the revision identifier, freeze metadata, this revision history, and the ratifications below. It states no schema definition.

Preserved without change: every canonical sort tuple in PART-B section 5 and section 6, duplicate detection and DuplicateCount semantics, exact raw evidence with Missing, empty, and whitespace-only distinctions, guide binding as exact raw ordinal equality, the EntryId, BindingKey, programme identity, StructuralEvidenceHash, and GuideCandidateIdRecord inputs, every other schema, enum, property order, and projection, all canonical byte and serialization rules, all paths, the journal and recovery protocol, the fault hook inventory, the acceptance test catalog, and all governance rules.

Ratifications:

- The raw occurrence hash domain identifiers raw-m3u-occurrence/v2, raw-xmltv-occurrence/v2, and raw-programme/v2 are retained unchanged under blocker-2-contract/v2. The corrected projections are distinguished by ContractRevisionId, not by new domain strings, so the PART-A exhaustive v2 semantic domain inventory is unchanged.
- Hash values computed under the corrected projections differ from values computed under the v1 wording, which changes EntryId, BindingId, BuildIdentity, CandidateManifestHash, and candidate namespace directory names. No accepted generation, pointer, journal, or previous-generation artifact exists, so no persisted-state migration is required and no compatibility shim is authorized.
- Retaining the digest as the leading key of the M3U ordinal sort tuple is ratified. Every remaining tuple key is a declared raw occurrence property, so the digest is redundant for total ordering, but EntryId already binds RawM3UOccurrenceDigest, so a future digest revision changes entry identity whether or not ordinals are renumbered. Keeping the tuple verbatim preserves the frozen ordering text, keeps the decisive comparison on fixed lowercase 64-hex ASCII, and keeps the delta bounded to the digest projections.
