# Blocker #2 contract freeze record

This file is governance metadata for the contract revisions in this directory. It is not part of any revision content and is excluded from RevisionContentId. This file defines and weakens no normative rule. Every rule referenced here is stated normatively in README.md; the text here is operating procedure and is invalid wherever it disagrees. The revision identity rules are in README.md under Revision identity and freeze separation.

## blocker-2-contract/v1

- Status: FROZEN. Current authority until blocker-2-contract/v2 is frozen.
- Entry state: immutable, append-only.
- ContractRevisionId: `blocker-2-contract/v1`
- RevisionContentId: `9d54cdd12b44196bdfd2f999703d24fbd691a2f584af788ad25a68fdfe63362d`
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
- Version control pointers, non-normative: content commit `af9d5da3dc81fc4d484a9f475bc0da884d0d880c`, content tree `e3a341826f5080f378316ed333d221246f1f5660`, attestation commit `8ded7836ade413434f3398a43e8f71a3edcf3774`.
- Provenance note: this attestation was originally appended to README.md by commit `8ded7836ade413434f3398a43e8f71a3edcf3774`, which produced a different five-file content with tree pointer `a4035d032277cd2835733510e3838665bf377e84`. Under the revision identity model that appended text is governance metadata. It is transcribed here, and blocker-2-contract/v1 denotes RevisionContentId `9d54cdd12b44196bdfd2f999703d24fbd691a2f584af788ad25a68fdfe63362d` only.

## blocker-2-contract/v2

- Status: NOT FROZEN / PENDING APPROVALS.
- Entry state: pending, editable in place until this revision is frozen.
- ContractRevisionId: `blocker-2-contract/v2`
- RevisionContentId: `e08338a3a5c9e76ec82ff161f49bff4135b00948d3a75ef1aece7d546f03a874`
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
- Superseded candidate content: RevisionContentId `9c8757017ef313decd7c72bfef27d77183d5acaba838457f5b3083b14ebbdda6`, last published at commit `e8ddd909a72f1b9ea25b647eda49be73f0eb0541`, and the earlier candidate contents `e3550af7aea7190cfa19dae73ecb2d6a9e93abeaf93c2e75493785b66dd1f821` and `ea89f2961ce17af9b995ab1b328db06e38e216026d15ca5cbe932e6be97ffd92`. Any review result recorded for a superseded content attests that content only and does not carry to RevisionContentId `e08338a3a5c9e76ec82ff161f49bff4135b00948d3a75ef1aece7d546f03a874`.
- Effect while pending: blocker-2-contract/v1 remains the frozen authority. Implementation, release work, and merges against blocker-2-contract/v2 remain prohibited until every approval above is recorded and this record names the frozen commit SHA of blocker-2-contract/v2.

## Recording rules

- This file records attestation facts only: reviewer identity, review outcome, approval date, the RevisionContentId under attestation, candidate or frozen commit SHA, version control pointers, and superseded markers.
- An entry for a PENDING revision may be edited in place until that revision is frozen.
- An entry for a FROZEN revision is immutable and append-only. Its ContractRevisionId, RevisionContentId, approval results, and approval date are never edited in place, and the binding between a frozen ContractRevisionId and its RevisionContentId is never re-pointed or retired here.
- A correction to a frozen entry is recorded as a new dated correction entry that names the corrected field, the superseded value, and the corrected value. The superseded value remains readable.
- Appending an attestation fact, or adding a dated correction entry, does not create a new ContractRevisionId.
- Any change to README.md, PART-A-canonical-foundation.md, PART-B-semantic-schemas.md, PART-C-promotion-recovery.md, or SYMBOL-CLOSURE.md produces a different RevisionContentId and requires a new ContractRevisionId and a new freeze cycle.
- A candidate or frozen commit SHA is recorded by a later metadata commit, because a commit cannot contain its own identity.
- RevisionContentId is verified independently from any checkout of the five normative files, using the PART-A section 3 formula, with:

```sh
sha256sum PART-A-canonical-foundation.md PART-B-semantic-schemas.md PART-C-promotion-recovery.md README.md SYMBOL-CLOSURE.md > manifest.txt
{ printf 'contract-revision-content/v1'; printf '\0'; cat manifest.txt; } | sha256sum
```

  The listed file order is ascending file-name byte order, and the default sha256sum output line is already the digest, two ASCII spaces, the file name exactly as listed above with no directory component, and one LF.
