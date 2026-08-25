# Blocker #2 contract freeze record

This file is governance metadata for the contract revisions in this directory. It is not part of any revision content, it is excluded from RevisionContentId, and it defines, restates, and weakens no normative rule. The revision identity rules are in README.md under Revision identity and freeze separation.

## blocker-2-contract/v1

- Status: FROZEN. Current authority until blocker-2-contract/v2 is frozen.
- ContractRevisionId: `blocker-2-contract/v1`
- RevisionContentId: `e3a341826f5080f378316ed333d221246f1f5660`
- Content commit: `af9d5da3dc81fc4d484a9f475bc0da884d0d880c`
- Attestation commit: `8ded7836ade413434f3398a43e8f71a3edcf3774`
- Accountable owner: ChannelForge Product Owner
- Approver: ChannelForge Architecture Authority
- Independent reviewers:
  - OMP Desktop, independent specification and consistency reviewer
  - OMP Arcade, independent adversarial, determinism, and recovery reviewer
- Approval results:
  - OMP Desktop: PASS / approved
  - OMP Arcade: PASS / approved
  - ChannelForge Architecture Authority: PASS / approved
- Approval date: 2026-08-25
- Provenance note: this attestation was originally appended to README.md by commit `8ded7836ade413434f3398a43e8f71a3edcf3774`, which produced the different five-file content tree `a4035d032277cd2835733510e3838665bf377e84`. Under the revision identity model that appended text is governance metadata. It is transcribed here, and blocker-2-contract/v1 denotes tree `e3a341826f5080f378316ed333d221246f1f5660` only.

## blocker-2-contract/v2

- Status: NOT FROZEN / PENDING APPROVALS.
- ContractRevisionId: `blocker-2-contract/v2`
- RevisionContentId: `2fc271e3c1de832341d50801a5633014c198d858`
- Candidate commit: pending
- Accountable owner: ChannelForge Product Owner
- Approver: ChannelForge Architecture Authority
- Independent reviewers:
  - OMP Desktop, independent specification and consistency reviewer
  - OMP Arcade, independent adversarial, determinism, and recovery reviewer
- Approval results:
  - Technical preservation review: pending
  - OMP Desktop: pending
  - OMP Arcade: pending
  - ChannelForge Architecture Authority: pending
- Freeze approval date: pending
- Frozen commit SHA: pending
- Superseded candidate content: the earlier v2 candidate content tree `3f97ebd305bdc20a670e9d33c0b6ce33efb6bdf8`, last committed at `0d969a34d83cdbf2031c67f0d18c37983fa610a1`, received a technical preservation PASS and an OMP Desktop governance PASS. Those results attest that content only. They do not carry to RevisionContentId `2fc271e3c1de832341d50801a5633014c198d858`, which adds the revision identity model and must be reviewed again.
- Effect while pending: blocker-2-contract/v1 remains the frozen authority. Implementation, release work, and merges against blocker-2-contract/v2 remain prohibited until every approval above is recorded and this record names the frozen commit SHA of blocker-2-contract/v2.

## Recording rules

- This file records attestation facts only: reviewer identity, review outcome, approval date, RevisionContentId under attestation, candidate or frozen commit SHA, and superseded markers.
- Appending or correcting those facts does not create a new ContractRevisionId.
- Any change to README.md, PART-A-canonical-foundation.md, PART-B-semantic-schemas.md, PART-C-promotion-recovery.md, or SYMBOL-CLOSURE.md creates a different revision content and requires a new ContractRevisionId and a new freeze cycle.
- A candidate commit SHA is recorded by a later metadata commit, because a commit cannot contain its own identity.
