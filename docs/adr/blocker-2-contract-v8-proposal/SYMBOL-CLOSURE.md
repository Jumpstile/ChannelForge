# Successor symbol closure

Status: proposal-4 review inventory; NOT FROZEN. The frozen v7 candidate
definitions remain authoritative and are referenced, not redefined.

ProposalId: `blocker-2-contract/proposal-4`. Proposed revision label:
`blocker-2-contract/v8`.

An owner in this table is the sole normative owner in the proposal. A
cross-part reference does not create a second definition. Every listed
symbol has a closed owner and definition; this inventory records no
unresolved or duplicate symbol.

| Symbol | Sole owner | Scope | Definition / review status |
|---|---|---|---|
| `CandidateContractVersion` | PART-A | retained candidate | Exact value `blocker-2-contract/v7`; inherited frozen authority, not redefined |
| `BuildIdentity` | frozen v7 candidate contract | candidate | v7 candidate identity; proposal-4 does not change its projection or value rules |
| `AcceptanceContractVersion` | PART-A | acceptance/promotion | Exact value `blocker-2-contract/v8-acceptance` |
| `PointerV2` | PART-B | acceptance | `pointer/v2` ordered projection |
| `AcceptedStateV2` | PART-B | acceptance | `accepted-state/v2` ordered projection |
| `ActiveM3UV2` | PART-B | active output | `active-m3u/v2` ordered projection |
| `ActiveXMLTVV2` | PART-B | active output | `active-xmltv/v2` ordered projection |
| `PreviousM3UV2` | PART-B | previous output | `previous-m3u/v2` ordered projection |
| `PreviousXMLTVV2` | PART-B | previous output | `previous-xmltv/v2` ordered projection |
| `DecisionM3UV2` | PART-B §8 | decision subordinate | `decision-m3u/v2` ordered projection; self-hashes as `M3UDecisionHash` and is not an acceptance authority |
| `DecisionXMLTVV2` | PART-B §9 | decision subordinate | `decision-xmltv/v2` ordered projection when XMLTV is Generated; self-hashes as `XMLTVDecisionHash` |
| `DecisionManifestV2` | PART-B §10 | aggregate decision binding | `decision-manifest/v2` ordered projection binding the subordinate hashes and status; sole authoritative decision record |
| `M3UDecisionHash` | PART-B §8 | decision subordinate hash | `H(decision-m3u/v2, canonical subordinate bytes without M3UDecisionHash)` |
| `XMLTVDecisionHash` | PART-B §9–10 | decision subordinate/aggregate binding | Subordinate `H(decision-xmltv/v2, canonical bytes without XMLTVDecisionHash)` when Generated; aggregate field is `null` iff NotGenerated |
| `DecisionManifestHash` | PART-B §10 | authoritative decision binding | `H(decision-manifest/v2, canonical aggregate bytes with only DecisionManifestHash omitted)`; consumed singularly by state and generation |
| `GenerationManifestV2` | PART-B §11 | generation | `generation-manifest/v2` ordered projection |
| `PreviousOutputManifestV2` | PART-B §12 | previous output | `previous-output-manifest/v2` ordered projection |
| `TransactionPhase` | PART-C | recovery | `Prepared`, `GenerationPublished`, `PointerSwapped`, `Committed` |
| `JournalV2` | PART-C | journal | Exact `journal/v2` property order, types, phase ranks, and nullability in PART-C §6 |
| `JournalHash` | PART-C | journal | `H(journal/v2, ordered journal projection without JournalHash)` |
| `OldJournalHash` | PART-C | journal | Prior authoritative journal hash, or null only before first publication |
| `GenerationId` | PART-A | operational generation identity | Exactly 64 lowercase hexadecimal characters (32 random bytes), carried by generation bindings |
| `DuplicateCount` | PART-B §13 | occurrence/review evidence | Derived non-representative duplicate multiplicity; excluded from occurrence digests and not an occurrence property |
| `AcceptedOutputManifestV2` | PART-B §12 | acceptance/output | Current accepted output manifest uses the `previous-output-manifest/v2` projection and is serialized as `accepted-output.manifest.json`; no separate output hash domain |
| `OutputManifestHash` | PART-B §12 (hash rule in PART-A §5) | output binding | Integrity/projection hash for the declared output-manifest projection; references copy the already computed hash |

## Ownership rules

PART-A owns the scoped version registry, canonical UTF-8/JSON and
domain-separated hash rules, dependency graph, and revision-identity
procedure. PART-B owns the eleven acceptance/output/decision/previous-output
projections (including the aggregate decision binding) and the
`DuplicateCount` disposition. PART-C owns the transaction phases, journal
semantics, and recovery classifications.
`README.md` owns proposal status, authority, scope, and freeze separation.
This file owns only the cross-part ownership inventory and does not add an
alternate property order.

The candidate contract is deliberately a separate authority boundary:
candidate `Version`, `ContractVersion`, `BuildIdentity`, candidate manifest,
candidate review, candidate artifact, and candidate namespace definitions
remain v7 definitions. No successor symbol changes those values or candidate
bytes.

## Closure disposition

The eleven named proposal projections each have one owner in PART-B. The
aggregate `DecisionManifestV2` is the only authority for
`DecisionManifestHash`; `DecisionM3UV2` and `DecisionXMLTVV2` contribute
only their subordinate `M3UDecisionHash`/`XMLTVDecisionHash` values.
`AcceptedOutputManifestV2` is a role-specific use of the
`previous-output-manifest/v2` projection, not a separate output hash domain.
Hashes and IDs are consumed across parts without changing ownership.

JournalV2, its property order, and its phase/nullability rules are owned by
PART-C §6; this file intentionally does not restate those fields. The
`DuplicateCount` disposition is owned by PART-B §13 and does not add a field
to any v7 occurrence projection.

The closure inventory is ready for review only when all cross-part references
are resolved against these owners. In particular, the review gate must
recompute the two subordinate decision hashes, recompute the one aggregate
`DecisionManifestHash` under `decision-manifest/v2`, and verify that accepted
state and generation reference only that aggregate hash. For XMLTV
`NotGenerated`, the aggregate's `XMLTVDecisionStatus` is `NotGenerated`,
its `XMLTVDecisionHash` is `null`, and no XMLTV subordinate object is
required; output and generation integrity links remain required while only
content hash/path/length fields become nullable or zero where defined.
These are integration checks, not alternate symbol definitions.
