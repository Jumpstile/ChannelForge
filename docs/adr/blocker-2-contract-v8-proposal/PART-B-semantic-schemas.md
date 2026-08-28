# ChannelForge blocker #2 contract proposal 4 — semantic schemas

## 1. Schema notation and common rules

This part is the sole definition of the ten successor domains. Every object has exactly the fields listed below, in the listed order. `required` means the property MUST be present; `required nullable` means it MUST be present and may have only the stated `null` value. A property described as `absent` MUST NOT be serialized. Missing and `null` are never interchangeable.

`Hash` means a lowercase 64-hex string. `GenerationId` means a lowercase 64-hex string. `EntryId`, `BindingId`, and `DecisionId` mean lowercase 64-hex candidate IDs. `BuildIdentity` and `CandidateManifestHash` are copied v7 candidate hashes. `Utc` means RFC3339 UTC with a literal `Z`. `UInt` means a non-negative JSON integer in decimal notation without leading zeroes. Arrays are present even when empty, contain no duplicates, and are sorted by ascending ordinal ASCII bytes of their hash/ID strings.

Every object is compact ordered UTF-8 JSON without BOM or trailing newline, with no unknown or duplicate properties. All hashes use `H(UTF8(domain) || 0x00 || input-bytes)`, as defined in PART-A. A field that references a hash does not hash that value again.

`ContentHash` is an artifact-content hash, not a JSON-record hash. It is `H(active-m3u/v2, exact merged.m3u bytes)` for M3U and `H(active-xmltv/v2, exact merged.xml bytes)` for XMLTV. `ByteLength` is the unsigned length of those exact bytes. `DecisionManifestHash`, `OutputManifestHash`, `AcceptedStateHash`, `GenerationManifestHash`, and `PointerHash` are integrity hashes of canonical projections; each omits its own property. The two categories MUST NOT be substituted for one another.

## 2. `pointer/v2` — PointerV2

**Exact field list:** `Version,GenerationId,GenerationManifestHash,AcceptedStateHash,AcceptedOutputManifestHash,PointerHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required string exactly `blocker-2-contract/v8-acceptance`; never null/missing |
| `GenerationId` | required `GenerationId`; never null/missing |
| `GenerationManifestHash` | required `Hash`; never null/missing; equals the referenced generation manifest integrity hash |
| `AcceptedStateHash` | required `Hash`; never null/missing; equals the referenced accepted-state hash |
| `AcceptedOutputManifestHash` | required `Hash`; never null/missing; equals the referenced output-manifest hash |
| `PointerHash` | required `Hash`; never null/missing; self-hash |

`PointerHash = H(pointer/v2, canonical pointer bytes with PointerHash omitted)`. The pointer hash includes all five remaining fields, including the operational `GenerationId`; it is pointer integrity, not generation or artifact content identity. The pointer is valid only when all three references resolve inside `state/generations/GenerationId/` and the referenced objects agree on that same generation.

## 3. `accepted-state/v2` — AcceptedStateV2

**Exact field list:** `Version,GenerationId,BuildIdentity,CandidateManifestHash,DecisionM3UHash,DecisionXMLTVHash,AcceptedOutputManifestHash,PreviousStateHash,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,AcceptedBindingIds,AcceptedXMLTVStatus,AcceptedAtUtc,AcceptedStateHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required `GenerationId`; never null/missing |
| `BuildIdentity` | required `Hash`; copied exact v7 value; never null/missing |
| `CandidateManifestHash` | required `Hash`; copied exact v7 value; never null/missing |
| `DecisionM3UHash` | required `Hash`; equals the `decision-m3u/v2` `DecisionManifestHash`; never null/missing |
| `DecisionXMLTVHash` | required `Hash`; equals the `decision-xmltv/v2` `DecisionManifestHash`; never null/missing |
| `AcceptedOutputManifestHash` | required `Hash`; equals `OutputManifestHash` of this generation's output manifest; never null/missing |
| `PreviousStateHash` | required nullable `Hash`; `null` only for the first accepted generation, otherwise the prior generation's `AcceptedStateHash`; never missing |
| `IncludedCandidateEntryIds` | required array of unique `EntryId`; never null/missing |
| `ExcludedCandidateEntryIds` | required array of unique `EntryId`; never null/missing |
| `AcceptedBindingIds` | required array of unique `BindingId`; never null/missing |
| `AcceptedXMLTVStatus` | required enum `Generated` or `NotGenerated`; never null/missing |
| `AcceptedAtUtc` | required `Utc` audit string; never null/missing |
| `AcceptedStateHash` | required `Hash`; never null/missing; self-hash |

The included and excluded arrays are disjoint and their union is exactly the candidate entry set. `AcceptedBindingIds` is exactly the accepted candidate binding set selected by the decision projections. `AcceptedXMLTVStatus` equals both decision XMLTV status and output-manifest status. `AcceptedStateHash = H(accepted-state/v2, canonical bytes with AcceptedStateHash, AcceptedOutputManifestHash, GenerationId, and AcceptedAtUtc omitted)`. The output reference is required in the object but excluded only to break the state/output cycle; the audit timestamp and operational generation ID are excluded from semantic state identity. `PreviousStateHash` is the sole state-chain field and is owned here, not by a pointer, output manifest, generation manifest, or journal.

## 4. `active-m3u/v2` — ActiveM3UV2

**Exact field list:** `Version,GenerationId,AcceptedStateHash,OutputManifestHash,ContentHash,ByteLength,RelativePath`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required `GenerationId`; never null/missing |
| `AcceptedStateHash` | required `Hash`; never null/missing |
| `OutputManifestHash` | required `Hash`; never null/missing; equals current output-manifest integrity hash |
| `ContentHash` | required `Hash`; never null/missing; `H(active-m3u/v2, exact merged.m3u bytes)` |
| `ByteLength` | required `UInt`; never null/missing; exact M3U byte length |
| `RelativePath` | required string exactly `merged.m3u`; never null/missing |

The descriptor is metadata for the exact active artifact, not the artifact's content and not a second content hash. Its fields are validated against the containing generation and output manifest. No absolute path, URL, candidate path, or alternate relative path is permitted.

## 5. `active-xmltv/v2` — ActiveXMLTVV2

**Exact field list:** `Version,GenerationId,AcceptedStateHash,OutputManifestHash,Status,ContentHash,ByteLength,RelativePath`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required `GenerationId`; never null/missing |
| `AcceptedStateHash` | required `Hash`; never null/missing |
| `OutputManifestHash` | required `Hash`; never null/missing |
| `Status` | required enum `Generated` or `NotGenerated`; never null/missing |
| `ContentHash` | required nullable `Hash`; non-null iff `Status=Generated`, null iff `Status=NotGenerated` |
| `ByteLength` | required `UInt`; positive and exact iff `Generated`, exactly `0` iff `NotGenerated` |
| `RelativePath` | required nullable string exactly `merged.xml` iff `Generated`, exactly `null` iff `NotGenerated` |

`Generated` requires a present `merged.xml`, a recomputed matching content hash, and a matching non-zero byte length. `NotGenerated` requires no `merged.xml` in the generation and the exact triple `ContentHash=null, ByteLength=0, RelativePath=null`. The status, nullability, file presence, content hash, and length must agree in active XMLTV, accepted state, output manifest, and generation manifest; no consumer may infer status from file presence.

## 6. `previous-m3u/v2` — PreviousM3UV2

**Exact field list:** `Version,GenerationId,AcceptedStateHash,OutputManifestHash,ContentHash,ByteLength,RelativePath,PreviousGenerationId`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required current containing `GenerationId`; never null/missing |
| `AcceptedStateHash` | required prior generation `AcceptedStateHash`; never null/missing |
| `OutputManifestHash` | required prior generation `OutputManifestHash`; never null/missing |
| `ContentHash` | required `Hash` of the exact prior `merged.m3u`; never null/missing |
| `ByteLength` | required `UInt` equal to exact prior artifact length; never null/missing |
| `RelativePath` | required string exactly `merged.m3u`; never null/missing |
| `PreviousGenerationId` | required prior owner `GenerationId`, different from current; never null/missing |

This descriptor is permitted only when `PreviousStateHash` and `PreviousOutputManifestHash` are non-null. It resolves only to `state/generations/PreviousGenerationId/merged.m3u`; it is never a fallback to current output or an unverified path.

## 7. `previous-xmltv/v2` — PreviousXMLTVV2

**Exact field list:** `Version,GenerationId,AcceptedStateHash,OutputManifestHash,Status,ContentHash,ByteLength,RelativePath,PreviousGenerationId`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required current containing `GenerationId`; never null/missing |
| `AcceptedStateHash` | required prior generation `AcceptedStateHash`; never null/missing |
| `OutputManifestHash` | required prior generation `OutputManifestHash`; never null/missing |
| `Status` | required enum `Generated` or `NotGenerated`; never null/missing |
| `ContentHash` | required nullable `Hash`; non-null iff `Generated`, null iff `NotGenerated` |
| `ByteLength` | required `UInt`; exact prior length, or `0` iff `NotGenerated` |
| `RelativePath` | required nullable string `merged.xml` iff `Generated`, null iff `NotGenerated` |
| `PreviousGenerationId` | required prior owner `GenerationId`, different from current; never null/missing |

The XMLTV Generated/NotGenerated triple is identical to active XMLTV, but is evaluated against the prior generation. For `NotGenerated`, the prior generation has no XMLTV file and the exact values are `ContentHash=null, ByteLength=0, RelativePath=null`; for `Generated`, the prior file, hash, and length are all required and checked.

## 8. `decision-m3u/v2` — DecisionM3UV2

**Exact field list:** `Version,CandidateManifestHash,BuildIdentity,AcceptedParentGenerationManifestHash,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,DecisionIds,DecisionManifestHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `CandidateManifestHash` | required v7 `Hash`; never null/missing |
| `BuildIdentity` | required v7 `Hash`; never null/missing |
| `AcceptedParentGenerationManifestHash` | required nullable `Hash`; null only on first generation, otherwise prior `GenerationManifestHash`; never missing |
| `IncludedCandidateEntryIds` | required unique sorted `EntryId` array; never null/missing |
| `ExcludedCandidateEntryIds` | required unique sorted `EntryId` array; never null/missing |
| `DecisionIds` | required unique sorted `DecisionId` array; never null/missing |
| `DecisionManifestHash` | required `Hash`; self-hash |

The entry arrays are disjoint and partition the candidate manifest entries. `DecisionManifestHash = H(decision-m3u/v2, canonical bytes with DecisionManifestHash omitted)`. The parent hash is a backward reference and can never name the generation being built.

## 9. `decision-xmltv/v2` — DecisionXMLTVV2

**Exact field list:** `Version,CandidateManifestHash,BuildIdentity,AcceptedParentGenerationManifestHash,AcceptedXMLTVStatus,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,DecisionIds,DecisionManifestHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `CandidateManifestHash` | required v7 `Hash`; never null/missing |
| `BuildIdentity` | required v7 `Hash`; never null/missing |
| `AcceptedParentGenerationManifestHash` | required nullable `Hash`; null only on first generation, otherwise prior `GenerationManifestHash`; never missing |
| `AcceptedXMLTVStatus` | required enum `Generated` or `NotGenerated`; never null/missing |
| `IncludedCandidateEntryIds` | required unique sorted `EntryId` array; never null/missing |
| `ExcludedCandidateEntryIds` | required unique sorted `EntryId` array; never null/missing |
| `DecisionIds` | required unique sorted `DecisionId` array; never null/missing |
| `DecisionManifestHash` | required `Hash`; self-hash |

`DecisionManifestHash = H(decision-xmltv/v2, canonical bytes with DecisionManifestHash omitted)`. The candidate hash, build identity, parent hash, entry partition, and status must match the corresponding current acceptance decision and accepted state. XMLTV status does not permit an omitted array or omitted decision hash.

## 10. `generation-manifest/v2` — GenerationManifestV2

**Exact field list:** `Version,GenerationId,BuildIdentity,CandidateManifestHash,DecisionM3UHash,DecisionXMLTVHash,AcceptedStateHash,AcceptedOutputManifestHash,ActiveM3UHash,ActiveXMLTVHash,PreviousOutputManifestHash,GenerationManifestHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required `GenerationId`; never null/missing |
| `BuildIdentity` | required v7 `Hash`; never null/missing |
| `CandidateManifestHash` | required v7 `Hash`; never null/missing |
| `DecisionM3UHash` | required `Hash` equal to current decision-m3u `DecisionManifestHash`; never null/missing |
| `DecisionXMLTVHash` | required `Hash` equal to current decision-xmltv `DecisionManifestHash`; never null/missing |
| `AcceptedStateHash` | required `Hash`; never null/missing |
| `AcceptedOutputManifestHash` | required `Hash` equal to current `OutputManifestHash`; never null/missing |
| `ActiveM3UHash` | required `Hash` equal to active M3U `ContentHash`; never null/missing |
| `ActiveXMLTVHash` | required nullable `Hash`; non-null iff accepted XMLTV is Generated, null iff NotGenerated |
| `PreviousOutputManifestHash` | required nullable `Hash`; null only on first generation, otherwise prior `OutputManifestHash`; never missing |
| `GenerationManifestHash` | required `Hash`; self-hash |

`GenerationManifestHash = H(generation-manifest/v2, canonical bytes with GenerationManifestHash and GenerationId omitted)`. The generation manifest binds both decisions, accepted state, accepted output, and exact active artifact content. `ActiveXMLTVHash` follows the same status/null rules as active XMLTV. No generation manifest may contain a later generation's hash.

## 11. `previous-output-manifest/v2` — PreviousOutputManifestV2

**Exact field list:** `Version,GenerationId,ActiveM3UHash,ActiveXMLTVStatus,ActiveXMLTVHash,AcceptedStateHash,OutputManifestHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required current manifest owner `GenerationId`; never null/missing |
| `ActiveM3UHash` | required `Hash` of that generation's active M3U bytes; never null/missing |
| `ActiveXMLTVStatus` | required enum `Generated` or `NotGenerated`; never null/missing |
| `ActiveXMLTVHash` | required nullable `Hash`; non-null iff `ActiveXMLTVStatus=Generated`, null iff `NotGenerated` |
| `AcceptedStateHash` | required `Hash` of that generation's accepted state; never null/missing |
| `OutputManifestHash` | required `Hash`; self-hash |

This is the sole output-manifest schema. It is serialized as `accepted-output.manifest.json` in each immutable generation; `PreviousOutputManifestHash` points to the previous generation's `OutputManifestHash`. `OutputManifestHash = H(previous-output-manifest/v2, canonical bytes with OutputManifestHash and GenerationId omitted)`. Its active hashes and status must equal the active descriptors and accepted state. `NotGenerated` means no XMLTV artifact and `ActiveXMLTVHash=null`; it is not an absent output-manifest object.

## 12. DuplicateCount disposition

`DuplicateCount` is owned by the v7 occurrence population, not by any of these ten domains. It is never a property of `RawM3UOccurrence`, `RawXMLTVChannelOccurrence`, or `RawProgrammeOccurrence`, and is excluded from their occurrence digests. For a selected representative, it is exactly the unsigned 32-bit count of other raw occurrences that are byte-for-byte/equivalently identical under that occurrence's complete canonical tuple; the representative itself is excluded, so a unique occurrence has count `0`. It is carried only by the v7 review/collision evidence record whose purpose is to report multiplicity. It MUST NOT appear in a decision, accepted state, output descriptor, output manifest, generation manifest, pointer, or previous descriptor, and it cannot alter acceptance identity or output bytes.

## 13. Complete binding check

Validation starts with scope and exact `Version`, then exact property set/order and primitive/null rules, then candidate/decision/state/output links, then artifact content hashes. The two decision projections must share candidate/build/parent values and the same complete disjoint entry partition. Accepted state must equal that partition and both decision hashes; output manifest must equal accepted state and active content hashes; generation manifest must equal both decision hashes, state/output hashes, and active hashes; pointer must equal the generation's three authoritative hashes. Previous descriptors, when present, must all identify the same prior generation and prior output manifest. Any mismatch, stale parent, mixed generation, missing required property, or status/file inconsistency is invalid and fails closed.
