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

`New-ChannelForgeCandidateManifest.ps1` constructs the ordered `$buildInput`
projection and hashes its canonical UTF-8 bytes with `candidate-manifest/v2`.
When the opt-in `CHANNELFORGE_BUILD_IDENTITY_INPUT_OUTPUT` environment
variable names a file, the same hash boundary writes a lossless evidence
record containing the canonical bytes as Base64, their length, a direct
SHA-256, the domain, `BuildIdentity`, the ordered fields, and the sorted input
artifact hashes. The variable is unset by default, so this capture does not
change production output or hash semantics.

| BuildIdentityInput member | Repository evidence | Focused evidence |
|---|---|---|
| Contract and identity-rule versions | `$buildInput` sets `ContractVersion = blocker-2-contract/v7` and `IdentityRulesVersion = lineup-history-v1`. | `CandidateVersionRegistryEvidence.Tests.ps1` asserts the frozen-v7 version on emitted projections. |
| Parser, serializer, and guide-binding versions | `$buildInput` includes the M3U/XMLTV parser and serializer contract versions and `GuideBindingContractVersion = guide-binding-exact-ordinal-v1`. | `CandidateCanonicalization.Tests.ps1` repeats equivalent candidate builds and compares `BuildIdentity`; `DeterministicComparisonEvidence.Tests.ps1` compares identities across fixture paths and source order. |
| Selected logical source IDs | `SelectedLogicalSourceIds` is sorted and de-duplicated before insertion into the ordered projection. | `DeterministicComparisonEvidence.Tests.ps1` exercises reversed EPG source order while requiring equal `CandidateBuildIdentity`. |
| Input artifact hashes | `InputArtifactHashes` is sorted by logical source, M3U/XMLTV kind, and artifact hash. `Build-Lineup.ps1` supplies local M3U hashes from complete file bytes and configured remote M3U/XMLTV hashes from acquisition status; `Build-Candidate.ps1` hashes its local input bytes directly. | `M3UInputArtifactHashEvidence.Tests.ps1` proves path independence, one-byte sensitivity, local/remote equality, lowercase 64-hex validation, and rejection of empty hashes. |

The explicit-LF deterministic capture records these exact ordered fields:

* `ContractVersion`: `blocker-2-contract/v7`
* `IdentityRulesVersion`: `lineup-history-v1`
* `M3UParserContractVersion`: `m3u-parser-v1`
* `XMLTVParserContractVersion`: `xmltv-parser-v1`
* `M3USerializerVersion`: `m3u-serializer-v1`
* `XMLTVSerializerVersion`: `xmltv-serializer-v1`
* `GuideBindingContractVersion`: `guide-binding-exact-ordinal-v1`
* `SelectedLogicalSourceIds`: `35a5ee3273a2cc9472f8c7e6536e3cd45b5c4be1203fa611090cc2459f234b5c`, `3bc3868c0cc52e573d68f5411d81527e63093df9efb48a8f95ad545b2153501c`, `893631a6dc90363e260b73c1ab72faa5b92866c758d5d16fe0379b186a8ac7c8`
* `InputArtifactHashes`: XMLTV/`35a5ee3273a2cc9472f8c7e6536e3cd45b5c4be1203fa611090cc2459f234b5c` → `492bb3208b87e7e1dee61f705d48a6b017c82fe4a811fd95a062fdee708844f7`; XMLTV/`3bc3868c0cc52e573d68f5411d81527e63093df9efb48a8f95ad545b2153501c` → `878f964fd71a5a309ec19821e3efe84b011a216b7ae700103e172fbd2376fc80`; M3U/`893631a6dc90363e260b73c1ab72faa5b92866c758d5d16fe0379b186a8ac7c8` → `9d537b6f00459798b141c1153dde167a274f097bce8fafdf49fbf89d887cbbb0`

The complete Base64 canonical UTF-8 values are retained in the focused test
capture at `output/deterministic-comparison-evidence.json`, under
`BuildA.BuildIdentityInput.CanonicalUtf8Base64` and
`BuildB.BuildIdentityInput.CanonicalUtf8Base64`; Build A and Build B are byte
identical. The test independently recomputes both direct SHA-256 and the
domain-separated `candidate-manifest/v2` identity from the decoded bytes.

## Cross-machine BuildIdentity disposition

The earlier Desktop/Arcade mismatch was an evidence-fixture portability defect. `DeterministicComparisonEvidence.Tests.ps1` originally wrote here-string contents directly, so parser-input bytes inherited checkout EOLs. LF and CRLF are distinct raw inputs under v7 and therefore correctly produce distinct input hashes and identities. Production does not normalize these bytes.

The corrected fixture explicitly joins logical lines with LF and appends one LF. The corrected explicit-LF run produced:

| BuildIdentityInput item | Value |
|---|---|
| Canonical byte length | 1157 |
| Direct SHA-256 | `d2a13faa2c9b86e752de6aa434e1e0450416c6bf9d7e93f686f6f55de9924530` |
| Domain | `candidate-manifest/v2` |
| BuildIdentity | `089d4e1b212515715546cbe2409fb59742d0fe61bbeec74d4b05ebaa7fc01dcd` |
| M3U fixture bytes | 216 bytes; `960717803a0119ab2d2674e026cfaf7f3071405b78bf7004302a8954b840f306` |
| Alpha XMLTV fixture bytes | 297 bytes; `b7ab0c30543f1870d6dc134591ba8510f110c064155bdef3da842bb5680d8c3a` |
| Zeta XMLTV fixture bytes | 293 bytes; `3f34ec55e9a87a71c43e2c4841b2765b30ac8d470648da4f5ad49b288dc923c1` |

The prior packet's `1157`/`876c269a709158f91155b0f905635d465b4c8dddf335c96c9fa9736d88935a83` pair is retired. The canonical length remains 1157 in the corrected explicit-LF capture, while the lossless canonical bytes produce the direct SHA-256 above. The corresponding Arcade value `2a5de7d4daa1cf699aa740d67943bb01457f58a2144ca77366cd479b9191233a` and Desktop value `a005d336f5a3fa7ffedcadf695c5ad6bdbfa66231ba89e3d50c52bb4435f49b4` are retired as historical outputs of non-equivalent CRLF/LF fixture bytes. The corrected fixture establishes: cross-machine production determinism defect = NO; filesystem-path dependence = NO; machine-state dependence = NO; exact-byte sensitivity = YES.

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

## Parser identity disposition

`ParserIdentityDisposition.Tests.ps1` is the focused permanent parser evidence for the three distinct M3U and XMLTV representations. It writes each representation as a standalone input, invokes the public local-file importer, records the outcome and termination layer, and does not invoke binding or candidate projection for rejected XMLTV input.

| Input representation | Parser result | Grounded disposition |
|---|---|---|
| M3U with no `tvg-id` attribute | Returned from M3U parser | `RawTvgIdPresence = Missing`, `RawTvgId = null`, runtime `TvgId = ''`. |
| M3U `tvg-id=""` | Returned from M3U parser | `RawTvgIdPresence = Present`, `RawTvgId = ''`, runtime `TvgId = ''`. |
| M3U `tvg-id="   "` | Returned from M3U parser | `RawTvgIdPresence = Present`, `RawTvgId` and runtime `TvgId` preserve three spaces. |
| XMLTV channel with no `id` attribute | Rejected by `Read-ChannelForgeXmltvDocument` | Error: `XMLTV channel elements require a non-empty id attribute.` No downstream `BindingKind` or `Status` claim is made. |
| XMLTV channel `id=""` | Rejected by `Read-ChannelForgeXmltvDocument` | Same parser error and boundary; no downstream `BindingKind` or `Status` claim is made. |
| XMLTV channel `id="   "` | Rejected by `Read-ChannelForgeXmltvDocument` | Same parser error and boundary; no downstream `BindingKind` or `Status` claim is made. |

The XMLTV termination layer is extracted from the caught error's actual `ScriptStackTrace` frame (`Read-ChannelForgeXmltvDocument`), rather than inferred from a later resolver result. The test therefore makes no `Unbound`, `ReviewNeeded`, `XMLTVOnly`, or other downstream disposition claim for invalid XMLTV IDs.

Related executable identity evidence remains in the existing focused tests: `M3UXmltvBinding.Tests.ps1` covers case mismatch (and leading/trailing whitespace plus confusable variants), duplicate XMLTV declarations, XMLTV-only `orphan.us`, and reversed-input permutation; `BuildLineupIdentityBinding.Tests.ps1` covers the normalized M3U collision (`zeta.us` and ` ZETA.US `) and its review-needed result; `ReviewCountMatrix.Tests.ps1` covers the disjoint `XMLTVOnly` and `ReviewNeeded` count domains and the synthetic `RejectedXMLTV` exclusion. Those tests provide one review-needed record per exercised duplicate/collision case; no same-run multiple-review-needed fixture is claimed here.

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

## ReviewRecord population boundary

The frozen v7 schema requires `ReviewRecords` structurally in both
`CandidateManifest` and candidate review JSON, and defines the
`ReviewRecord` property order and its candidate/accepted-ID constraints. This
packet confirms only that the field is emitted (as an empty array); it does
not claim that binding or guide evidence has been transformed into populated
canonical review records.

The frozen schema does not define a `ReviewRecordDigest` hash domain or
derivation, an Evidence item property order, or a complete Evidence value
schema. PR #1 is candidate-only and excludes accepted-state comparison and
acceptance. Consequently, this repository cannot infer a canonical
candidate-stage mapping from the available binding evidence without inventing
normative contract details. ReviewRecord population remains unresolved and
out of scope pending an authoritative contract clarification; no production
mapping or acceptance/promotion behavior is changed by PR #1.

## Namespace isolation

`CandidateNamespaceEvidence.Tests.ps1` snapshots protected state/public surfaces before and after candidate-only build and asserts equality. Candidate namespace publication is the only intended mutation. Review-only namespaces and malformed/extra-artifact namespaces fail validation.

## Determinism and byte evidence

`DeterministicComparisonEvidence.Tests.ps1` builds Build A and Build B from the same logical fixture with different playlist/guide paths and reversed EPG source order. The following values are the actual generated values captured by that test run (not placeholders). Artifact `ContentHash` values are domain-separated hashes from manifest `ArtifactRecords`; `Manifest SHA-256` is the direct SHA-256 of the emitted `manifest.json` bytes; `CandidateManifestHash` is the `candidate-manifest/v2` value and the namespace directory identity.

| Generated value | Build A | Build B | Comparison |
|---|---|---|---|
| `BuildIdentity` | `089d4e1b212515715546cbe2409fb59742d0fe61bbeec74d4b05ebaa7fc01dcd` | `089d4e1b212515715546cbe2409fb59742d0fe61bbeec74d4b05ebaa7fc01dcd` | Equal |
| `GuideCandidateEvidenceDigest` (ordinal 0) | `5c455a97c5053bfc4f2cab5e5c92cbde7327a39beadd20a6cb0be35cc815ede8` | `5c455a97c5053bfc4f2cab5e5c92cbde7327a39beadd20a6cb0be35cc815ede8` | Equal |
| `GuideCandidateEvidenceDigest` (ordinal 1) | `0d51455a7d03a3133757bc6643e4366977dd0d5727df6073cdfaac059fa402ec` | `0d51455a7d03a3133757bc6643e4366977dd0d5727df6073cdfaac059fa402ec` | Equal |
| `CandidateM3U` (`merged.m3u`) | 242 bytes; `d135af5f631311bea44709224eec8c4815d5979de8165cdda8226de022cc55f3` | 242 bytes; `d135af5f631311bea44709224eec8c4815d5979de8165cdda8226de022cc55f3` | Equal |
| `CandidateXMLTV` (`merged.xml`) | 1036 bytes; `3893d34656f01aea810178539bbc27735aa3110c436e2000a0fec7e94bf71c6e` | 1036 bytes; `3893d34656f01aea810178539bbc27735aa3110c436e2000a0fec7e94bf71c6e` | Equal |
| `CandidateReviewJSON` (`lineup-change-review.json`) | 298 bytes; `b939e21bf54c2fe689bb115db795b98faee47669c60ec0622af1b27cb05d694e` | 298 bytes; `b939e21bf54c2fe689bb115db795b98faee47669c60ec0622af1b27cb05d694e` | Equal; domain `candidate-review-json/v2` |
| `CandidateReviewMarkdown` (`lineup-change-review.md`) | 303 bytes; `665fee8571e9ddb2b282f54b9d279681637fcdb3d5419cea716f8dc2a7665a3c` | 303 bytes; `665fee8571e9ddb2b282f54b9d279681637fcdb3d5419cea716f8dc2a7665a3c` | Equal; domain `candidate-review-markdown/v2` |
| `manifest.json` bytes | 6850 bytes | 6850 bytes | Equal |
| `manifest.json` direct SHA-256 | `79b993e75b89ff4f590a90d1a0c29b20b072f3cab7d12f9d5f28c03cc96f6731` | `79b993e75b89ff4f590a90d1a0c29b20b072f3cab7d12f9d5f28c03cc96f6731` | Equal |
| `CandidateManifestHash` / namespace | `bbf45601c4c7e888bd9f4c571dac176957bcf4b9b4d2a13c659ed6b065144b9e` | `bbf45601c4c7e888bd9f4c571dac176957bcf4b9b4d2a13c659ed6b065144b9e` | Equal |

The review encoding capture is exact for both builds: JSON is 298 UTF-8 bytes, has no BOM, has no CR, has no LF, and preserves property order `Version, BuildIdentity, ReviewRecords, M3UIdentityCollisions, RawM3UOccurrenceCount, RawXMLTVOccurrenceCount, ExactBindingCount, UnboundCount, ReviewNeededCount, XMLTVOnlyCount`; Markdown is 303 UTF-8 bytes, has no BOM or CR, ends with LF, and does not end with CRLF. The test also compares the complete review JSON/Markdown bytes, not only parsed values.

## Fifteen-row adversarial identity matrix

The repository has direct assertions for the following fifteen rows. Inputs are shown exactly where the test supplies them; no trim, case-fold, or Unicode-normalized value is inferred.

| Row | Adversarial input | Grounded expected result | Evidence |
|---:|---|---|---|
| 1 | M3U `guide.us`; XMLTV `guide.us ` (XMLTV trailing whitespace) | No exact binding; one M3U channel remains unbound | `M3UXmltvBinding.Tests.ps1` |
| 2 | M3U `guide.us`; XMLTV ` guide.us` (XMLTV leading whitespace) | No exact binding; one M3U channel remains unbound | `M3UXmltvBinding.Tests.ps1` |
| 3 | M3U `guide.us ` (M3U trailing whitespace); XMLTV `guide.us` | No exact binding; one M3U channel remains unbound | `M3UXmltvBinding.Tests.ps1` |
| 4 | M3U ` guide.us` (M3U leading whitespace); XMLTV `guide.us` | No exact binding; one M3U channel remains unbound | `M3UXmltvBinding.Tests.ps1` |
| 5 | M3U `GUIDE.US`; XMLTV `guide.us` (case mismatch) | No exact binding; one M3U channel remains unbound | `M3UXmltvBinding.Tests.ps1` |
| 6 | M3U `guid` + Cyrillic `е` + `.us`; XMLTV `guide.us` (Unicode confusable) | No exact binding; one M3U channel remains unbound | `M3UXmltvBinding.Tests.ps1` |
| 7 | M3U `guide.us `; XMLTV `guide.us ` (same whitespace-preserving raw value) | One exact binding; the raw M3U/XMLTV values remain `guide.us ` | `M3UXmltvBinding.Tests.ps1` |
| 8 | Fixture M3U record with missing `tvg-id` | `Unbound`, reason `MissingTvgId`, not publishable, empty `TvgId` | `M3UXmltvBinding.Tests.ps1` |
| 9 | Fixture M3U `missing.us` with no XMLTV channel | `Unbound`, reason `TvgIdNotFoundInXmltv`; it is not exact-bound | `M3UXmltvBinding.Tests.ps1` |
| 10 | Two XMLTV declarations for `ambiguous.us` | One review-needed record, reason `DuplicateXmltvChannelIdDeclaration`, declaration count 2, not publishable | `M3UXmltvBinding.Tests.ps1` |
| 11 | XMLTV-only `orphan.us` | `OrphanedXmltv`, reason `NoM3UChannelWithTvgId`, candidate channel count 4 | `M3UXmltvBinding.Tests.ps1` |
| 12 | Fixture exact pair `alpha.us` | Exact, publishable binding; raw IDs equal | `M3UXmltvBinding.Tests.ps1` |
| 13 | Fixture exact pair `zeta.us` | Exact, publishable binding; raw IDs equal | `M3UXmltvBinding.Tests.ps1` |
| 14 | Reverse the complete channel and programme input arrays | Serialized binding-order summary is identical after canonical ordering | `M3UXmltvBinding.Tests.ps1` |
| 15 | Invoke resolver and compare canonical channels/programmes before and after | Canonical inputs are unchanged; no resolver mutation | `M3UXmltvBinding.Tests.ps1` |

These rows cover the currently grounded adversarial identity cases. No additional unsupported row is silently represented as a pass; the matrix is limited to the fifteen cases directly asserted by the named test.

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

The implementation now offers a separately persisted `BuildIdentityInput` evidence record only when `CHANNELFORGE_BUILD_IDENTITY_INPUT_OUTPUT` is explicitly set; default production remains unchanged. The capture is evidence-only and does not alter acceptance or promotion behavior. The generated hashes and byte lengths recorded above are evidence from the named deterministic fixture run. Report timestamps, direct report SHA-256 fields, and redacted report projections remain evidence context rather than additional identity inputs.

## Carried contract debt

PR #1 does not close:

- DuplicateCount storage ambiguity;
- Journal field-sequence restatement;
- `pointer/v2`, `accepted-state/v2`, `active-m3u/v2`, `active-xmltv/v2`, `previous-m3u/v2`, `previous-xmltv/v2`, `decision-m3u/v2`, `decision-xmltv/v2`, `generation-manifest/v2`, and `previous-output-manifest/v2`.

These are carried frozen-contract debt outside candidate-only PR #1 scope. No compliance claim is made for later acceptance/promotion surfaces.

## Status

The implementation, focused suites, evidence suites, full unit suite, parser, analyzer, and diff checks are green. Deterministic architecture-packet hash/value capture is now recorded above; final acceptance review remains an external review gate.
