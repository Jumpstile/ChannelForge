# ChannelForge blocker #2 contract proposal 4 — semantic schemas

## 1. Schema notation and common rules

This part is the sole definition of the eleven successor projections: the ten
acceptance/promotion surface domains and the aggregate `decision-manifest/v2`
binding projection. Every object has exactly the fields listed below, in the
listed order. `required` means the property MUST be present; `required
nullable` means it MUST be present and may have only the stated `null` value.
A property described as `absent` MUST NOT be serialized. Missing and `null`
are never interchangeable.

`Hash` means a lowercase 64-hex string. `GenerationId` means a lowercase
64-hex string. `EntryId`, `BindingId`, and `DecisionId` mean lowercase
64-hex candidate IDs. `BuildIdentity` and `CandidateManifestHash` are copied
v7 candidate hashes. `Utc` means RFC3339 UTC with a literal `Z`. `UInt` means
a non-negative JSON integer in decimal notation without leading zeroes. Arrays
are present even when empty, contain no duplicates, and are sorted by
ascending ordinal ASCII bytes of their hash/ID strings.

Every object is compact ordered UTF-8 JSON without BOM or trailing newline,
with no unknown or duplicate properties. All hashes use
`H(UTF8(domain) || 0x00 || input-bytes)`, as defined in PART-A. A field that
references a hash does not hash that value again.

`ContentHash` is an artifact-content hash, not a JSON-record hash. It is
`H(active-m3u/v2, exact merged.m3u bytes)` for M3U and
`H(active-xmltv/v2, exact merged.xml bytes)` for XMLTV. `ByteLength` is the
unsigned length of those exact bytes. `M3UDecisionHash`, `XMLTVDecisionHash`,
`DecisionManifestHash`, `OutputManifestHash`, `AcceptedStateHash`,
`GenerationManifestHash`, and `PointerHash` are integrity hashes of canonical
projections; each omits its own property. The two categories MUST NOT be
substituted for one another.

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

**Exact field list:** `Version,GenerationId,BuildIdentity,CandidateManifestHash,DecisionManifestHash,AcceptedOutputManifestHash,PreviousStateHash,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,AcceptedBindingIds,AcceptedXMLTVStatus,AcceptedAtUtc,AcceptedStateHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required `GenerationId`; never null/missing |
| `BuildIdentity` | required `Hash`; copied exact v7 value; never null/missing |
| `CandidateManifestHash` | required `Hash`; copied exact v7 value; never null/missing |
| `DecisionManifestHash` | required `Hash`; equals the aggregate `decision-manifest/v2` `DecisionManifestHash`; never null/missing |
| `AcceptedOutputManifestHash` | required `Hash`; equals `OutputManifestHash` of this generation's output manifest; never null/missing |
| `PreviousStateHash` | required nullable `Hash`; `null` only for the first accepted generation, otherwise the prior generation's `AcceptedStateHash`; never missing |
| `IncludedCandidateEntryIds` | required array of unique `EntryId`; never null/missing |
| `ExcludedCandidateEntryIds` | required array of unique `EntryId`; never null/missing |
| `AcceptedBindingIds` | required array of unique `BindingId`; never null/missing |
| `AcceptedXMLTVStatus` | required enum `Generated` or `NotGenerated`; never null/missing; equals aggregate `XMLTVDecisionStatus` |
| `AcceptedAtUtc` | required `Utc` audit string; never null/missing |
| `AcceptedStateHash` | required `Hash`; never null/missing; self-hash |

The included and excluded arrays are disjoint and their union is exactly the
candidate entry set. `AcceptedBindingIds` is exactly the accepted candidate
binding set selected by the subordinate decision projections. The accepted
state's `DecisionManifestHash` is the aggregate hash; it never carries or
accepts either subordinate hash independently. `AcceptedXMLTVStatus` equals
the aggregate status and output-manifest status. `AcceptedStateHash =
H(accepted-state/v2, canonical bytes with AcceptedStateHash, GenerationId,
and AcceptedAtUtc omitted)`. The output reference is required and included
in the state projection; output is hashed before the accepted state, so this
reference does not create a cycle. The audit timestamp and operational
generation ID are excluded from semantic state identity. `PreviousStateHash`
is the sole state-chain field and is owned here, not by a pointer, output
manifest, generation manifest, or decision projection.

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

`Generated` requires a present `merged.xml`, a recomputed matching content
hash, and a matching non-zero byte length in the active descriptor.
`NotGenerated` requires no `merged.xml` in the generation and the exact
active-descriptor triple `ContentHash=null, ByteLength=0, RelativePath=null`.
The status is copied to accepted state and output manifest; each projection's
XMLTV content-hash field is nullable iff its status is `NotGenerated`.
Only the active descriptor proves file presence, path, and byte length; all
available fields and artifact presence must agree, and no consumer may infer
status from file presence alone.

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

The XMLTV Generated/NotGenerated triple is identical to active XMLTV, but is
evaluated against the prior generation. For `NotGenerated`, the prior
generation has no XMLTV file and the exact values are
`ContentHash=null, ByteLength=0, RelativePath=null`; for `Generated`, the
prior file, hash, and length are all required and checked. The previous
descriptor remains required on every non-first generation, including N→N;
its integrity links (`AcceptedStateHash`, `OutputManifestHash`, and
`PreviousGenerationId`) remain required regardless of status. Only its
content hash, path, and length follow the nullable NotGenerated triple.

Across a generation, let `S` be the XMLTV decision status. The aggregate
`XMLTVDecisionStatus`, accepted-state `AcceptedXMLTVStatus`, output
`ActiveXMLTVStatus`, and active descriptor `Status` must all equal `S`.
`S=Generated` requires `merged.xml`, a non-null content hash, positive exact
length, and `merged.xml` path; `S=NotGenerated` requires no file and null
content hash/path with length zero wherever those fields exist. The output
manifest and generation manifest remain required and retain their required
integrity hashes in either status. The first-generation G and
first-generation N vectors and the later G→G, G→N, N→G, and N→N
transition vectors apply these same rules; only the first generation omits
the previous-output object and previous descriptors.

## 8. `decision-m3u/v2` — DecisionM3UV2 subordinate projection

**Exact field list:** `Version,CandidateManifestHash,BuildIdentity,AcceptedParentGenerationManifestHash,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,DecisionIds,M3UDecisionHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `CandidateManifestHash` | required v7 `Hash`; never null/missing |
| `BuildIdentity` | required v7 `Hash`; never null/missing |
| `AcceptedParentGenerationManifestHash` | required nullable `Hash`; null only on first generation, otherwise prior `GenerationManifestHash`; never missing |
| `IncludedCandidateEntryIds` | required unique sorted `EntryId` array; never null/missing |
| `ExcludedCandidateEntryIds` | required unique sorted `EntryId` array; never null/missing |
| `DecisionIds` | required unique sorted lowercase 64-hex `DecisionId` array; never null/missing |
| `M3UDecisionHash` | required `Hash`; self-hash |

The entry arrays are disjoint and partition the candidate manifest entries.
`M3UDecisionHash = H(decision-m3u/v2, canonical bytes with
M3UDecisionHash omitted)`. This subordinate hash is not authoritative for
acceptance; it is an input to the aggregate decision manifest. The parent
hash is a backward reference and can never name the generation being built.

## 9. `decision-xmltv/v2` — DecisionXMLTVV2 subordinate projection

**Exact field list:** `Version,CandidateManifestHash,BuildIdentity,AcceptedParentGenerationManifestHash,AcceptedXMLTVStatus,IncludedCandidateEntryIds,ExcludedCandidateEntryIds,DecisionIds,XMLTVDecisionHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `CandidateManifestHash` | required v7 `Hash`; never null/missing |
| `BuildIdentity` | required v7 `Hash`; never null/missing |
| `AcceptedParentGenerationManifestHash` | required nullable `Hash`; null only on first generation, otherwise prior `GenerationManifestHash`; never missing |
| `AcceptedXMLTVStatus` | required enum `Generated` or `NotGenerated`; never null/missing |
| `IncludedCandidateEntryIds` | required unique sorted `EntryId` array; never null/missing |
| `ExcludedCandidateEntryIds` | required unique sorted `EntryId` array; never null/missing |
| `DecisionIds` | required unique sorted lowercase 64-hex `DecisionId` array; never null/missing |
| `XMLTVDecisionHash` | required `Hash`; self-hash when this subordinate projection is present |

This subordinate projection is serialized and hashed when
`AcceptedXMLTVStatus=Generated`; when status is `NotGenerated`, the
projection is absent and the aggregate's `XMLTVDecisionHash` is `null`.
When present, `XMLTVDecisionHash = H(decision-xmltv/v2, canonical bytes with
XMLTVDecisionHash omitted)`. The candidate hash, build identity, parent hash,
entry partition, and status must match the aggregate decision manifest and
accepted state. A NotGenerated status never permits a fabricated hash or
empty stand-in object.

## 10. `decision-manifest/v2` — DecisionManifestV2 aggregate

**Exact field list:** `Version,CandidateManifestHash,BuildIdentity,M3UDecisionHash,XMLTVDecisionStatus,XMLTVDecisionHash,DecisionIds,DecisionManifestHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `CandidateManifestHash` | required v7 `Hash`; never null/missing |
| `BuildIdentity` | required v7 `Hash`; never null/missing |
| `M3UDecisionHash` | required `Hash`; equals the subordinate `decision-m3u/v2` `M3UDecisionHash`; never null/missing |
| `XMLTVDecisionStatus` | required enum `Generated` or `NotGenerated`; never null/missing |
| `XMLTVDecisionHash` | required nullable `Hash`; equals the subordinate `decision-xmltv/v2` `XMLTVDecisionHash` iff status is `Generated`, and is exactly `null` iff status is `NotGenerated` |
| `DecisionIds` | required unique sorted lowercase 64-hex `DecisionId` array; never null/missing |
| `DecisionManifestHash` | required lowercase 64-hex `Hash`; self-hash |

The aggregate binds the subordinate M3U projection and, only when XMLTV is
Generated, the subordinate XMLTV projection. Its candidate hash, build
identity, and `DecisionIds` equal the M3U subordinate values; when present,
the XMLTV subordinate has the same candidate/build values and
`DecisionIds`. The two subordinate projections also have the same parent
generation hash and disjoint complete entry partition. The aggregate's
`DecisionIds` are the sorted unique IDs from that shared decision result.
`DecisionManifestHash = H(decision-manifest/v2, canonical bytes with only
DecisionManifestHash omitted)`. The aggregate does not include either
subordinate projection inline, a generation ID, a parent hash, an accepted
state hash, an output hash, a generation hash, a pointer hash, or a journal
hash; all such links remain outside this hash input. Thus the aggregate
cannot participate in a cycle.

## 11. `generation-manifest/v2` — GenerationManifestV2

**Exact field list:** `Version,GenerationId,BuildIdentity,CandidateManifestHash,DecisionManifestHash,AcceptedStateHash,AcceptedOutputManifestHash,ActiveM3UHash,ActiveXMLTVHash,PreviousOutputManifestHash,GenerationManifestHash`.

| Field | Type and null/missing rule |
|---|---|
| `Version` | required acceptance version string; never null/missing |
| `GenerationId` | required `GenerationId`; never null/missing |
| `BuildIdentity` | required v7 `Hash`; never null/missing |
| `CandidateManifestHash` | required v7 `Hash`; never null/missing |
| `DecisionManifestHash` | required `Hash` equal to the current aggregate `decision-manifest/v2` `DecisionManifestHash`; never null/missing |
| `AcceptedStateHash` | required `Hash`; never null/missing |
| `AcceptedOutputManifestHash` | required `Hash` equal to current `OutputManifestHash`; never null/missing |
| `ActiveM3UHash` | required `Hash` equal to active M3U `ContentHash`; never null/missing |
| `ActiveXMLTVHash` | required nullable `Hash`; non-null iff accepted XMLTV is Generated, null iff NotGenerated |
| `PreviousOutputManifestHash` | required nullable `Hash`; null only on first generation, otherwise prior `OutputManifestHash`; never missing |
| `GenerationManifestHash` | required `Hash`; self-hash |

`GenerationManifestHash = H(generation-manifest/v2, canonical bytes with
GenerationManifestHash and GenerationId omitted)`. The generation manifest
binds the aggregate decision manifest, accepted state, accepted output, and
exact active artifact content. It never carries either subordinate decision
hash. `ActiveXMLTVHash` follows the same status/null rules as active XMLTV.
No generation manifest may contain a later generation's hash.

## 12. `previous-output-manifest/v2` — PreviousOutputManifestV2

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

This is the sole output-manifest schema. It is serialized as `accepted-output.manifest.json` in each immutable generation; `PreviousOutputManifestHash` points to the previous generation's `OutputManifestHash`. `OutputManifestHash = H(previous-output-manifest/v2, canonical bytes with OutputManifestHash, GenerationId, and AcceptedStateHash omitted)`. Its active hashes and status must equal the active descriptors and accepted state. `NotGenerated` means no XMLTV artifact and `ActiveXMLTVHash=null`; it is not an absent output-manifest object.

## 13. DuplicateCount disposition

`DuplicateCount` is owned by the v7 occurrence population, not by any of these ten domains. It is never a property of `RawM3UOccurrence`, `RawXMLTVChannelOccurrence`, or `RawProgrammeOccurrence`, and is excluded from their occurrence digests. For a selected representative, it is exactly the unsigned 32-bit count of other raw occurrences that are byte-for-byte/equivalently identical under that occurrence's complete canonical tuple; the representative itself is excluded, so a unique occurrence has count `0`. It is carried only by the v7 review/collision evidence record whose purpose is to report multiplicity. It MUST NOT appear in a decision, accepted state, output descriptor, output manifest, generation manifest, pointer, or previous descriptor, and it cannot alter acceptance identity or output bytes.

## 14. Complete binding check

Validation starts with scope and exact `Version`, then exact property
set/order and primitive/null rules, then candidate/decision/state/output
links, then artifact content hashes. The M3U subordinate projection and,
when XMLTV is Generated, the XMLTV subordinate projection must share
candidate/build/parent values and the same complete disjoint entry
partition. The aggregate must equal those subordinate hashes, status, and
`DecisionIds`; for NotGenerated it must carry `XMLTVDecisionHash=null` and
no XMLTV subordinate object. Accepted state must equal the aggregate
`DecisionManifestHash` and the selected partition; it must not carry
subordinate hashes. Output manifest must equal accepted state and active
content hashes; generation manifest must equal the aggregate decision hash,
state/output hashes, and active hashes; pointer must equal the generation's
three authoritative hashes. Previous descriptors, when present, must all
identify the same prior generation and prior output manifest. Any mismatch,
stale parent, mixed generation, missing required property, or
status/file inconsistency is invalid and fails closed.
