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

## Dated correction — 2026-08-29 — RCID byte-source integrity

The original freeze attestation above recorded
`874b96b871069ef67b505dce4eaa0c64f0be050b158db90492482bad16f625f7`.
That value is historical only and is invalid as an independently reproducible
RevisionContentId because its manifest mixed one LF-normalized payload hash
with three CRLF working-tree payload hashes. The original attestation is
preserved; this entry corrects its byte-source procedure without changing the
four normative files or their semantics.

- Correction status: CURRENT AUTHORITY.
- ContractRevisionId: `blocker-2-contract/v9`.
- Corrected RevisionContentId: `1396db7098973a1ef7469e851d308dc7aad47a8cd61a0d675e85717e7ae84192`.
- Canonical byte source: exact payload bytes of the Git blobs addressed by the
  canonical content commit and path, read from the Git object database with
  `git cat-file blob`; working-tree bytes are never consumed.
- Canonical Git content commit: `d6d63f9dea56acbf1edbc9339ba97971b7a2a571`.
- Equivalent preserved integration commits: #109 merge
  `97a0d1d64dc1a0a074acbdcba3b98a978c3e41a7`; current main
  `6f55478ab6498affa59429d37f35586b302ba98b`.
- CandidateContractVersion: `blocker-2-contract/v8`.
- AcceptanceContractVersion: `blocker-2-contract/v8-acceptance`.
- #102 binding: the Issue #102 implementation retains its existing code and
  versions; its authority metadata must cite this corrected v9 attestation.

### Governance decision

The selected repair is an append-only corrective attestation in this
governance file (Option A implemented without rewriting the historical entry).
It preserves the original invalid RCID, retains `ContractRevisionId` v9, and
declares one current RCID for the unchanged four-file normative byte set.

Option B, a separate unattached attestation, would preserve history but leave
authority discovery ambiguous. Option C, a successor governance revision,
would unnecessarily change the contract identity without a semantic change.
No alternate approach provides a smaller unambiguous correction.

`CandidateContractVersion`, `AcceptanceContractVersion`, candidate bytes, and
acceptance bytes are unchanged. Future freeze attestations MUST use the
verifier in `scripts/Verify-ContractRevisionId.ps1` against Git object bytes;
the verifier rejects any manifest whose per-file digest differs from the
addressed Git blob payload, including a mixed LF/CRLF manifest.

The four canonical Git-object payload hashes at the canonical content commit
are:

| File                           | Git blob object                            | SHA-256 of exact Git blob payload                                  | LF checkout SHA-256                                                | CRLF checkout SHA-256                                              |
| ------------------------------ | ------------------------------------------ | ------------------------------------------------------------------ | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| PART-A-canonical-foundation.md | `2e420ddf10c660df840e880040a0d0e56d49bb89` | `a96d9a5a35e7aab4c8c9293ad262fc0c71c0ba100ce7b147c5e0ad9027190670` | `a96d9a5a35e7aab4c8c9293ad262fc0c71c0ba100ce7b147c5e0ad9027190670` | `86a4c35284c20922fe9296d09f48d32000235e1e2542530979716fae77e9b764` |
| PART-B-entry-output-slice.md   | `5f14e214932afe4ea0f0c031a6465d95bd129005` | `ddcda96326692c9619b8830efc6194d5e50e3d45efab5ad743dc85d75170babf` | `ddcda96326692c9619b8830efc6194d5e50e3d45efab5ad743dc85d75170babf` | `6e94795a80fe686e338380622358308304d935e86b7a7c0160f2c2b952c1382d` |
| README.md                      | `bd9d7c609febb32bd75742741ea7411a671fbb3f` | `01453629d3956f1cb11e8729ee8860394eb0f735e521fca7c842ca22a71206f3` | `01453629d3956f1cb11e8729ee8860394eb0f735e521fca7c842ca22a71206f3` | `735b966e04a45360bd03117600576698a8233563319250e87f1e1cde998fe427` |
| VERSION-OWNERSHIP-MAP.md       | `820c4d4cefdfaa88ae6d5d59e04c4e1424acd57b` | `acda1382d1d8232664555d78324022adf6b43cb5f30c1081f970733e7cf4233c` | `acda1382d1d8232664555d78324022adf6b43cb5f30c1081f970733e7cf4233c` | `e907a2fcedbf2870043faf6d3609cee3a1f7943a117e13b50135d8fdcde5ba4d` |

The corrected canonical manifest is delimited for automated verification:

<!-- RCID-GIT-MANIFEST-BEGIN -->

```text
a96d9a5a35e7aab4c8c9293ad262fc0c71c0ba100ce7b147c5e0ad9027190670  PART-A-canonical-foundation.md
ddcda96326692c9619b8830efc6194d5e50e3d45efab5ad743dc85d75170babf  PART-B-entry-output-slice.md
01453629d3956f1cb11e8729ee8860394eb0f735e521fca7c842ca22a71206f3  README.md
acda1382d1d8232664555d78324022adf6b43cb5f30c1081f970733e7cf4233c  VERSION-OWNERSHIP-MAP.md
```

<!-- RCID-GIT-MANIFEST-END -->

Independent reproduction:

```powershell
pwsh -File scripts/Verify-ContractRevisionId.ps1 `
  -RepositoryRoot . `
  -Commit eef60709888a37689c551efc9df5b66715b7e7b7 `
  -AttestationPath docs/adr/blocker-2-contract-v9-proposal/FREEZE-RECORD.md `
  -ExpectedRevisionContentId 1396db7098973a1ef7469e851d308dc7aad47a8cd61a0d675e85717e7ae84192
```

The verifier resolves each path to its immutable Git blob, streams the exact
blob payload through `git cat-file blob`, compares every declared per-file
hash, reconstructs the LF-delimited manifest, and verifies the final
`RevisionContentId`. It fails closed on a missing, reordered, duplicate,
mixed-source, or mismatched manifest entry. The verifier does not read
normative files from the working tree.

## Dated integration update — 2026-08-29 — Issue #103 runtime

The corrected v9 authority above remains unchanged. Issue #103 implements the
runtime-only immutable generation staging, pointer replacement, journal
transitions, safe-handle identity checks, and restart classification against
`ContractRevisionId = blocker-2-contract/v9` and
`RevisionContentId = 1396db7098973a1ef7469e851d308dc7aad47a8cd61a0d675e85717e7ae84192`.
This entry is nonnormative integration status; it does not modify the frozen
normative byte set.
