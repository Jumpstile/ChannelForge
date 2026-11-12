# Contract revision proposal: raw occurrence digest acyclicity

Status: proposal. Not frozen. Grants no implementation authority.

Prior ContractRevisionId: `blocker-2-contract/v1`
Prior artifact commit: `af9d5da3dc81fc4d484a9f475bc0da884d0d880c`
Proposed ContractRevisionId: `blocker-2-contract/v2`
Targeted delta: two sentences in `PART-B-semantic-schemas.md` sections 5 and 6. No other section, schema, enum, projection, or protocol changes.

This document does not modify the frozen artifact. `docs/adr/blocker-2-contract/` remains byte-identical to the frozen SHA.

## 1. Confirmed defect

`docs/adr/blocker-2-contract/PART-B-semantic-schemas.md`, section 5, line 6:

> RawM3UOccurrence property order is Version, LogicalSourceId, RawTvgIdPresence, RawTvgId, TvgName, DisplayName, GroupTitle, Logo, ChannelNumber, StreamUrl, SourceLocalOrdinal, RawM3UOccurrenceDigest. Presence is Present or Missing. Missing is null in RawTvgId and is distinct from Present with an empty string or whitespace-only string. RawM3UOccurrenceDigest omits itself and hashes all other properties in raw-m3u-occurrence/v2. No field is trimmed, normalized, or case-folded for guide binding.

Same file, section 5, line 12:

> SourceLocalOrdinal is zero-based and is assigned after canonical sorting of all raw occurrences of one LogicalSourceId by the tuple (RawM3UOccurrenceDigest, RawTvgIdPresence rank, RawTvgId or empty, TvgName or empty, DisplayName or empty, GroupTitle or empty, Logo or empty, ChannelNumber or empty, StreamUrl). Equal complete raw occurrences have identical digests and are exact duplicates; their multiplicity is stored in DuplicateCount and only the representative with the lowest canonical tuple is retained. Input order never selects a representative.

`SourceLocalOrdinal` is a declared `RawM3UOccurrence` property, and the digest omits only itself, so `SourceLocalOrdinal` is inside the digest input:

```text
SourceLocalOrdinal ──▶ RawM3UOccurrenceDigest ──▶ (first sort key) ──▶ SourceLocalOrdinal
```

The cycle blocks any conforming implementation. Line 12 also asserts that equal complete raw occurrences have identical digests, which is unsatisfiable while a per-occurrence ordinal is a digest input. Both sentences become true only if the ordinal is excluded from the digest.

`SYMBOL-CLOSURE.md` section 1 independently supports exclusion. `StructuralEvidenceInput` is:

> Version, LogicalSourceId, ElementKind, StructuralOrdinal, RawOccurrenceDigest, DuplicateCount

The closure treats the ordinal and the raw occurrence digest as two independent inputs, which is only coherent if the digest does not already contain the ordinal.

## 2. Confirmed XMLTV gap

Section 6, line 29:

> RawXMLTVChannelOccurrence property order is Version, LogicalSourceId, StructuralOccurrenceOrdinal, RawChannelIdPresence, RawChannelId, DisplayNameNodes, IconNodes, RawChannelExtensions, RawXMLTVOccurrenceDigest. RawProgrammeOccurrence property order is Version, LogicalSourceId, StructuralOccurrenceOrdinal, RawProgrammeChannelIdPresence, RawProgrammeChannelId, StartRaw, StopRaw, TitleNodes, SubTitleNodes, DescNodes, CategoryNodes, EpisodeNumbers, Rating, StarRating, PreviouslyShown, Premiere, LastChance, Credits, Date, IconNodes, RawProgrammeExtensions, RawProgrammeDigest.

Section 6, line 31:

> StructuralOccurrenceOrdinal is zero-based within the complete population of raw occurrences of the same LogicalSourceId and element kind, assigned by canonical sort, not parser order. Channel sort tuple is (RawChannelIdPresence rank, RawChannelId or empty, canonical display-node bytes, canonical icon-node bytes, canonical extension bytes, RawXMLTVOccurrenceDigest). Programme sort tuple is (RawProgrammeChannelIdPresence rank, RawProgrammeChannelId or empty, StartRaw or empty, StopRaw or empty, canonical title/subtitle/desc/category/episode/extension bytes, RawProgrammeDigest). A complete tie has identical raw digest and is represented with DuplicateCount; otherwise the digest is the final tie-breaker. No input permutation changes the ordinal.

v1 never states the projection for `RawXMLTVOccurrenceDigest` or `RawProgrammeDigest`. `StructuralOccurrenceOrdinal` is a declared property of both objects and both ordinals are assigned by a tuple whose final tie-breaker is the corresponding digest. The XMLTV dependency is therefore undefined, and under the section 5 wording it is the same latent cycle. This must be stated explicitly, not inferred.

## 3. Options evaluated

| Option | Change | Assessment |
|---|---|---|
| A. Exclude the ordinal from the raw occurrence digest | Two sentences | Recommended. Removes the cycle at its source, keeps one digest per occurrence, keeps every existing sort tuple, keeps duplicate detection exact |
| B. Add a separate pre-ordinal sort digest | New hash domain plus a second per-occurrence digest | Rejected. Two digests per occurrence, a new domain in the PART-A inventory, and new equality/evidence questions for the extra value |
| C. Iterative fixed-point ordinal assignment | New algorithm section | Rejected. Explicitly excluded by the revision goals, unbounded convergence argument, no determinism benefit |
| D. Drop the digest from the sort tuple | Change both ordering tuples | Rejected. Removes the deterministic final tie-breaker and edits more normative text than option A |

## 4. Proposed exact changes

### 4.1 PART-B section 5, line 6, final digest sentence

Current:

> RawM3UOccurrenceDigest omits itself and hashes all other properties in raw-m3u-occurrence/v2.

Proposed:

> RawM3UOccurrenceDigest omits itself and SourceLocalOrdinal and hashes all remaining properties in declared property order in raw-m3u-occurrence/v2. The digest input is therefore Version, LogicalSourceId, RawTvgIdPresence, RawTvgId, TvgName, DisplayName, GroupTitle, Logo, ChannelNumber, StreamUrl. The digest is ordinal-independent and is fully computable before SourceLocalOrdinal is assigned.

### 4.2 PART-B section 6, line 29, added digest sentence

Proposed addition at the end of the paragraph:

> RawXMLTVOccurrenceDigest omits itself and StructuralOccurrenceOrdinal and hashes all remaining RawXMLTVChannelOccurrence properties in declared property order in raw-xmltv-occurrence/v2. RawProgrammeDigest omits itself and StructuralOccurrenceOrdinal and hashes all remaining RawProgrammeOccurrence properties in declared property order in raw-programme/v2. Both digests are ordinal-independent and are fully computable before StructuralOccurrenceOrdinal is assigned.

No edit to section 6, line 31. Both ordering tuples remain exactly as frozen and become computable.

### 4.3 Field projection delta

| Object | v1 digest input | v2 digest input | Delta |
|---|---|---|---|
| RawM3UOccurrence | all properties except RawM3UOccurrenceDigest, so including SourceLocalOrdinal | all properties except RawM3UOccurrenceDigest and SourceLocalOrdinal | `SourceLocalOrdinal` removed |
| RawXMLTVChannelOccurrence | undefined | all properties except RawXMLTVOccurrenceDigest and StructuralOccurrenceOrdinal | defined; ordinal excluded |
| RawProgrammeOccurrence | undefined | all properties except RawProgrammeDigest and StructuralOccurrenceOrdinal | defined; ordinal excluded; domain fixed as raw-programme/v2 |

### 4.4 Resulting dependency graph

```text
raw occurrence properties (ordinal excluded)
            │
            ▼
canonical digest projection            raw-m3u-occurrence/v2
            │                          raw-xmltv-occurrence/v2
            ▼                          raw-programme/v2
deterministic canonical ordering        (digest is first or final tie-break key)
            │
            ▼
ordinal assignment                     SourceLocalOrdinal
            │                          StructuralOccurrenceOrdinal
            ▼
ordinal consumers                      EntryId, BindingKey, programme identity,
                                       StructuralEvidenceHash, GuideCandidateIdRecord
```

Acyclic. Every ordinal consumer named in PART-B lines 10, 33, 35, 48 and `SYMBOL-CLOSURE.md` section 1 is unchanged, because each consumes the ordinal and the digest after assignment.

## 5. Preserved behavior

- Deterministic canonical bytes. Ordering tuples, candidate M3U byte rules, and candidate XMLTV byte rules are untouched; every sort key is now computable in one pass.
- Duplicate detection. Byte-identical raw occurrences now genuinely produce identical digests, which is what line 12 and line 31 already assert; `DuplicateCount` and representative selection are unchanged.
- Exact raw evidence. No trim, case fold, Unicode normalization, or SafeText conversion is introduced. Presence, empty, and whitespace-only distinctions are unchanged. Guide binding remains exact raw ordinal equality.
- No fixed-point algorithm. One projection, one sort, one assignment.

## 6. Compatibility impact

- Semantic hash values change for `raw-m3u-occurrence/v2`, `raw-xmltv-occurrence/v2`, and `raw-programme/v2`. `EntryId`, `BindingId`, `BuildIdentity`, and `CandidateManifestHash` change with them, and candidate namespace directory names change.
- No persisted accepted generation exists. `state/accepted-lineup.json`, `state/accepted-lineup.json.previous`, `output/merged.m3u`, and `output/merged.xml` are absent in the working tree, so no accepted state, pointer, journal, or previous-generation artifact requires migration.
- Domain strings are unchanged. Recommendation: keep `raw-m3u-occurrence/v2`, `raw-xmltv-occurrence/v2`, and `raw-programme/v2`, because no artifact was ever produced under a frozen and approved v1 implementation and the `ContractRevisionId` already distinguishes the revision. Renaming these domains would ripple into the PART-A exhaustive domain inventory and every consuming projection, which exceeds the minimal delta. This choice requires explicit ratification by the Approver.
- No change to promotion, journal, recovery, fault hooks, decision schemas, accepted-state schemas, or privacy rules.

## 7. Why a new revision is required

`README.md` in the frozen artifact, section "Governance and freeze control":

> The supersession and change-control authority is the Accountable Contract Owner acting with the Approver. Any proposed change must identify the prior ContractRevisionId, describe the targeted delta, and produce a new versioned revision. No amendment may silently modify a frozen revision.

> Implementation is unblocked only when a versioned contract revision exists, all required reviewers have approved it, freeze approval is recorded, and the frozen ContractRevisionId is referenced by the implementation work. Any contract modification after freeze automatically invalidates the freeze and requires the review sequence and freeze approval to run again for the new revision.

The delta changes normative semantic hash inputs, so it is not an editorial amendment. It requires the full five-step review sequence, a new `ContractRevisionId`, a new frozen SHA, and updated approvals from OMP Desktop, OMP Arcade, and the ChannelForge Architecture Authority.

## 8. Migration impact on PR #1

Blocked by this proposal, issue #101 only:

- Exact `GuideCandidateOccurrence` projection and `BindingRecord` publication, because both depend on final occurrence ordinals and digests.
- Occurrence-ordinal and digest tests: missing, empty, whitespace-only, case-only, Unicode, duplicate raw IDs, normalized-history collisions.

Not blocked, proceeding against v1 text unchanged:

- C01 through C15 named fault inventory wiring and per-hook evidence.
- Final namespace validation: manifest self-hash omission projection, declared artifact domains, every referenced artifact hash, artifact existence, byte and hash consistency, deterministic namespace identity.
- Contract drift removal: legacy version fields, outdated SafeText behavior, outdated redaction behavior, fields absent from the frozen property orders.

Current implementation state at `79d73693f1a80a321156203c6c8f198147d12d63`, recorded so the delta is auditable:

- `src/ChannelForge/Private/Get-ChannelForgeRawM3UProjection.ps1` computes an undeclared ordinal-free base digest for sorting and then publishes an ordinal-inclusive `RawM3UOccurrenceDigest`. Under v2 these collapse into one digest and the second hash computation is deleted.
- `src/ChannelForge/Private/Get-ChannelForgeRawXmltvProjection.ps1` excludes the ordinal from its sort digest, then publishes `RawProgrammeDigest` with the ordinal included, and uses domain `raw-xmltv-occurrence/v2` for programme occurrences where the frozen text assigns `raw-programme/v2`. Under v2 both behaviors are explicitly specified.
- Both projections also carry properties absent from the frozen property orders. That is implementation drift, remediated under item 4 above, not a contract defect.

Post-freeze re-evidence required for PR #1: new `CandidateManifestHash`, new candidate directory name, determinism rerun across repeated equivalent builds, C01 through C15 fault evidence, and unchanged privacy and candidate-isolation results.

## 9. Non-goals

No change to ordering tuples, duplicate semantics, guide-binding exactness, SafeText policy, review or decision schemas, accepted-state schemas, journal, promotion, recovery, or fault inventory.

Adjacent observation, deliberately excluded from this delta: `DuplicateCount` is referenced by PART-B lines 12 and 31 and by `SYMBOL-CLOSURE.md` section 1, but it is absent from both raw occurrence property orders. It creates no cycle and is recorded here for the Approver rather than changed.

## 10. Required approval sequence

1. Technical preservation review: confirm the delta is bounded to two sentences and preserves accepted technical content.
2. Adversarial review: confirm acyclicity, determinism, duplicate detection, and permutation invariance.
3. Governance review: confirm ownership, scope, and change-control compliance.
4. Architecture acceptance of the complete `blocker-2-contract/v2` revision.
5. Freeze approval recording `ContractRevisionId`, owner, reviewers, results, approval date, and the new frozen SHA.

Issues #101, #102, and #103 must then be re-pointed at the new `ContractRevisionId` and frozen SHA before implementation resumes on the blocked items.
