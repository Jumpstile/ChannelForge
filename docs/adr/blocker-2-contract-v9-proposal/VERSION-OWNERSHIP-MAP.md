# v9 Candidate Version Ownership Map

This map follows the frozen registry in `docs/adr/blocker-2-contract/PART-A-canonical-foundation.md`. `ContractVersion` is the candidate semantic version: `blocker-2-contract/v7` for the frozen default and `blocker-2-contract/v8` for the frozen v9 successor revision.

## Registry scope

| Surface | Owner | Frozen v7 value | Successor value | #109 implementation status |
|---|---|---|---|---|
| SafeTvgNameInput | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| RawM3UOccurrence | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| EntryId input | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| M3UIdentityCollisions | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| RawXMLTVChannelOccurrence | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| RawProgrammeOccurrence | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| GuideCandidateOccurrence | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| Candidate review JSON | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| BindingRecord | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| CandidateManifest | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| StructuralEvidenceInput | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| CollisionIdentity | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| CollisionEvidenceInput | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| BuildIdentity.ContractVersion | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| CandidateManifest.ContractVersion | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #110 |
| M3UParserContractVersion | Independent parser subsystem | `m3u-parser-v1` | `m3u-parser-v1` | UNCHANGED; NOT A #109 MIGRATION |
| XMLTVParserContractVersion | Independent parser subsystem | `xmltv-parser-v1` | `xmltv-parser-v1` | UNCHANGED; NOT A #109 MIGRATION |
| M3USerializerVersion | Independent serializer subsystem | `m3u-serializer-v1` | `m3u-serializer-v1` | UNCHANGED; NOT A #109 MIGRATION |
| XMLTVSerializerVersion | Independent serializer subsystem | `xmltv-serializer-v1` | `xmltv-serializer-v1` | UNCHANGED; NOT A #109 MIGRATION |
| GuideBindingContractVersion | Independent guide-binding subsystem | `guide-binding-exact-ordinal-v1` | `guide-binding-exact-ordinal-v1` | UNCHANGED; NOT A #109 MIGRATION |
| Journal.Version | Explicit integer exception | `2` | `2` | DEFERRED TO RUNTIME ISSUE |
| DecisionManifest | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO LATER DECISION/RUNTIME ISSUE |
| AcceptedState | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO #102 |
| AcceptedOutputManifest | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO LATER ACCEPTANCE ISSUE |
| GenerationManifest | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO LATER GENERATION ISSUE |
| accepted pointer | CandidateContractVersion | `blocker-2-contract/v7` | `blocker-2-contract/v8` | DEFERRED TO LATER PUBLICATION ISSUE |

The sole Issue #109 implementation surface is the EntryOutputSlice /
EntryContentHash erratum. It does not implement any registry-wide
CandidateContractVersion successor migration; those surfaces remain deferred
to their named owners and issues above.

The deferred surfaces are normatively version-owned but outside Issue #109.
Their acceptance identifier remains `blocker-2-contract/v8-acceptance`; it is
not replaced by the candidate version.
## Frozen implementation divergence

The frozen v7 implementation historically uses `entry-id-v2`,
`stream-fingerprint-v2`, and `safe-tvg-name-fingerprint-v2` as projection
input literals in places where the frozen registry names the field
CandidateContractVersion-owned. Those historical bytes are frozen and are not
rewritten by Issue #109. The successor mapping is explicit: candidate-owned
`Version` fields emit `blocker-2-contract/v8`; the independent hash domains
remain unchanged. This is a compatibility-preserving successor mapping, not a
claim that the historical v7 implementation fully reflects the registry text.

`entry-id/v2`, `stream-fingerprint/v2`, and
`safe-tvg-name-fingerprint/v2` are the independent semantic hash domains.
The historical literals `entry-id-v2`, `stream-fingerprint-v2`, and
`safe-tvg-name-fingerprint-v2` are frozen implementation Version-field values,
not independent domains.


For EntryId, the projection's `Version` is candidate-owned; the `entry-id/v2` domain is an independent algorithm identifier. Therefore successor EntryId hashes change because the canonical EntryId input Version changes, while the domain identifier remains `entry-id/v2`.

StreamFingerprint and PresentationFingerprint use candidate-owned projection Version fields and unchanged independent algorithm domains. Their successor identities therefore change when their canonical Version-bearing inputs change.

## Expected identity consequences

Changing a candidate-owned Version in a hashed canonical projection is expected to change that projection's digest and all downstream identities that include it: SafeTvgName-derived identity, raw M3U/XMLTV/programme digests, EntryId, collision evidence, guide evidence, BindingId, structural/collision evidence, review/change identities, CandidateManifestHash, and BuildIdentity. Media bytes (`merged.m3u`, `merged.xml`) do not include these Version fields and are expected to remain preserved. Review Markdown changes only through changed deterministic inputs such as BuildIdentity.

The default v7 mapping is retained byte-for-byte. The successor mapping is uniform across every in-scope candidate-construction surface. No accepted-state, pointer, journal, promotion, recovery, or publication implementation is changed by Issue #109.
