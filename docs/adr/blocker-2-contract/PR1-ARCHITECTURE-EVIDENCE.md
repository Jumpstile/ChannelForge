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

`M3UInputArtifactHashEvidence.Tests.ps1` proves path independence, local/remote equivalence, one-byte mutation, lowercase 64-hex output, and empty-hash rejection.

Production remote M3U hashing fails closed unless the computed `input-m3u/v2` value matches `^[0-9a-f]{64}$`.

## BuildIdentityInput

`New-ChannelForgeCandidateManifest.ps1` constructs the local `$buildInput` projection and hashes it with `candidate-manifest/v2`. The projection is not emitted as a separate artifact; the observable value is `BuildIdentity` in the manifest and review outputs.

| BuildIdentityInput member | Repository evidence | Focused evidence |
|---|---|---|
| Contract and identity-rule versions | `$buildInput` sets `ContractVersion = blocker-2-contract/v7` and `IdentityRulesVersion = lineup-history-v1`. | `CandidateVersionRegistryEvidence.Tests.ps1` asserts the frozen-v7 version on emitted projections. |
| Parser, serializer, and guide-binding versions | `$buildInput` includes the M3U/XMLTV parser and serializer contract versions and `GuideBindingContractVersion = guide-binding-exact-ordinal-v1`. | `CandidateCanonicalization.Tests.ps1` repeats equivalent candidate builds and compares `BuildIdentity`; `DeterministicComparisonEvidence.Tests.ps1` compares identities across fixture paths and source order. |
| Selected logical source IDs | `SelectedLogicalSourceIds` is sorted and de-duplicated before insertion into the ordered projection. | `DeterministicComparisonEvidence.Tests.ps1` exercises reversed EPG source order while requiring equal `CandidateBuildIdentity`. |
| Input artifact hashes | `InputArtifactHashes` is sorted by logical source, M3U/XMLTV kind, and artifact hash. `Build-Lineup.ps1` supplies local M3U hashes from complete file bytes and configured remote M3U/XMLTV hashes from acquisition status; `Build-Candidate.ps1` hashes its local input bytes directly. | `M3UInputArtifactHashEvidence.Tests.ps1` proves path independence, one-byte sensitivity, local/remote equality, lowercase 64-hex validation, and rejection of empty hashes. |

The packet intentionally records the input fields and domains, not a generated hash literal. The evidence tests compare independently produced values and validate the 64-hex shape without fabricating a value.

## Raw digest dependencies

The raw projections make ordinal dependencies explicit:

| Projection | Digest input implemented | Ordering/consumer relationship |
|---|---|---|
| `RawM3UOccurrenceDigest` | The ordered ten-field projection in `Get-ChannelForgeRawM3UProjection.ps1`: Version, LogicalSourceId, RawTvgIdPresence, RawTvgId, TvgName, DisplayName, GroupTitle, Logo, ChannelNumber, and StreamUrl. | The digest is computed before `SourceLocalOrdinal`; records are sorted by digest and raw tie-break fields, then the ordinal is assigned. `EntryId` subsequently hashes logical source, assigned ordinal, and the raw digest. |
| `RawXMLTVOccurrenceDigest` | `Get-ChannelForgeRawXmltvProjection.ps1::Get-Digest` copies projection properties except `StructuralOccurrenceOrdinal` and digest properties, then hashes with `raw-xmltv-occurrence/v2`. | Channel sort uses raw identity, canonical node/extension bytes, and this digest before assigning `StructuralOccurrenceOrdinal`. |
| `RawProgrammeDigest` | The same ordinal/self-excluding helper hashes the programme projection with `raw-programme/v2`. | Programme sort uses raw identity, times, canonical programme-node/extension bytes, and this digest before assigning `StructuralOccurrenceOrdinal`. |

`CandidateVersionRegistryEvidence.Tests.ps1` checks that emitted raw occurrence digests are lowercase 64-hex values. `DeterministicComparisonEvidence.Tests.ps1` checks the resulting guide evidence, candidate bytes, manifest bytes, and namespace identity across path and source-order permutations.

## Guide projection

`New-ChannelForgeCandidateManifest.ps1` projects XMLTV channel occurrences into `GuideOccurrences`. It groups by logical source, raw-ID presence, and the raw ID; computes a `binding-key/v2` value from logical source, structural ordinal, raw-ID presence, and raw ID; and emits `Version`, `BindingKey`, `RawIdentityPresence`, `RawIdentityValue`, `OccurrenceOrdinal`, `LogicalSourceId`, `CandidateOccurrenceCount`, and `GuideCandidateEvidenceDigest`. The guide evidence digest input is explicitly `Version`, `BindingKey`, `RawIdentityPresence`, `RawIdentityValue`, `OccurrenceOrdinal`, `LogicalSourceId`, and `CandidateOccurrenceCount` (excluding the digest itself); raw XMLTV digest is used upstream for canonical ordering, not silently replaced by a normalized ID.

`M3UXmltvBinding.Tests.ps1` asserts the exact GuideOccurrence property order and that M3U and XMLTV-only binding records are both represented. `DeterministicComparisonEvidence.Tests.ps1` compares every `GuideCandidateEvidenceDigest` and the serialized `GuideOccurrences` projection between equivalent builds.

## BindingKind and Status projection

The candidate manifest's `New-BindingRecord` emits two concrete kinds:

| BindingKind | Construction | Status mapping and count domain |
|---|---|---|
| `M3U` | One record for each non-null raw M3U channel occurrence. | Resolver `Exact` becomes `ExactBound`; resolver `NeedsReview` becomes `ReviewNeeded`; absent binding becomes `Unbound`. `UnboundCount` filters this kind explicitly. |
| `XMLTVOnly` | One record for each XMLTV channel occurrence not matched to an M3U occurrence. | Status is `Unbound` with `MissingM3UId`; `XMLTVOnlyCount` filters this kind explicitly. |

The resolver only marks one-to-one exact raw-ordinal string-equality `tvg-id`/XMLTV `channel id` matches as `Exact` and publishable. Missing IDs, absent matches, duplicate declarations, ambiguous candidates, and M3U identity collisions remain unbound or review-needed. `RejectedXMLTV` is used only as a synthetic count-filter case in `ReviewCountMatrix.Tests.ps1`; the candidate projection does not create such a record.

`M3UXmltvBinding.Tests.ps1` asserts exact, unbound, review-needed, and orphaned results plus the emitted GuideOccurrence/BindingRecord property order. `ReviewCountMatrix.Tests.ps1` proves the disjoint count filters and the fixture matrix (six raw M3U occurrences including a duplicate, five raw XMLTV channels, two exact, two unbound M3U, one review-needed, and three XMLTV-only).

## Review counts

`ReviewCountMatrix.Tests.ps1` proves:

- RawM3UOccurrenceCount = 6, including pre-dedup duplicate;
- RawXMLTVOccurrenceCount = 5, excluding three RawProgrammeOccurrence records;
- ExactBindingCount = 2;
- UnboundCount = 2;
- ReviewNeededCount = 1;
- XMLTVOnlyCount = 3;
- RejectedXMLTV does not affect UnboundCount or XMLTVOnlyCount.

## Shared review-count calculation

`Get-ChannelForgeCandidateReviewCounts.ps1` is the single canonical source-level calculation implementation. `Build-Candidate.ps1` invokes it once and `Build-Lineup.ps1` invokes the same helper once per independent build entry point. Both entry points pass the resulting ordered `ReviewCounts` structure to JSON and Markdown construction; serializers do not inspect raw occurrences, binding records, or review records.

| Inventory item | Count | Evidence |
|---|---:|---|
| Canonical calculation implementations | 1 | `Get-ChannelForgeCandidateReviewCounts.ps1` |
| Build-Candidate callers | 1 | `Build-Candidate.ps1` |
| Build-Lineup callers | 1 | `Build-Lineup.ps1` |
| JSON consumers | 1 per entry-point serializer path | `ReviewCountMatrix.Tests.ps1` |
| Markdown consumers | 1 per entry-point serializer path | `ReviewCountMatrix.Tests.ps1` |
| Serializer recomputation sites | 0 | supplied-sentinel review-count test |

The focused supplied-count test mutates/removes the underlying source collections after calculation and verifies both serializers retain the supplied values.

## Namespace isolation

`CandidateNamespaceEvidence.Tests.ps1` snapshots protected state/public surfaces before and after candidate-only build and asserts equality. Candidate namespace publication is the only intended mutation. Review-only namespaces and malformed/extra-artifact namespaces fail validation.

## Determinism and byte evidence

`DeterministicComparisonEvidence.Tests.ps1` builds equivalent fixtures with different paths and source ordering and compares BuildIdentity, guide evidence digests, candidate artifacts, review artifacts, manifest bytes/hash, and namespace identity. It also checks UTF-8/BOM/newline/property-order constraints for review artifacts.

## Candidate artifact graph

`New-ChannelForgeCandidateManifest.ps1` records generated output bytes as `ArtifactRecords`; each record carries a role, relative path, `Generated` status, byte length, content domain, and domain-separated content hash. The implemented graph is:

| Artifact role | Relative path | Content domain | Presence |
|---|---|---|---|
| `CandidateM3U` | `merged.m3u` | `candidate-m3u/v2` | Present when M3U bytes were generated. |
| `CandidateXMLTV` | `merged.xml` | `candidate-xmltv/v2` | Present when XMLTV bytes were generated. |
| `CandidateReviewJSON` | `lineup-change-review.json` | `candidate-review-json/v2` | Required by namespace validation. |
| `CandidateReviewMarkdown` | `lineup-change-review.md` | `candidate-review-markdown/v2` | Required by namespace validation. |

`manifest.json` is not an `ArtifactRecord`: its `CandidateManifestHash` is separately computed over the ordered manifest with that self field omitted. `Test-ChannelForgeCandidateNamespace` then requires the manifest, the two review artifacts, at least one merged output, an exact allowed file set, and byte length/content-hash agreement for every listed artifact. Publication validates staging, performs the named directory move, and validates the final namespace on the post-move hook path.

`CandidateHookEvidence.Tests.ps1` exercises C01-C15 write/flush/reopen failures, C16/C17 move boundaries and final reopen validation, and invalid/missing/extra artifact rejection. `CandidateNamespaceEvidence.Tests.ps1` proves protected state and public outputs remain byte-identical while a valid candidate namespace is created; it also proves a review-only namespace is rejected. `CandidateCanonicalization.Tests.ps1` proves repeated equivalent builds keep the candidate hash and BuildIdentity equal and that candidate output does not create active merged files.

## Noncanonical and report-only helpers

The implementation has deliberately derived or report-only values adjacent to canonical hash inputs. Evidence for their boundaries is:

| Helper or value | Observed behavior | Boundary |
|---|---|---|
| `Get-SafeCandidateText` | Redacts URLs, paths, and credential-like labels when constructing candidate presentation fields. | It is not used to construct `$buildInput`; those safe fields can still be part of the separately hashed candidate manifest projection. |
| `Get-SafeReportText` / `Get-SafeReportIdentityText` | `Get-SafeReportText` trims and safety-filters; `Get-SafeReportIdentityText` preserves leading/trailing and case characters while applying the safety filter so exact-guide evidence remains visible. | These helpers feed Build-Lineup summary/plan projections, not `BuildIdentityInput`. |
| `ConvertTo-SafeChannelForgeIdentityRecord` and related candidate/evidence helpers | Convert binding results to redacted report records before writing `build-summary.json` and `lineup-plan.md`. | They do not replace the raw binding resolver or candidate manifest binding records. |
| `GeneratedAt` and direct report SHA-256 fields | `Build-Lineup.ps1` writes wall-clock `GeneratedAt`; report M3U/XMLTV SHA-256 values are computed for summary output. | Neither is a member of `$buildInput`; candidate content hashes remain the domain-separated values in `ArtifactRecords`. |

`M3UXmltvBinding.Tests.ps1` proves that whitespace, case, and Unicode-confusable identity variants do not exact-bind and that the resolver does not mutate canonical inputs. `BuildLineupIdentityBinding.Tests.ps1` proves report redaction; `CandidateCanonicalization.Tests.ps1` proves candidate-only output and candidate-manifest URL exclusion.

## Carried evidence limits

In addition to the frozen-contract debt listed below, this packet does not claim a separately persisted `BuildIdentityInput`, generated hash literals, or acceptance/promotion behavior. The repository exposes the resulting `BuildIdentity` and `CandidateManifestHash`, while the input projection is local to manifest construction. Report timestamps, direct report SHA-256 fields, and redacted report projections are evidence context rather than additional identity inputs.

## Carried contract debt

PR #1 does not close:

- DuplicateCount storage ambiguity;
- Journal field-sequence restatement;
- `pointer/v2`, `accepted-state/v2`, `active-m3u/v2`, `active-xmltv/v2`, `previous-m3u/v2`, `previous-xmltv/v2`, `decision-m3u/v2`, `decision-xmltv/v2`, `generation-manifest/v2`, and `previous-output-manifest/v2`.

These are carried frozen-contract debt outside candidate-only PR #1 scope. No compliance claim is made for later acceptance/promotion surfaces.

## Status

The implementation, focused suites, evidence suites, full unit suite, parser, analyzer, and diff checks are green. Exact architecture-packet hash/value capture and final acceptance review remain external review gates.
