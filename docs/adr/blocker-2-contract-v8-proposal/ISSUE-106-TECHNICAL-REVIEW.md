# Issue #106 technical integration review

Status: REVIEW PACKET / NOT NORMATIVE / NOT AN APPROVAL

ProposalId: `blocker-2-contract/proposal-4`

Proposed revision label: `blocker-2-contract/v8`

Current authority: frozen `blocker-2-contract/v7`

Current frozen RevisionContentId: `c2779f69a54695237cdb4dafa87e231a2a53d597fba11769e2fbcea9cf85cd8a`

This packet is an integration checklist and evidence index for the proposal in
this directory. It does not add a schema, property order, hash rule, recovery
classification, or implementation requirement. It is not one of the five
normative files used to compute the proposal's eventual `RevisionContentId`.
No v8 `ContractRevisionId` or `RevisionContentId` exists yet.

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
| v8 ContractRevisionId | Not minted |
| v8 RevisionContentId | Not computed from final approved bytes |
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
| PART-A -> PART-B | Acceptance projections use `blocker-2-contract/v8-acceptance`; canonical ordered UTF-8 JSON and domain-separated hash rules apply uniformly | Review exact field-level exceptions and self-hash omissions |
| PART-B -> PART-C | Generation, accepted-state, output, decision, previous-output, and pointer hashes must resolve to one generation and candidate manifest | Proposed; cross-binding review still required |
| PART-C -> PART-A | Journal validation and recovery use the central version registry and the acyclic hash graph | JournalV2 is now textually defined in PART-C §6; verify its version/ID encoding against PART-A |
| Candidate -> decision | Decisions consume immutable v7 candidate manifest/build identity and identify the accepted parent generation | Proposed; stale candidate/parent rejection needs adversarial review |
| Decision -> accepted state | Included/excluded IDs, binding IDs, XMLTV status, and decision hash must agree exactly | Proposed; decision-manifest hash cardinality needs clarification |
| Accepted state -> outputs | Active output metadata and bytes must bind to the same generation and accepted-state hash | Proposed; NotGenerated XMLTV hash handling needs clarification |
| Outputs -> previous output | Previous files refer only to the immediately prior accepted generation; first generation has no previous-output object | Proposed; status/hash null rules need an end-to-end example |
| Generation -> pointer | Pointer names one complete generation and all required manifest/state/output hashes; pointer replacement is the authority transition | Proposed; output-manifest role is defined in PART-A but needs cross-part verification |
| Journal -> recovery | Journal phases classify OLD/NEW authority around pointer replacement and never edit accepted output bytes | Proposed; exact JournalV2 is present, but runtime evidence is out of scope |
| Review packet -> normative content | This file reports integration findings but does not define schemas or enter RevisionContentId | Preserved; explicitly non-normative |

## Validation matrix categories

This matrix separates what can be checked from contract text from what requires
implementation evidence after freeze. `TEXT` means the proposal states an
intended rule; it does not mean the rule has passed runtime validation.

| Category | Contract checks | Current disposition | Required evidence before implementation approval |
|---|---|---|---|
| Authority and version scope | v7 candidate authority, v8 proposal label, scoped acceptance value, no draft authority | TEXT / PASS for boundary | Governance review and freeze record |
| Exact projection closure | Property order, required fields, null/missing rules, array ordering, self-field omission | TEXT / REVIEW | Independent schema/projection vectors for all ten domains |
| Canonical byte encoding | UTF-8 without BOM, compact ordered JSON, no trailing newline, unsigned lengths | TEXT / REVIEW | Byte-for-byte serializer vectors, including null and empty cases |
| Hash domains and self-hashes | Domain-separated input, omitted self field, lowercase SHA-256 output | TEXT / REVIEW | Independent recomputation from captured canonical bytes |
| Dependency acyclicity | Candidate -> decision -> state/output -> generation -> pointer; journal points backward | TEXT / REVIEW | Graph walk and negative cycle/dependency cases |
| Cross-object binding | GenerationId, CandidateManifestHash, state/output/decision/pointer hashes agree | TEXT / REVIEW | Mismatch matrix for every edge and stale-parent case |
| Candidate isolation | v7 candidate bytes and values remain unchanged; candidate namespace is not accepted state | TEXT / PASS for scope | Before/after byte comparison and namespace separation evidence |
| Determinism and permutation invariance | Sorting, unique IDs, status projections, previous linkage | TEXT / REVIEW | Repeated equivalent builds and input-order permutations |
| XMLTV status/nullability | Generated versus NotGenerated content and path/null rules | TEXT / BLOCKED by cross-manifest hash consistency | Explicit first-generation and no-XMLTV vectors |
| Generation/previous linkage | First generation absence; later generation exact previous accepted output | TEXT / REVIEW | Two-generation and stale-previous-manifest vectors |
| Transaction durability | Flush/close/reopen/verify and pointer replacement boundary | TEXT / REVIEW | Fault-hook evidence at every durability boundary |
| Crash recovery | OLD before pointer replacement, NEW after replacement, fail closed on damaged authority | TEXT / REVIEW | Crash matrix with journal and pointer remnants |
| Path and reparse safety | Safe roots, no path substitution, no guessed latest-file authority | TEXT / REVIEW | Adversarial path/reparse and malformed-remnant cases |
| Duplicate evidence | `DuplicateCount` derived outside occurrence digests and excludes representative | TEXT / PASS as disposition | Evidence population vectors and review/collision ownership |
| Governance and reproducibility | Five-file content manifest excludes this packet and freeze metadata | TEXT / REVIEW | Independent RevisionContentId calculation after final freeze candidate |

## Proposed-domain review matrix

| Domain | Intended owner | Proposed projection | Integration check still required |
|---|---|---|---|
| `pointer/v2` | PART-B | `Version,GenerationId,GenerationManifestHash,AcceptedStateHash,AcceptedOutputManifestHash,PointerHash` | Verify pointer references the PART-A output-manifest role and exact bytes |
| `accepted-state/v2` | PART-B | Accepted generation/build/candidate/decision/output IDs, included/excluded IDs, binding IDs, XMLTV status, timestamp, self-hash | Verify state/output ordering and excluded self/reference fields |
| `active-m3u/v2` | PART-B | Active M3U metadata and content binding | Verify `OutputManifestHash` against the PART-A output-manifest projection |
| `active-xmltv/v2` | PART-B | Generated/NotGenerated status and conditional content fields | Resolve required generation hash versus null content hash |
| `previous-m3u/v2` | PART-B | Prior accepted M3U plus `PreviousGenerationId` | Verify previous hash and generation coherence |
| `previous-xmltv/v2` | PART-B | Prior accepted XMLTV plus `PreviousGenerationId` | Resolve NotGenerated previous hash binding |
| `decision-m3u/v2` | PART-B | Subordinate M3U decision hash | Feeds aggregate `DecisionManifestHash`; resolved |
| `decision-xmltv/v2` | PART-B | Subordinate XMLTV decision hash/status | Feeds aggregate when Generated; null/absent subordinate on NotGenerated; resolved |
| `generation-manifest/v2` | PART-B | Generation, candidate, aggregate decision, state, output, active, previous hashes | Aggregate decision and XMLTV status/null rules resolved |
| `previous-output-manifest/v2` | PART-B | Prior generation output references and self-hash | First-generation absence and status/hash vectors resolved |

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
3. **Runtime validation: EXPECTED / NOT APPLICABLE TO CONTRACT FREEZE.** Runtime
   acceptance, promotion, recovery, serializer, durability, and crash testing
   are deferred until after the successor revision is frozen.
4. **Fixture values: evidence only.** Preserved v7 hashes are not acceptance
   constants for unrelated candidates or generations.
5. **DuplicateCount: resolved as a derived v7 evidence field.** It remains
   excluded from occurrence projections and successor acceptance objects.

Material unresolved contract issues: NONE.

The proposal remains unfrozen and has no runtime authority. Its candidate RCID
must be independently recomputed from the final five normative proposal files
before any freeze decision.

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
work until every open limitation above has a normative disposition and the new
revision is frozen.
