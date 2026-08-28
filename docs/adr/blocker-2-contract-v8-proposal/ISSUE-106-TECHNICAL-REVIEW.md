# Issue #106 technical integration review

Status: REVIEW PACKET / NOT NORMATIVE / NOT AN APPROVAL

ProposalId: `blocker-2-contract/proposal-4`

Proposed revision label: `blocker-2-contract/v8`

Current authority: frozen `blocker-2-contract/v7`

Current frozen RevisionContentId: `c2779f69a54695237cdb4dafa87e231a2a53d597fba11769e2fbcea9cf85cd8a`

This packet is an integration checklist and evidence index for the proposal in
this directory. It does not add a schema, property order, hash rule, recovery
classification, or implementation requirement. It is not one of the five
normative files used to compute the proposal's `RevisionContentId`.
At candidate normative HEAD `08dac95f9f97af2534905215a2daabcbd04e118b`, the
exact five normative files currently compute to candidate
`RevisionContentId` `1d7bc81f362c632cad433e1ab65711c61b0950ac9d7ffe7f3942d1b69fa0d91b`.
That is a reproducibility reference, not a minted `ContractRevisionId` or
frozen authority.

## Review conclusion

The proposal now defines one aggregate `decision-manifest/v2` identity. The subordinate M3U and XMLTV decision hashes feed that aggregate; generation and accepted-state bind only the singular aggregate `DecisionManifestHash`. XMLTV Generated/NotGenerated status and nullable content-hash rules are defined consistently across current and previous output projections, including first-generation and four later transitions.

The proposal is a contract candidate, not runtime authority. Runtime acceptance, promotion, recovery, and durability validation are intentionally deferred until after a successor revision is approved and frozen.

No acceptance, decision, promotion, recovery, pointer-publication,
generation-publication, or active-output implementation is authorized by this
packet or by the unfrozen proposal.

## Authority and version boundary

| Item | Required value or disposition |
|---|---|
| Prior authority | `blocker-2-contract/v7` |
| Prior RevisionContentId | `c2779f69a54695237cdb4dafa87e231a2a53d597fba11769e2fbcea9cf85cd8a` |
| Frozen approved normative commit | `91f3a15431d8c11cbe30d0c1e63d4b937815dea0` |
| Frozen attestation commit | `9cae7f29690ea5d171a1a10f1538c985db6e2077` |
| Proposal identity | `blocker-2-contract/proposal-4` |
| Proposed label | `blocker-2-contract/v8` |
| Candidate contract value | `blocker-2-contract/v7` (preserved) |
| Acceptance contract value | `blocker-2-contract/v8-acceptance` (proposed, scoped to acceptance/promotion) |
| Candidate normative HEAD | `08dac95f9f97af2534905215a2daabcbd04e118b` (convenience pointer only) |
| Candidate `RevisionContentId` | `1d7bc81f362c632cad433e1ab65711c61b0950ac9d7ffe7f3942d1b69fa0d91b` (computed from the current five normative files; not minted) |
| v8 `ContractRevisionId` | Not minted |
| v8 frozen `RevisionContentId` | Not recorded; the candidate value above is not frozen authority |
| Runtime authority | None until a new revision is approved and frozen |

The proposal's version registry must remain the sole source for version values.
A field named `Version` in a retained candidate projection must not be changed
merely because an acceptance projection uses the v8 acceptance value.
`Journal.Version` is the explicit PART-C exception and is the literal integer
`2`, not `AcceptanceContractVersion`.

## Preserved frozen-v7 candidate values

The following values and boundaries are preserved from the frozen candidate
contract. They are contract values, not values to be regenerated under the v8
acceptance namespace:

| Candidate value or rule | Preserved value |
|---|---|
| `ContractVersion` / candidate `Version` | `blocker-2-contract/v7` |
| `IdentityRulesVersion` | `lineup-history-v1` |
| `M3UParserContractVersion` | `m3u-parser-v1` |
| `XMLTVParserContractVersion` | `xmltv-parser-v1` |
| `M3USerializerVersion` | `m3u-serializer-v1` |
| `XMLTVSerializerVersion` | `xmltv-serializer-v1` |
| `GuideBindingContractVersion` | `guide-binding-exact-ordinal-v1` |
| Candidate hash domains | Existing frozen v7 domains, including `candidate-manifest/v2`, `raw-m3u-occurrence/v2`, `raw-xmltv-occurrence/v2`, and `raw-programme/v2` |
| Candidate namespace authority | Candidate manifest hash and candidate artifact bytes remain v7 candidate authority; a candidate namespace is never accepted state |
| Candidate review privacy boundary | Candidate review remains candidate-only; stream URLs and other restricted raw values are not exposed in review text |

The following are **reference evidence values from the v7 candidate packet**,
not universal constants and not v8 acceptance values. They must not be copied
into a new implementation as expected output for unrelated inputs:

- `BuildIdentity`: `089d4e1b212515715546cbe2409fb59742d0fe61bbeec74d4b05ebaa7fc01dcd`
- Candidate M3U fixture: 242 bytes,
  `d135af5f631311bea44709224eec8c4815d5979de8165cdda8226de022cc55f3`
- Candidate manifest hash / namespace:
  `bbf45601c4c7e888bd9f4c571dac176957bcf4b9b4d2a13c659ed6b065144b9e`
- Build-identity evidence direct SHA-256:
  `d2a13faa2c9b86e752de6aa434e1e0450416c6bf9d7e93f686f6f55de9924530`

The authoritative source for these v7 values is
[`PR1-ARCHITECTURE-EVIDENCE.md`](../blocker-2-contract/PR1-ARCHITECTURE-EVIDENCE.md).
The fixture-specific values above prove neither v8 freeze nor acceptance
runtime behavior.

## Cross-part integration packet

| Integration boundary | Expected contract relationship | Review disposition |
|---|---|---|
| PART-A -> retained candidate | Candidate fields and candidate BuildIdentity remain v7; PART-A's scoped registry must not rewrite them | Preserve; no candidate delta is in scope |
| PART-A -> PART-B | Acceptance projections use `blocker-2-contract/v8-acceptance`; canonical ordered UTF-8 JSON and domain-separated hash rules apply uniformly | Closed in current contract text; field-level exceptions and self-hash omissions are explicit in PART-A/PART-B |
| PART-B -> PART-C | Generation, accepted-state, output, decision, previous-output, and pointer hashes must resolve to one generation and candidate manifest | Closed in current contract text; cross-object bindings and required status/null rules are explicit |
| PART-C -> PART-A | Journal validation and recovery use the central version registry and the acyclic hash graph | Closed in current contract text; JournalV2 is owned by PART-C §6 and its literal `Version` 2 exception is explicit |
| Candidate -> decision | Decisions consume immutable v7 candidate manifest/build identity and identify the accepted parent generation | Closed in current contract text; candidate/build/parent mismatches fail the stated validation |
| Decision -> accepted state | Included/excluded IDs, binding IDs, XMLTV status, and decision hash must agree exactly | Closed in current contract text; the aggregate owns the singular `DecisionManifestHash` and status |
| Accepted state -> outputs | Active output metadata and bytes must bind to the same generation and accepted-state hash | Closed in current contract text; output and active descriptors carry the required generation/state links |
| Outputs -> previous output | Previous files refer only to the immediately prior accepted generation; first generation has no previous-output object | Closed in current contract text; first-generation and later status/hash rules are explicit |
| Generation -> pointer | Pointer names one complete generation and all required manifest/state/output hashes; pointer replacement is the authority transition | Closed in current contract text; pointer references and compare-and-swap postconditions are explicit |
| Journal -> recovery | Journal phases classify OLD/NEW authority around pointer replacement and never edit accepted output bytes | Closed in current contract text; runtime fault evidence is outside this contract-freeze review |
| Review packet -> normative content | This file reports integration findings but does not define schemas or enter RevisionContentId | Preserved; explicitly non-normative |

## Validation matrix categories

This matrix separates what can be checked from contract text from what requires
implementation evidence after freeze. `TEXT` means the proposal states an
intended rule; it does not mean the rule has passed runtime validation.

| Category | Contract checks | Current disposition | Required evidence before implementation approval |
|---|---|---|---|
| Authority and version scope | v7 candidate authority, v8 proposal label, scoped acceptance value, no draft authority | TEXT / CLOSED FOR CONTRACT SCOPE | Governance review and freeze record |
| Exact projection closure | Property order, required fields, null/missing rules, array ordering, self-field omission | TEXT / CLOSED | Independent schema/projection vectors for all eleven projections are post-freeze implementation evidence |
| Canonical byte encoding | UTF-8 without BOM, compact ordered JSON, no trailing newline, unsigned lengths | TEXT / CLOSED | Byte-for-byte serializer vectors, including null and empty cases, are post-freeze implementation evidence |
| Hash domains and self-hashes | Domain-separated input, omitted self field, lowercase SHA-256 output | TEXT / CLOSED | Independent recomputation from captured canonical bytes is post-freeze implementation evidence |
| Dependency acyclicity | Candidate -> decision -> state/output -> generation -> pointer; journal points backward | TEXT / CLOSED | Graph walk and negative cycle/dependency cases are post-freeze implementation evidence |
| Cross-object binding | GenerationId, CandidateManifestHash, state/output/decision/pointer hashes agree | TEXT / CLOSED | Mismatch matrix for every edge and stale-parent case is post-freeze implementation evidence |
| Candidate isolation | v7 candidate bytes and values remain unchanged; candidate namespace is not accepted state | TEXT / CLOSED FOR SCOPE | Before/after byte comparison and namespace separation evidence are post-freeze implementation evidence |
| Determinism and permutation invariance | Sorting, unique IDs, status projections, previous linkage | TEXT / CLOSED | Repeated equivalent builds and input-order permutations are post-freeze implementation evidence |
| XMLTV status/nullability | Generated versus NotGenerated content and path/null rules | TEXT / CLOSED | First-generation and four later transition vectors are post-freeze implementation evidence |
| Generation/previous linkage | First generation absence; later generation exact previous accepted output | TEXT / CLOSED | Two-generation and stale-previous-manifest vectors are post-freeze implementation evidence |
| Transaction durability | Flush/close/reopen/verify and pointer replacement boundary | TEXT / DEFINED; NOT APPLICABLE TO CONTRACT FREEZE REVIEW | Fault-hook evidence at every durability boundary is required only for post-freeze implementation approval |
| Crash recovery | OLD before pointer replacement, NEW after replacement, fail closed on damaged authority | TEXT / DEFINED; NOT APPLICABLE TO CONTRACT FREEZE REVIEW | Crash matrix with journal and pointer remnants is required only for post-freeze implementation approval |
| Path and reparse safety | Safe roots, no path substitution, no guessed latest-file authority | TEXT / DEFINED; NOT APPLICABLE TO CONTRACT FREEZE REVIEW | Adversarial path/reparse and malformed-remnant evidence is required only for post-freeze implementation approval |
| Duplicate evidence | `DuplicateCount` derived outside occurrence digests and excludes representative | TEXT / CLOSED FOR DISPOSITION | Evidence population vectors and review/collision ownership are post-freeze implementation evidence |
| Governance and reproducibility | Five-file content manifest excludes this packet and freeze metadata | TEXT / CANDIDATE COMPUTED | Independent `RevisionContentId` reproduction and freeze record remain required |

## Domain closure matrix

| Domain | Intended owner | Projection | Closure disposition |
|---|---|---|---|
| `pointer/v2` | PART-B | `Version,GenerationId,GenerationManifestHash,AcceptedStateHash,AcceptedOutputManifestHash,PointerHash` | Closed; pointer references the declared output-manifest role and exact hashes |
| `accepted-state/v2` | PART-B | Accepted generation/build/candidate/decision/output IDs, included/excluded IDs, binding IDs, XMLTV status, timestamp, self-hash | Closed; state ordering and excluded self/reference fields are explicit |
| `active-m3u/v2` | PART-B | Active M3U metadata and content binding | Closed; `OutputManifestHash` and exact artifact binding are explicit |
| `active-xmltv/v2` | PART-B | Generated/NotGenerated status and conditional content fields | Closed; required generation link and status-dependent content fields are explicit |
| `previous-m3u/v2` | PART-B | Prior accepted M3U plus `PreviousGenerationId` | Closed; prior hash and generation coherence are explicit |
| `previous-xmltv/v2` | PART-B | Prior accepted XMLTV plus `PreviousGenerationId` | Closed; NotGenerated prior hash/null rules are explicit |
| `decision-m3u/v2` | PART-B | Subordinate M3U decision hash | Closed; feeds aggregate `DecisionManifestHash` |
| `decision-xmltv/v2` | PART-B | Subordinate XMLTV decision hash/status | Closed; feeds the aggregate when Generated and is absent with aggregate null hash on NotGenerated |
| `generation-manifest/v2` | PART-B | Generation, candidate, aggregate decision, state, output, active, previous hashes | Closed; aggregate decision and XMLTV status/null rules are explicit |
| `previous-output-manifest/v2` | PART-B | Prior generation output references and self-hash | Closed; first-generation absence and status/hash rules are explicit |

## Status and dispositions

1. **Decision identity cardinality: RESOLVED.** `DecisionManifestV2` is the
   sole owner of `DecisionManifestHash`; subordinate M3U/XMLTV decision
   projections own only their subordinate hashes. Generation and accepted state
   reference only the aggregate.
2. **NotGenerated XMLTV: RESOLVED.** `XMLTVDecisionStatus` is copied across
   decision, accepted-state, output, active, and generation projections.
   Generated requires content hash, positive length, path, and file. NotGenerated
   requires null content hash, zero length, null path where defined, and no
   artifact. Integrity links remain required.
3. **Runtime validation: NOT APPLICABLE TO CONTRACT FREEZE REVIEW.** This
   packet evaluates contract text only. Runtime acceptance, promotion, recovery,
   serializer, durability, and crash testing are deferred until after the
   successor revision is approved and frozen.
4. **Fixture values: evidence only.** Preserved v7 hashes are not acceptance
   constants for unrelated candidates or generations.
5. **DuplicateCount: closed.** It remains a derived v7 evidence field,
   excluded from occurrence projections and successor acceptance objects; exact
   overflow above `4294967295` fails closed before serialization or acceptance.
6. **PreviousStateHash: closed.** It has one owner in accepted-state/v2, is null
   only for first generation, and otherwise equals the prior AcceptedStateHash
   without independent rehashing.

Material unresolved contract issues: NONE.

## Remaining limitations

These are process or post-freeze implementation limitations, not unresolved
decision/XMLTV schema closures:

1. Proposal-4 is not frozen and has no runtime authority. The candidate
   `RevisionContentId` above must be independently reproduced from the final
   five normative files and recorded with a new `ContractRevisionId` in the
   freeze record.
2. Runtime acceptance, serialization, durability, path-safety, and crash-
   recovery evidence is not produced by this contract-freeze packet and is not
   applicable to this review. It is required only when implementation approval
   is sought against the frozen revision.
3. Technical preservation, independent adversarial, governance, and
   Architecture Authority review, followed by the ordered freeze record,
   remain required by the proposal's governance boundary.

## Required review and freeze record

The review sequence remains ordered:

1. Technical preservation review confirms v7 candidate values and bytes are
   retained and the v8 delta is bounded to acceptance/promotion surfaces.
2. Independent adversarial review checks canonical bytes, determinism, hash
   dependencies, stale links, path safety, durability, and recovery.
3. Governance review confirms sole ownership, scope, authority, and the
   non-normative status of this packet.
4. Architecture Authority accepts one exact five-file revision candidate.
5. Freeze records the new `ContractRevisionId`, independently reproduced
   `RevisionContentId`, owner, reviewers, results, date, and frozen commit.

No implementation branch may claim v8 compliance or begin acceptance/promotion
work until the required technical, adversarial, governance, and Architecture
Authority reviews are complete, a new `ContractRevisionId` and independently
reproduced `RevisionContentId` are recorded, and the revision is frozen.
