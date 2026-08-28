# Blocker #2 contract proposal-4 freeze record

This file is governance metadata. It is excluded from RevisionContentId.

## blocker-2-contract/v8

- Status: FROZEN.
- ProposalId: `blocker-2-contract/proposal-4`.
- ContractRevisionId: `blocker-2-contract/v8`.
- RevisionContentId: `cbcbbd1ee1f8a59857562f6c5672def60bea16416fbfe8b95df1dca8354346cc`.
- Approved candidate commit: `cb2f640f8e3479e497e43a07fa50237380fcde44`.
- Prior frozen authority: `blocker-2-contract/v7`.
- Prior RevisionContentId: `c2779f69a54695237cdb4dafa87e231a2a53d597fba11769e2fbcea9cf85cd8a`.
- Approval evidence: Desktop technical preparation: PASS; OMP Arcade independent final review: APPROVE; Architecture acceptance: APPROVED FOR FREEZE.
- Authority effect: v8 supersedes v7 as the complete frozen contract revision.
- Retained candidate semantic surfaces: `CandidateContractVersion = blocker-2-contract/v7`.
- Acceptance/promotion/recovery semantic surfaces: `AcceptanceContractVersion = blocker-2-contract/v8-acceptance`.
- Freeze attestation commit: recorded by the commit that adds this metadata.

## RevisionContentId procedure

Compute SHA-256 for the exact Git-object bytes of the five normative files in this order:

```text
PART-A-canonical-foundation.md
PART-B-semantic-schemas.md
PART-C-promotion-recovery.md
README.md
SYMBOL-CLOSURE.md
```

Write each lowercase digest, two ASCII spaces, the filename, and one LF. Hash:

```text
UTF8("contract-revision-content/v1") || 0x00 || RevisionContentManifest
```

The resulting RevisionContentId is the value recorded above. This metadata file is excluded and cannot alter the revision identity.

## Dated correction — corrected normative candidate pending re-attestation

The prior entry's RevisionContentId `cbcbbd1ee1f8a59857562f6c5672def60bea16416fbfe8b95df1dca8354346cc` attested an earlier normative byte set. After freeze-status normalization of README.md, that attestation is superseded pending independent review and replacement metadata for the corrected candidate RCID `d80feb5b24a4c335badb288fe0d82339f84a0d6b417d3a0a5fc3f38f2b07c69d`. No corrected RCID is frozen by this entry.
