# ChannelForge blocker #2 contract proposal 4 — canonical foundation

## 1. Scope and version ownership

This proposal is design/review evidence only. It authorizes no acceptance, promotion, recovery, pointer publication, generation publication, or active-output implementation. The frozen authority remains `blocker-2-contract/v7` until this proposal is frozen.

The version registry has two deliberately disjoint scopes:

* `CandidateContractVersion` is the literal `blocker-2-contract/v7`. Every retained candidate projection, candidate artifact, `BuildIdentity`, and candidate `Version` field remains owned by v7. This proposal does not restate or amend those projections.
* `AcceptanceContractVersion` is the literal `blocker-2-contract/v8-acceptance`. It is owned by this proposal and is used only by the ten successor domains listed in section 3. A field named `Version` in one of those ten objects is exactly this value. It is not the proposed revision label (`blocker-2-contract/v8`) and is not a hash-domain name.

`GenerationId` is an operational identifier, not a version: exactly 64 lowercase hexadecimal characters (32 random bytes), generated before staging. `BuildIdentity` and `CandidateManifestHash` are v7 candidate values and are copied, never re-versioned or re-hashed by an acceptance domain. Hash-domain suffixes are semantic domain names, not registry version values.

## 2. Revision identity

`RevisionContentId` retains the frozen five-file procedure: create the ascending file-name manifest of the exact bytes of the five normative proposal files, then compute `H(contract-revision-content/v1, manifest)`. `FREEZE-RECORD` is governance metadata and is not part of that manifest. This proposal is not frozen and therefore has no minted `ContractRevisionId`.

## 3. Exhaustive successor domain inventory

The acceptance/promotion amendment closes the ten original acceptance,
output, decision, and previous-output domains plus one aggregate decision
binding projection. The original ten remain the required surface-domain
inventory; `decision-manifest/v2` is the single cross-surface object that
binds the subordinate M3U and XMLTV decision projections:

1. `pointer/v2`
2. `accepted-state/v2`
3. `active-m3u/v2`
4. `active-xmltv/v2`
5. `previous-m3u/v2`
6. `previous-xmltv/v2`
7. `decision-m3u/v2` (subordinate)
8. `decision-xmltv/v2` (subordinate)
9. `generation-manifest/v2`
10. `previous-output-manifest/v2`
11. `decision-manifest/v2` (aggregate binding)

PART-B is the sole owner of all eleven ordered projections. The aggregate
decision manifest is not a second decision authority: its
`DecisionManifestHash` is the one authoritative decision hash consumed by
accepted state and generation. `journal/v2` and all transaction/recovery
symbols remain solely owned by PART-C; this proposal intentionally does not
restate their field sequence. The duplicated-Journal-definition debt is
therefore explicitly resolved by single ownership: PART-C is normative, while
PART-A and PART-B may only reference it.

## 4. Canonical bytes and primitive rules

Every projection is an object with exactly the properties listed in PART-B, in that order. Unknown properties, duplicate JSON properties, omitted required properties, wrong types, and duplicate array members are invalid. A required property is still required when its value is `null`; missing and `null` are never interchangeable.

Canonical bytes are compact JSON encoded as UTF-8 without BOM and without a trailing newline. Objects use the declared order. Arrays use the declared sort order. Strings are compared as Unicode scalar sequences before JSON escaping. Only the JSON short escapes for quote, reverse solidus, backspace, form feed, line feed, carriage return, and tab are used; other code points use lowercase `\u` escapes (astral scalars use their two lowercase surrogate escapes). No locale, parser order, filesystem order, timestamp, randomness, or serializer default participates.

Unsigned integers are decimal JSON numbers with no leading zero except zero. Negative, fractional, exponent-form, and numeric-string values are invalid. Hashes are exactly 64 lowercase hexadecimal characters. IDs use the exact grammar stated by PART-B; an empty ID, hash, path, or domain string is invalid. Enum strings are case-sensitive.

## 5. Hash and content rules

For an exact ASCII domain `D` and bytes `B`, `H(D,B)` is lowercase SHA-256 over `UTF8(D) || 0x00 || B`. A domain is used only as specified below and in PART-B; no object may substitute another domain.

A **content hash** (`ContentHash`, and the corresponding
`ActiveM3UHash`/`ActiveXMLTVHash`) is `H(active-m3u/v2, exact merged.m3u
bytes)` or `H(active-xmltv/v2, exact merged.xml bytes)`. It is an identity
of artifact content, and its `ByteLength` is the exact byte count of those
same bytes. It is never a hash of JSON metadata.

An **integrity/projection hash** (`M3UDecisionHash`,
`XMLTVDecisionHash`, `DecisionManifestHash`, `OutputManifestHash`,
`AcceptedStateHash`, `GenerationManifestHash`, or `PointerHash`) is
`H(the object's named domain, canonical bytes of that object's hash input
projection)`. The self-hash property is omitted from that projection.
Integrity hashes identify the declared canonical record; they do not stand
in for artifact content hashes.

## 6. Acyclic dependency and ownership

The hash dependency graph is:

`v7 candidate inputs -> CandidateManifestHash/BuildIdentity ->
decision-m3u subordinate (M3UDecisionHash) and decision-xmltv subordinate
(XMLTVDecisionHash, when Generated) -> decision-manifest aggregate
(DecisionManifestHash) -> accepted-state/output -> generation-manifest ->
pointer`.

`DecisionManifestHash` is the sole authoritative decision hash. The
aggregate hashes only its declared fields under `decision-manifest/v2`;
it references the already computed subordinate hashes and does not include
accepted-state, output, generation, pointer, or journal hashes. Each
subordinate decision hash covers only its own ordered projection under its
own domain, and neither subordinate projection references the aggregate.
Consequently, the decision portion of the graph is acyclic.

`PreviousStateHash` is owned only by `accepted-state/v2`; it is `null` only
for the first accepted generation and otherwise equals the prior
generation's `AcceptedStateHash`. It is never derived from current state,
current output, or journal bytes. `PreviousOutputManifestHash` is owned only
by `generation-manifest/v2`; its required field is `null` only on the first
generation and otherwise equals the prior generation's `OutputManifestHash`.
The previous-output-manifest object and previous M3U/XMLTV descriptors are
absent on the first generation; they are never represented by a null object.
The previous descriptors, when present, point to artifacts in that same prior
generation and are not current-output fallbacks.

The output-manifest object is serialized as `accepted-output.manifest.json`
and uses `previous-output-manifest/v2`. The domain name describes its role
as the prior-output reference consumed by the next generation; it is also
the authoritative manifest for the current generation when published. Thus
no unlisted `output-manifest/v2` domain exists.

`OutputManifestHash` excludes the required `AcceptedStateHash` reference
from its hash input so that output can be hashed before the accepted state;
`AcceptedStateHash` includes `AcceptedOutputManifestHash`. This is the sole
cross-reference exclusion required to avoid a state/output cycle, in
addition to each object's self-hash exclusion and the explicit
audit/operational exclusions in PART-B.

## 7. Cross-object binding invariants

An accepted pointer names exactly one generation and must match the final
generation directory name. Its `GenerationManifestHash`,
`AcceptedStateHash`, and `AcceptedOutputManifestHash` must byte-resolve to
the generation manifest, accepted state, and accepted output manifest in
that directory. The generation manifest must in turn match the candidate,
the aggregate decision manifest, accepted state, and output manifest.

The aggregate decision manifest's candidate hash, build identity, M3U
decision hash, XMLTV status/hash, and `DecisionIds` must match its
subordinate projections. The M3U and (when Generated) XMLTV subordinate
projections must have the same candidate hash, build identity, parent
generation hash, and disjoint complete entry partition. The aggregate
`DecisionIds` are the same sorted unique IDs as the M3U subordinate and,
when XMLTV is Generated, the XMLTV subordinate. For NotGenerated,
`XMLTVDecisionHash` is `null` and no XMLTV subordinate decision object is
required. Accepted state is the authority for included/excluded candidate
IDs, accepted binding IDs, XMLTV status, the aggregate
`DecisionManifestHash`, and the previous-state link; no state or generation
field may name either subordinate hash.

The output manifest's active content hashes must equal the hashes of the
exact active descriptors and exact artifact bytes. Generated XMLTV
requires one non-null content hash/length/path in every linked descriptor;
NotGenerated requires null content hash/path and zero length everywhere
those fields exist, and no XMLTV file. M3U is always generated. A first
generation has a null `PreviousOutputManifestHash` and no previous output
manifest object or previous artifact descriptors; null is not used as an
absent previous object.

All links are checked against exact bytes before authority is declared. A
mismatch, stale candidate/decision/parent, mixed `GenerationId`,
inconsistent status/nullability, or a link to a missing object is invalid
and fails closed.
