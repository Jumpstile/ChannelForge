# PR #1 Architecture Evidence

## Authority

- ContractRevisionId: `blocker-2-contract/v7`
- RevisionContentId: `c2779f69a54695237cdb4dafa87e231a2a53d597fba11769e2fbcea9cf85cd8a`
- Branch: `review/issue-60-blocker-2-candidate-canonicalization`
- HEAD at packet preparation: `0bdbafb`

## Fresh validation

- Focused and evidence suites: 78 passed, 0 failed, 0 skipped.
- Full unit suite: 518 passed, 0 failed, 0 skipped.
- Syntax/parser: PASS.
- Production static analysis: 0 Error-severity findings.
- `git diff --check`: PASS.

## C01-C17

| ID | Exact hook name | Implementation | Evidence | Result |
|---|---|---|---|---|
| C01 | CandidateStageWrite.Manifest | `ConvertTo-ChannelForgeCandidateCanonical.ps1` / artifact writer | `CandidateHookEvidence.Tests.ps1` | PASS |
| C02 | CandidateStageFlush.Manifest | same | same | PASS |
| C03 | CandidateStageReopenHash.Manifest | same | same | PASS |
| C04 | CandidateStageWrite.M3U | same | same | PASS |
| C05 | CandidateStageFlush.M3U | same | same | PASS |
| C06 | CandidateStageReopenHash.M3U | same | same | PASS |
| C07 | CandidateStageWrite.XMLTV | same | same | PASS |
| C08 | CandidateStageFlush.XMLTV | same | same | PASS |
| C09 | CandidateStageReopenHash.XMLTV | same | same | PASS |
| C10 | CandidateStageWrite.ReviewJSON | same | same | PASS |
| C11 | CandidateStageFlush.ReviewJSON | same | same | PASS |
| C12 | CandidateStageReopenHash.ReviewJSON | same | same | PASS |
| C13 | CandidateStageWrite.ReviewMarkdown | same | same | PASS |
| C14 | CandidateStageFlush.ReviewMarkdown | same | same | PASS |
| C15 | CandidateStageReopenHash.ReviewMarkdown | same | same | PASS |
| C16 | CandidateDirectoryMove.Before | `Publish-ChannelForgeCandidateNamespace.ps1` | `CandidateHookEvidence.Tests.ps1` | PASS |
| C17 | CandidateDirectoryMove.After | same | same | PASS |

C01-C17 exercised: 17/17. C01-C17 passed: 17/17. Hook identifiers are explicit names; no numeric ordering is used.

C16 proves staging remains unpublished at the before-move boundary. C17 proves final move, post-move reopen validation, and candidate-only publication. Invalid bytes, missing merged content, and extra files fail namespace validation.

## Input hashes

`M3UInputArtifactHashEvidence.Tests.ps1` proves path independence, local/remote equivalence, one-byte mutation, lowercase 64-hex output, and empty-hash rejection. Production remote M3U hashing fails closed unless the computed `input-m3u/v2` value matches `^[0-9a-f]{64}$`.

## Review counts

`ReviewCountMatrix.Tests.ps1` proves:

- RawM3UOccurrenceCount = 6, including pre-dedup duplicate;
- RawXMLTVOccurrenceCount = 5, excluding three RawProgrammeOccurrence records;
- ExactBindingCount = 2;
- UnboundCount = 2;
- ReviewNeededCount = 1;
- XMLTVOnlyCount = 3;
- RejectedXMLTV does not affect UnboundCount or XMLTVOnlyCount.

## Namespace isolation

`CandidateNamespaceEvidence.Tests.ps1` snapshots protected state/public surfaces before and after candidate-only build and asserts equality. Candidate namespace publication is the only intended mutation. Review-only namespaces and malformed/extra-artifact namespaces fail validation.

## Determinism and byte evidence

`DeterministicComparisonEvidence.Tests.ps1` builds equivalent fixtures with different paths and source ordering and compares BuildIdentity, guide evidence digests, candidate artifacts, review artifacts, manifest bytes/hash, and namespace identity. It also checks UTF-8/BOM/newline/property-order constraints for review artifacts.

## Carried contract debt

PR #1 does not close:

- DuplicateCount storage ambiguity;
- Journal field-sequence restatement;
- `pointer/v2`, `accepted-state/v2`, `active-m3u/v2`, `active-xmltv/v2`, `previous-m3u/v2`, `previous-xmltv/v2`, `decision-m3u/v2`, `decision-xmltv/v2`, `generation-manifest/v2`, and `previous-output-manifest/v2`.

These are carried frozen-contract debt outside candidate-only PR #1 scope. No compliance claim is made for later acceptance/promotion surfaces.

## Status

The implementation, focused suites, evidence suites, full unit suite, parser, analyzer, and diff checks are green. Exact architecture-packet hash/value capture and final acceptance review remain external review gates.
