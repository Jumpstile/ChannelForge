# Blocker #2 contract proposal 4

Status: FROZEN.

ProposalId: `blocker-2-contract/proposal-4`

ContractRevisionId: `blocker-2-contract/v8`

Prior frozen authority: `blocker-2-contract/v7`

Exact RevisionContentId is recorded in the governance FREEZE-RECORD for this
revision. It is excluded from this normative file to avoid self-reference.

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
`RevisionContentId` is computed only from the exact five normative files. The
exact value is governance metadata in `FREEZE-RECORD.md`, which is excluded
from the five-file content hash to avoid a self-reference.

V8 supersedes v7 as the complete frozen contract revision. Existing candidate
semantic surfaces retain `CandidateContractVersion =
blocker-2-contract/v7`. Acceptance, promotion, and recovery surfaces use
`AcceptanceContractVersion = blocker-2-contract/v8-acceptance`.

Runtime acceptance, promotion, recovery, pointer publication, and generation
publication may begin only after this corrected frozen authority is integrated
into the intended target branch. This file authorizes no runtime
implementation before that integration.

The integration review packet records preserved v7 values, cross-part symbol
ownership, validation categories, and the governance evidence for this frozen
revision.
