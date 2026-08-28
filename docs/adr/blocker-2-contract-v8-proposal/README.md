# Blocker #2 contract proposal 4

Status: PROPOSED / NOT FROZEN. This directory is contract/design review evidence only.

ProposalId: `blocker-2-contract/proposal-4`

Proposed revision label: `blocker-2-contract/v8`

Current frozen authority: `blocker-2-contract/v7`

Current frozen RevisionContentId: `c2779f69a54695237cdb4dafa87e231a2a53d597fba11769e2fbcea9cf85cd8a`

This proposal is the bounded successor to the frozen v7 contract. It proposes
normative definitions for these ten acceptance/promotion domains:
`pointer/v2`, `accepted-state/v2`, `active-m3u/v2`, `active-xmltv/v2`,
`previous-m3u/v2`, `previous-xmltv/v2`, `decision-m3u/v2`,
`decision-xmltv/v2`, `generation-manifest/v2`, and
`previous-output-manifest/v2`.

The proposal does not amend, reinterpret, or re-version v7 candidate
projections, candidate artifacts, candidate namespaces, or `BuildIdentity`.
Candidate fields and candidate hash domains retain
`blocker-2-contract/v7`. New acceptance/promotion fields use the scoped
`AcceptanceContractVersion` value `blocker-2-contract/v8-acceptance`; this
value is not an implementation authority or a minted revision identifier.
`Journal.Version` remains the literal integer `2` under PART-C; it is the
explicit journal-schema exception and is not `AcceptanceContractVersion`.

Normative proposal content is exactly these five files:

- `PART-A-canonical-foundation.md`
- `PART-B-semantic-schemas.md`
- `PART-C-promotion-recovery.md`
- `README.md`
- `SYMBOL-CLOSURE.md`

`ISSUE-106-TECHNICAL-REVIEW.md`, when present, is a non-normative integration
review packet. It is excluded from the five-file `RevisionContentId`
procedure, as are all other files and governance metadata.

`RevisionContentId` is computed only from the exact five normative files after
technical, adversarial, governance, and Architecture Authority review. No
`ContractRevisionId` or `RevisionContentId` has been minted for proposal-4.
The proposed revision label, a branch name, a commit SHA, and a working-tree
state are not revision authority.

Until proposal-4 is approved and frozen, v7 remains the sole authority for
existing candidate behavior. This proposal authorizes no runtime
acceptance, decision, promotion, recovery, pointer publication, generation
publication, or active-output implementation. Implementation must wait for a
new frozen `ContractRevisionId` and its independently reproducible
`RevisionContentId`.

The integration review packet records preserved v7 values, cross-part symbol
ownership, validation categories, and limitations that must be resolved or
explicitly accepted before freeze.
