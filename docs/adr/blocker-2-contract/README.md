# Blocker #2 contract artifact

This directory is the stable repository artifact for the accepted Blocker #2 design. It is design/review evidence only. It authorizes no implementation, branch, pull request, merge, deployment, or release decision.

The source contract is the published standalone contract in GitHub issue #60, comment 5410735336. PART-A and PART-C remain verbatim section moves from that contract. PART-B remains verbatim except for the bounded section 5 and section 6 raw occurrence digest amendments recorded under Revision history. No other contract wording is rewritten. SYMBOL-CLOSURE.md contains only the nine known closure definitions requested after architectural acceptance.

## File map

- [PART-A-canonical-foundation.md](./PART-A-canonical-foundation.md) — authority, paths, canonical bytes, domains, source identity, and safe text.
- [PART-B-semantic-schemas.md](./PART-B-semantic-schemas.md) — M3U, XMLTV, candidate, review, decision, and accepted-state projections.
- [PART-C-promotion-recovery.md](./PART-C-promotion-recovery.md) — immutable promotion, journal protocol, recovery classification, fault hooks, and tests.
- [SYMBOL-CLOSURE.md](./SYMBOL-CLOSURE.md) — the additive closure definitions and the validation inventory.
- [FREEZE-RECORD.md](./FREEZE-RECORD.md) — governance metadata that attests freeze approvals. It is not part of revision content and is excluded from RevisionContentId.

The three contract parts are read together. A later part cannot weaken an earlier definition. The closure document is normative only for the symbols it defines; it does not redesign or regenerate the contract.

## Symbol-closure rule

Every referenced hash domain, enum, schema, property order, projection, and recovery classification must have exactly one definition across this directory. Duplicate definitions are invalid, and an unresolved reference is invalid. The closure inventory at the end of SYMBOL-CLOSURE.md is the review checklist for this rule.

## Scope boundary

No product implementation, database, scheduler, GUI, provider adapter, NAS behavior, or release certification is included in this artifact.

## Revision identity and freeze separation

A contract revision is identified by its normative content only. The normative revision content of this artifact is exactly these five files:

README.md
PART-A-canonical-foundation.md
PART-B-semantic-schemas.md
PART-C-promotion-recovery.md
SYMBOL-CLOSURE.md

RevisionContentId uses this contract's own hash discipline and no other scheme. RevisionContentManifest is UTF-8 text containing one line per normative file, in ascending file-name byte order, where each line is the lowercase 64-hex SHA-256 of that file's exact bytes, two ASCII spaces, the file name exactly as listed above with no directory component, and one LF. RevisionContentId is H(contract-revision-content/v1, RevisionContentManifest), where H is the single hash formula defined in PART-A section 3, D is the exact ASCII domain string contract-revision-content/v1, and B is the exact RevisionContentManifest bytes. This definition introduces no new hash formula, no alternative byte layout, and no second hashing scheme.

contract-revision-content/v1 is a governance-level domain. The inventory in PART-A section 3 is described there as the exhaustive v2 semantic domain inventory, and its exhaustiveness is over contract-semantic domains only, meaning the domains of hashes over lineup, candidate, review, decision, output, state, journal, and pointer content. contract-revision-content/v1 is outside that scope. It is not a semantic hash domain, it never appears in a semantic projection, a hash dependency graph, a manifest field, or an accepted-state field, it identifies artifact revisions only, and it neither extends nor amends the PART-A inventory.

The enclosing commit, its parents, the branch name, the version control system, and any additional file in this directory do not participate in RevisionContentId. Version control object identifiers such as commit, tree, and blob hashes are convenience pointers only. They are never the revision identity, and a pointer that disagrees with RevisionContentId is invalid.

ContractRevisionId is the durable name of one immutable RevisionContentId. One ContractRevisionId denotes exactly one RevisionContentId. If any byte of any of the five normative files changes, the result is a different revision that requires a new ContractRevisionId. The same ContractRevisionId is never reused for a second content. ProposalId identifies an in-progress contract proposal series and may point to successive candidate contents while the proposal is NOT FROZEN. ProposalId is not implementation authority and is not a ContractRevisionId. A ContractRevisionId is minted only when one exact RevisionContentId is submitted as an immutable approval and freeze candidate. Once minted, it can never be rebound to different normative content.

A revision never states its own RevisionContentId. That value is computed from the final content and is recorded only in governance metadata, exactly as a canonical object never contains its own hash.

FREEZE-RECORD.md is governance metadata. It attests approvals for a named ContractRevisionId and its RevisionContentId. It is excluded from revision content. FREEZE-RECORD.md defines and weakens no normative rule. It may restate normative operating rules for execution and verification, but README.md or the normative contract parts govern wherever the metadata differs.

Governance metadata may be appended or corrected without creating a new ContractRevisionId only when the change records attestation facts: reviewer identity, review outcome, approval date, the frozen commit SHA, the RevisionContentId under attestation, or a superseded marker. Every other change requires a new ContractRevisionId and a new freeze cycle, including any change to this section, the review sequence, ownership, approver authority, change-control rules, the freeze definition, the scope boundary, the symbol-closure rule, or any normative text in PART-A, PART-B, PART-C, or SYMBOL-CLOSURE.

blocker-2-contract/v1 identity is exact under this model. Its RevisionContentId is 9d54cdd12b44196bdfd2f999703d24fbd691a2f584af788ad25a68fdfe63362d, computed over the five-file content published at commit af9d5da3dc81fc4d484a9f475bc0da884d0d880c, whose non-normative tree pointer is e3a341826f5080f378316ed333d221246f1f5660. Commit 8ded7836ade413434f3398a43e8f71a3edcf3774 appended the v1 freeze attestation to README.md and therefore produced a different five-file content, tree pointer a4035d032277cd2835733510e3838665bf377e84. That second content is not a second blocker-2-contract/v1. The appended text is governance metadata, it is reclassified as such, and it is transcribed into FREEZE-RECORD.md. blocker-2-contract/v1 denotes RevisionContentId 9d54cdd12b44196bdfd2f999703d24fbd691a2f584af788ad25a68fdfe63362d only, and no v1 normative byte is modified by this revision.

This binding is immutable. Governance metadata can neither re-point nor retire the binding between a frozen ContractRevisionId and its RevisionContentId. An attestation of a frozen revision is append-only: it may be extended by a new dated entry, and any correction must be a new dated entry that cites the superseded value, never an edit in place. Metadata that contradicts a binding stated in revision content is invalid, and the binding in revision content governs.

Revision content records no freeze approval, reviewer result, approval date, or frozen commit SHA. Those attestation facts are recorded only in FREEZE-RECORD.md. Revision content may state conditional authority rules that depend on freeze state, including the rules in this section.

## Governance and freeze control

Accountable owner: ChannelForge Product Owner. The owner is accountable for contract scope, reviewer coordination, supersession, and freeze approval.

Approver: ChannelForge Architecture Authority. The approver grants architecture acceptance and freeze approval after the required technical, adversarial, and governance reviews are complete.

Canonical artifact location: docs/adr/blocker-2-contract/. ProposalId = blocker-2-contract/proposal-3. The proposed ContractRevisionId for this exact content is blocker-2-contract/v7, and its normative content is defined by Revision identity and freeze separation above. A branch name, draft, or working-tree state is not an identifier. The immediately prior frozen authority is blocker-2-contract/v6, whose RevisionContentId is e1c310fc27abf21906f24f40f0e341ed07c5ca1bd5ff1f8351768036744ed447, approved at candidate commit e63281b76ec7e26bfff85ff744c5c0a608de824e. Authority transfers to blocker-2-contract/v7 only when blocker-2-contract/v7 completes all required approvals and FREEZE-RECORD.md records its frozen commit SHA and RevisionContentId. blocker-2-contract/v1 is superseded only at that point. The earlier abandoned proposal label identifies abandoned proposal history only and is not implementation authority.

Until blocker-2-contract/v7 becomes frozen:

- Authority remains with blocker-2-contract/v1 under the rules of this section.
- blocker-2-contract/v7 remains a proposed revision and is not implementation authority; its ProposalId is blocker-2-contract/proposal-2.
- Implementation that depends on the corrected occurrence projection remains paused.
- Unrelated implementation work may continue against blocker-2-contract/v1 only where it does not depend on the amended contract semantics.

The supersession and change-control authority is the Accountable Contract Owner acting with the Approver. Any proposed change must identify the prior ContractRevisionId, describe the targeted delta, and produce a new versioned revision. No amendment may silently modify a frozen revision.

The mandatory review sequence is ordered as follows:

1. Technical preservation review confirms that the accepted technical content is preserved and that any delta is bounded.
2. Adversarial review checks determinism, safety, recovery, and unresolved contract gaps.
3. Governance review confirms ownership, scope, authority, and change-control compliance.
4. Architecture acceptance approves the complete versioned revision.
5. Freeze approval records the ContractRevisionId, Accountable Contract Owner, reviewers, approval results, and approval date.

Implementation is unblocked only when a versioned contract revision exists, all required reviewers have approved it, freeze approval is recorded, and the frozen ContractRevisionId is referenced by the implementation work. Any contract modification after freeze automatically invalidates the freeze and requires the review sequence and freeze approval to run again for the new revision.

Every implementation or release work item must reference the frozen ContractRevisionId. Implementation is prohibited against a draft, a superseded revision, or an amendment that has not completed the required approvals and freeze. This governance artifact remains review evidence only and is not release certification or release evidence.

## Revision history

### blocker-2-contract/v7

Prior revision: blocker-2-contract/v1, RevisionContentId 9d54cdd12b44196bdfd2f999703d24fbd691a2f584af788ad25a68fdfe63362d, published at commit af9d5da3dc81fc4d484a9f475bc0da884d0d880c.

Defect corrected: v1 PART-B section 5 excluded only the digest field itself from the RawM3UOccurrenceDigest projection, while SourceLocalOrdinal was a declared RawM3UOccurrence property and the first key of the canonical ordinal sort tuple. Ordinal assignment and digest computation therefore each required the other, and no conforming implementation existed. v1 also asserted that equal complete raw occurrences have identical digests, which is unsatisfiable while a per-occurrence ordinal is a digest input, and it never defined the RawXMLTVOccurrenceDigest or RawProgrammeDigest projections even though both XMLTV ordinal sort tuples use those digests as the final tie-breaker.

Bounded delta:

1. PART-B section 5 excludes SourceLocalOrdinal from the RawM3UOccurrenceDigest projection and states that projection exactly.
2. PART-B section 6 excludes StructuralOccurrenceOrdinal from the RawXMLTVOccurrenceDigest and RawProgrammeDigest projections and states both projections exactly.
3. README records the revision identifier, this revision history, and the ratifications below. It states no schema definition, no approval result, and no freeze approval fact.
4. README adds Revision identity and freeze separation, which defines revision content, RevisionContentId, the role of ContractRevisionId, and the separation of freeze attestation into FREEZE-RECORD.md. This resolves the blocker-2-contract/v1 ambiguity in which two different five-file contents both claimed one revision identifier.

Preserved without change: every canonical sort tuple in PART-B section 5 and section 6, duplicate detection and DuplicateCount semantics, exact raw evidence with Missing, empty, and whitespace-only distinctions, guide binding as exact raw ordinal equality, the EntryId, BindingKey, programme identity, StructuralEvidenceHash, and GuideCandidateIdRecord inputs, every other schema, enum, property order, and projection, all canonical byte and serialization rules, all paths, the journal and recovery protocol, the fault hook inventory, the acceptance test catalog, and all governance rules.

Ratifications:

- The raw occurrence hash domain identifiers raw-m3u-occurrence/v2, raw-xmltv-occurrence/v2, and raw-programme/v2 are retained unchanged under blocker-2-contract/v7. The corrected projections are distinguished by ContractRevisionId, not by new domain strings, so the PART-A exhaustive v2 semantic domain inventory is unchanged.
- Hash values computed under the corrected projections differ from values computed under the v1 wording, which changes EntryId, BindingId, BuildIdentity, CandidateManifestHash, and candidate namespace directory names. No accepted generation, pointer, journal, or previous-generation artifact exists, so no persisted-state migration is required and no compatibility shim is authorized.
- Retaining the digest as the leading key of the M3U ordinal sort tuple is ratified. Every remaining tuple key is a declared raw occurrence property, so the digest is redundant for total ordering, but EntryId already binds RawM3UOccurrenceDigest, so a future digest revision changes entry identity whether or not ordinals are renumbered. Keeping the tuple verbatim preserves the frozen ordering text, keeps the decisive comparison on fixed lowercase 64-hex ASCII, and keeps the delta bounded to the digest projections.

## Follow-up findings

These findings are recorded for a later revision. They are not part of the blocker-2-contract/v7 delta, they change no normative definition in this revision, and both were present in blocker-2-contract/v1.

- PART-B section 5 and section 6 state that exact duplicate multiplicity is stored in DuplicateCount, but DuplicateCount is not a declared property of RawM3UOccurrence, RawXMLTVChannelOccurrence, or RawProgrammeOccurrence, so its storage location is undefined. The blocker-2-contract/v7 digest input lists exclude it explicitly, so no digest projection in this revision is ambiguous.
- The Journal field sequence is restated in PART-C and in SYMBOL-CLOSURE.md section 5. Both statements list identical fields in identical order, so the restatement is consistent, but it is a second statement of one schema under the symbol-closure rule.


## Proposal-3 amendment scope

This proposal defines the central contract-version registry and closes the BuildIdentityInput schema. It is not a ContractRevisionId, is not implementation authority, and is not frozen. The proposed content must complete technical, adversarial, governance, and Architecture Authority review before v7 is minted.
