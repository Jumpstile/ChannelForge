# ChannelForge blocker #2 contract v9 freeze record

This file is governance metadata. It is excluded from RevisionContentId. The
normative frozen content is defined by README.md and consists of the four files
listed in the RevisionContentId procedure below.

## blocker-2-contract/v9

- Status: FROZEN.
- ContractRevisionId: `blocker-2-contract/v9`.
- RevisionContentId: `874b96b871069ef67b505dce4eaa0c64f0be050b158db90492482bad16f625f7`.
- Approved freeze-candidate predecessor commit: `11a0bcb090d0a26cac763caf78e221ea7194f377`.
- Prior frozen authority: `blocker-2-contract/v8`.
- Prior RevisionContentId: `d80feb5b24a4c335badb288fe0d82339f84a0d6b417d3a0a5fc3f38f2b07c69d`.
- CandidateContractVersion: `blocker-2-contract/v8`.
- AcceptanceContractVersion: `blocker-2-contract/v8-acceptance`.
- Issue relationship: Issue #109 freezes the EntryOutputSlice and EntryContentHash erratum only.
- Activation deferral: complete CandidateContractVersion v8 registry activation remains owned by Issue #110. Public candidate-v8 activation remains fail-closed; the bounded private slice producer is not production activation.
- Issue #102 relationship: #102 remains blocked and is not resumed by this freeze.
- Independent review evidence: OMP Arcade approved the narrow Issue #109 candidate for freeze preparation.
- Validation evidence: Issue #109 suite 12/12 PASS; frozen-v7 deterministic evidence 2/2 PASS; production guard matrix PASS; Markdown hygiene PASS; Markdown links PASS; parser/static PASS; PSScriptAnalyzer reported 0 Error-severity findings; git diff --check PASS.
- Freeze attestation commit: recorded by the commit that adds this metadata.

## RevisionContentId procedure

Compute SHA-256 for the exact bytes of these four normative files in this
canonical path order:

```text
PART-A-canonical-foundation.md
PART-B-entry-output-slice.md
README.md
VERSION-OWNERSHIP-MAP.md
```

For each file, write its lowercase SHA-256 digest, two ASCII spaces, the
basename exactly as listed above, and one LF. Hash:

```text
UTF8("contract-revision-content/v1") || 0x00 || RevisionContentManifest
```

The final manifest used for this record was:

```text
a96d9a5a35e7aab4c8c9293ad262fc0c71c0ba100ce7b147c5e0ad9027190670  PART-A-canonical-foundation.md
6e94795a80fe686e338380622358308304d935e86b7a7c0160f2c2b952c1382d  PART-B-entry-output-slice.md
735b966e04a45360bd03117600576698a8233563319250e87f1e1cde998fe427  README.md
e907a2fcedbf2870043faf6d3609cee3a1f7943a117e13b50135d8fdcde5ba4d  VERSION-OWNERSHIP-MAP.md
```

The resulting RevisionContentId is the value recorded above. This metadata
file is excluded and cannot alter the revision identity.
