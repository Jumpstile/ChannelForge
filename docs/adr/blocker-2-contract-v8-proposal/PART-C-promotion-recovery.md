## 5. Authority, paths, and invariants

This section is normative for acceptance under `blocker-2-contract/v8-acceptance`. It defines promotion, the authoritative journal, and crash recovery; it does not authorize runtime implementation. The frozen `blocker-2-contract/v7` candidate contract is not changed.

The only authoritative current accepted state is the complete object graph named by `state/accepted-lineup.json`. A directory, output file, journal, cache entry, staging remnant, or file selected because it is newest is never authority by itself. The fixed acceptance paths are:

| Role | Path | Authority rule |
|---|---|---|
| Exclusive operation lock | `state/lineup-operation.lock` | A live exclusive handle blocks promotion and recovery. A stale marker is diagnostic only. |
| Current pointer | `state/accepted-lineup.json` | Exact `pointer/v2`; its verified `PointerHash` selects the current generation. |
| Previous pointer backup | `state/accepted-lineup.json.previous` | Exact bytes of the pointer replaced by the current pointer; absent for the first generation. |
| Journal | `state/accepted-lineup.journal.json` | Exact `Journal/v2`; only a verified phase is authoritative. |
| Journal backup | `state/accepted-lineup.journal.json.previous` | Temporary replacement backup; never an accepted-state or rollback authority. |
| Transaction staging | `state/.staging/<TransactionId>/` | Never authoritative; ownership and exact transaction identity are required for cleanup. |
| Final generation | `state/generations/<GenerationId>/` | Authoritative only when named by the verified current pointer (or verified previous pointer for lineage). |

A current pointer is valid only when its bytes, `PointerHash`, referenced generation manifest, accepted state, output manifest, active artifacts, and every transitive hash/link agree. A valid pointer plus a missing, altered, extra, or mismatched required child is a failed accepted state, not an invitation to infer or repair from another generation. Every path is opened through a safe local handle; reparse points, path substitutions, UNC/SMB paths, and changed file identity fail closed.

## 6. Authoritative Journal schema

The Journal is the sole durable transaction record. Its canonical compact UTF-8 JSON property order is exactly:

`Version, TransactionId, JournalStage, ExpectedOldPointerHash, ExpectedNewPointerHash, ExpectedOldGenerationId, ExpectedNewGenerationId, MutationRecords, OldJournalHash, JournalHash`

The schema is `journal/v2`:

| Property | Type and rule |
|---|---|
| `Version` | Literal unsigned integer `2`. |
| `TransactionId` | Non-empty lowercase 32-hex operational identifier. |
| `JournalStage` | Closed enum `None`, `Prepared`, `GenerationPublished`, `PointerSwapped`, or `Committed`; ranks are 0, 1, 2, 3, and 4. Unknown values fail closed. `None` is an in-memory pre-publication state and is never an authoritative file. |
| `ExpectedOldPointerHash` | Null or lowercase 64-hex `PointerHash`. Null only for a first acceptance with no current pointer. It is the hash of the exact bytes that must still be current before replacement. |
| `ExpectedNewPointerHash` | Null or lowercase 64-hex `PointerHash`. Required from `Prepared` onward and is the hash of the staged new pointer. |
| `ExpectedOldGenerationId` | Null or exactly 64 lowercase hexadecimal characters (`GenerationId`). Null only for a first acceptance. When present, it is the generation selected by the old pointer. |
| `ExpectedNewGenerationId` | Required exactly 64 lowercase hexadecimal characters (`GenerationId`) from `Prepared` onward; it is the final generation selected by the new pointer. |
| `MutationRecords` | Unique `MutationRecord` objects sorted by `MutationOrdinal` ascending. The records are the exact operation preconditions and postconditions, not a second source of accepted semantics. |
| `OldJournalHash` | Null only on the first publication when no prior authoritative journal exists; otherwise lowercase 64-hex hash of the immediately prior authoritative journal. |
| `JournalHash` | Lowercase 64-hex hash of this object with `JournalHash` omitted, using domain `journal/v2`. `NewJournalHash` is not a property. |

`Prepared` requires a complete verified generation in transaction staging and a complete verified staged new pointer. `GenerationPublished` additionally requires that exact generation at its final path. `PointerSwapped` additionally requires the exact new current pointer and, when an old pointer existed, the exact previous-pointer backup. `Committed` additionally requires successful reopen/verification of the complete new object graph. A phase cannot skip a lower rank, regress, or name different old/new identities. `OldJournalHash` is independent of semantic acceptance hashes and prevents an unrelated or stale journal from being adopted.

### 6.1 MutationRecord schema

The canonical property order is exactly:

`MutationOrdinal, MutationKind, RelativePath, ExpectedOldPresence, ExpectedOldByteHash, ExpectedOldFileIdentity, ExpectedNewPresence, ExpectedNewByteHash, ExpectedNewFileIdentity`

`MutationOrdinal` is a unique zero-based unsigned integer in operation order. `MutationKind` is the closed enum `Create`, `Replace`, `Move`, `Delete`, or `Verify`. `RelativePath` is a fixed repository-relative path; it cannot be absolute, UNC, a reparse-based path, or a path containing a transaction-controlled escape. Presence is `Present` or `Absent`. A present byte hash is lowercase 64-hex in the declared artifact domain; an absent byte hash is null. File identity is null exactly when the corresponding presence is `Absent`.

`Create` requires old `Absent` and new `Present`; `Delete` requires old `Present` and new `Absent`; `Replace` requires both `Present`; `Move` is represented by distinct source and destination records; `Verify` leaves bytes unchanged and records equal old/new identities. Any presence, byte-hash, or file-identity mismatch aborts recovery with `FAIL_CLOSED_RECOVERY_REQUIRED`. Mutation metadata, including paths, ordinals, and identities, is operational data and is excluded from all semantic hashes.

For each present regular file, `FileIdentity` has canonical property order `VolumeSerial, FileId, ByteLength, LastWriteUtcTicks`. Numeric values are unsigned decimal integers; `FileId` is lowercase 64-hex from the opened local handle. A changed identity is a TOCTOU failure even when content bytes happen to hash equally.

### 6.2 Journal publication durability

Every journal phase uses one publication algorithm: create staged bytes, write all bytes, `Flush(true)`, close, reopen, verify exact bytes/schema/phase/identity/hash, verify the journal path and parent are not reparse points, then atomically replace `state/accepted-lineup.journal.json`. When an old journal exists, replacement creates `state/accepted-lineup.journal.json.previous`; when none exists, the first publication uses an atomic move. Reopen and verify the authoritative destination before deleting its temporary backup. A crash before replacement trusts the prior authoritative journal; a crash after replacement trusts the newly verified phase. A journal backup is never used as an automatic rollback source.

## 7. Promotion phases and pointer replacement

The phases are strictly ordered: `Prepared` -> `GenerationPublished` -> `PointerSwapped` -> `Committed`. `OLD` means the old current pointer and its complete generation remain authoritative; `NEW` means the new pointer and its complete generation are authoritative.

| Phase | Durable facts required | Current authority | Recovery may do |
|---|---|---|---|
| None | No new journal has been published. Stage may be absent, partial, or untrusted. | OLD (or no accepted state on first acceptance) | Remove nothing unless exact transaction ownership and complete preconditions are proven; otherwise fail closed. |
| Prepared | Complete staged generation and staged new pointer have passed reopen/hash checks; Prepared journal is authoritative. | OLD | Validate the exact stage and continue, or fail closed. |
| GenerationPublished | Complete generation was moved to `state/generations/<ExpectedNewGenerationId>/`; GenerationPublished journal is authoritative. | OLD | Validate final generation and retry the next journal/pointer operation, or fail closed. |
| PointerSwapped | New pointer replacement and exact previous backup completed; PointerSwapped journal is authoritative. | NEW | Reopen every link and complete verification/Committed, or fail closed without rollback. |
| Committed | New pointer/generation graph was fully reopened and verified; Committed journal is authoritative. | NEW | Cleanup only. Cleanup errors are retryable and cannot change authority. |

The pointer replacement is one compare-and-swap boundary, never a sequence of edits to accepted output:

1. Verify the current pointer bytes and `PointerHash` equal `ExpectedOldPointerHash`; for first acceptance, verify current and previous pointers are absent.
2. Verify the final new generation and staged `pointer/v2` name exactly `ExpectedNewGenerationId` and `ExpectedNewPointerHash`.
3. If an old pointer exists, atomically replace `state/accepted-lineup.json` with the staged new pointer while creating `state/accepted-lineup.json.previous` from the exact old bytes. If none exists, atomically move the staged pointer into place only after confirming absence.
4. Reopen and hash both current and previous pointer paths. The current pointer must name NEW; the previous pointer, when present, must name OLD and be byte-for-byte the replaced pointer.
5. Only after those checks may `PointerSwapped` be published. No M3U, XMLTV, state, decision, or manifest bytes are edited during pointer replacement.

A differing old hash, unexpected pointer absence, pre-existing non-identical backup, final-generation name collision, or path identity change stops before mutation. A pointer replacement that completed while its journal still says `GenerationPublished` is recovered by validating the exact NEW/current plus OLD/previous pair and publishing `PointerSwapped`; it is never reverted by copying old output.

## 8. Durability boundary matrix

| Boundary | Before boundary | Required action | After boundary and crash authority |
|---|---|---|---|
| Child/generation stage write | Bytes absent or partial | Exclusive create, write, `Flush(true)`, close, reopen, hash and identity verify each file | Complete stage is retryable but still non-authoritative; OLD. |
| Prepared journal replace | Prior journal (or no journal) | Stage, flush, reopen/hash verify, atomic journal replace, authoritative reopen | Prepared is authoritative; OLD. |
| Generation directory move | Complete stage, final path absent | Move only the exact verified directory and durably verify parent | Final generation may exist, but Prepared remains authoritative; OLD. |
| GenerationPublished journal replace | Prepared journal, final generation complete | Publish the next verified journal | GenerationPublished is authoritative; OLD. |
| Pointer compare-and-swap | GenerationPublished, exact OLD pointer | Verify old identity, atomically replace pointer and create exact backup | Before: OLD; after: NEW, even if the old journal is still GenerationPublished. |
| PointerSwapped journal replace | New pointer/previous pair verified | Publish verified phase journal | PointerSwapped is authoritative; NEW. |
| Full graph reopen | PointerSwapped and complete NEW generation | Verify pointer, generation, state, decisions, manifests, active/previous outputs, and optional XMLTV | Verification failure is retryable/fail-closed; bytes and authority remain NEW. |
| Committed journal replace | Full graph verified | Publish Committed journal | Committed is authoritative; NEW. |
| Cleanup | Committed | Delete only exact owned staging, journal backup, and unreferenced generations | Any before/after state remains NEW; retry cleanup, never rollback. |

A flush or close failure means that boundary did not complete. A successful system call is not treated as durable until the specified reopen and verification succeed.

## 9. Recovery matrix

Recovery is first-match-wins. It never chooses a generation by directory order, timestamp, lexical order, or output contents.

| Observed state | Authority classification | Recovery action |
|---|---|---|
| Live lock handle | `FAIL_CLOSED_RECOVERY_REQUIRED` | Mutate nothing; wait for the owner. |
| No journal; no acceptance remnant; valid current pointer and complete graph | `ACCEPTED_STATE_VALID` | No automatic mutation. Optional valid previous lineage and unreferenced valid generations remain untouched. |
| No journal; completely empty accepted namespace, with or without immutable candidates | `INITIAL_BASELINE_REQUIRED` | Preserve candidates and mutate nothing. |
| No journal; any acceptance transaction remnant, including complete staging, staged pointer, pointer backup, journal staging, or transaction directory | `FAIL_CLOSED_RECOVERY_REQUIRED` | Mutate nothing; an owner may explicitly restart the validated procedure only after exclusive ownership and fresh full validation. |
| Prepared journal and exact complete staging | OLD | Validate transaction identity, stage, hashes, and old pointer; retry or fail closed. |
| Prepared journal with final generation instead of staging | OLD | Validate the moved generation; publish GenerationPublished or fail closed; never delete a referenced generation. |
| GenerationPublished journal and complete final generation, exact OLD pointer | OLD | Retry pointer compare-and-swap or fail closed. |
| GenerationPublished journal with exact NEW current and exact OLD previous backup | NEW | Publish PointerSwapped after validating both pointers and generation. |
| PointerSwapped journal and complete verified NEW graph | NEW | Publish Committed; then cleanup only. |
| Committed journal | NEW | Verify once more as required, then cleanup only. |
| Pointer or required child missing, altered, hash-invalid, or identity-mismatched | `FAIL_CLOSED_RECOVERY_REQUIRED` | Mutate nothing; do not infer, reconstruct, or roll back. |
| Journal malformed, unknown-version, hash-invalid, impossible rank/identity, or stale chain | `FAIL_CLOSED_RECOVERY_REQUIRED` | Mutate nothing; operator repair/rerun of the validated procedure is required. |
| Journal backup left without a valid in-progress replacement | `FAIL_CLOSED_RECOVERY_REQUIRED` | Never adopt the backup automatically; mutate nothing. |
| Generation has an extra child, wrong namespace, invalid XMLTV nullability, or mismatched previous linkage | `FAIL_CLOSED_RECOVERY_REQUIRED` | Preserve bytes; no guessed cleanup or promotion. |
| Reparse/path substitution, UNC/SMB path, or changed FileIdentity | `FAIL_CLOSED_RECOVERY_REQUIRED` | Stop before mutation; restart only after safe handles and identity are revalidated. |
| Cleanup failure after Committed | NEW | Leave all accepted bytes in place and retry exact cleanup later. |

A malformed journal means transaction recovery cannot establish a trusted phase; it does not authorize replacing a valid pointer from a guessed directory. A valid current pointer with valid references may remain physically usable, but automatic recovery is fail-closed until the journal/remnant ambiguity is resolved.

## 10. Fault matrix

Each fault is injected immediately before or after the named boundary. `OLD`, `NEW`, and `FAIL_CLOSED` have the meanings in section 7. A stage is complete only after flush, close, reopen, schema, hash, and identity verification.

| Fault boundary | Before/after bytes | Restart result |
|---|---|---|
| Any generation file write/flush/reopen (`GenerationManifest`, `AcceptedState`, `AcceptedOutputManifest`, decision, M3U, XMLTV) | Partial/absent or unverified stage; pointer unchanged | OLD; exact owner may retry/delete incomplete stage, otherwise FAIL_CLOSED. `NotGenerated` XMLTV has no file and must pass the corresponding absence rule. |
| Journal stage write/flush/reopen for Prepared | Partial/absent staged journal; prior journal unchanged | OLD and prior phase; any ambiguous remnant is FAIL_CLOSED. |
| Journal replace for Prepared | Before: prior phase; after: verified Prepared | OLD; trust only the phase whose replacement completed. |
| Directory move before/after | Before: stage source; after: complete final generation | OLD; Prepared remains authoritative until GenerationPublished is published. |
| Journal replace for GenerationPublished | Before: Prepared; after: verified GenerationPublished | OLD; retry exact pointer path only after final generation validation. |
| Pointer replacement before | Exact OLD pointer; staged NEW pointer | OLD; retry only after expected hash/identity checks. |
| Pointer replacement after | Exact NEW current and exact OLD previous (when applicable); journal may still be GenerationPublished | NEW; validate pair and publish PointerSwapped, never rollback. |
| Journal stage/replace for PointerSwapped | Pointer pair NEW/OLD; prior journal may still be GenerationPublished | NEW if pointer swap completed; malformed staged journal is FAIL_CLOSED and does not alter pointer. |
| Reopen/hash verification of any NEW child | Bytes unchanged, verification incomplete or failed | NEW physical authority remains; retry verification or FAIL_CLOSED, never select OLD children. |
| Journal stage/replace for Committed | Complete verified NEW graph; prior phase PointerSwapped | NEW; retry publication, never rollback. |
| Any cleanup delete before/after | Staging, journal backup, or unreferenced generation present/absent | NEW; retry cleanup only. A current or previous referenced generation is never deleted. |

Every fault result is deterministic from the durable bytes and verified identities. No fault path copies accepted output, edits a generation in place, adopts a journal backup, or guesses a parent/current generation.

## 11. Current/previous lineage

For a non-first generation, let OLD be the generation named by the pre-promotion current pointer and NEW be the generation named by the post-promotion current pointer. The following equalities are mandatory:

- `ExpectedOldGenerationId` equals OLD `GenerationId`; `ExpectedNewGenerationId` equals NEW `GenerationId`; they are distinct.
- NEW `GenerationManifest.PreviousOutputManifestHash` equals the hash of OLD `previous-output-manifest/v2`, and that manifest names OLD's exact active M3U/XMLTV hashes and OLD `AcceptedStateHash`.
- NEW previous M3U/XMLTV objects, when present, carry `PreviousGenerationId=OLD` and are byte/hash exact snapshots of OLD accepted outputs. NEW active artifacts carry `GenerationId=NEW` and NEW `AcceptedStateHash`/`OutputManifestHash`.
- NEW decision records `AcceptedParentGenerationManifestHash` equal OLD `GenerationManifestHash`; a missing or different parent is stale and rejected.
- The new pointer names only NEW's generation manifest, accepted state, and output manifest. The previous pointer names only OLD's pointer bytes and is not a second current pointer.

For the first generation, all old pointer/generation/previous-output links are absent or null where the schema permits; there is no fabricated previous object and no null `previous-output-manifest/v2` object. A later transaction must never overwrite or reinterpret the first generation's lineage.

## 12. Mixed-generation rejection cases

The complete graph must resolve to one `GenerationId`, one `CandidateManifestHash`, and one coherent parent lineage. The following are explicit rejection cases, each `FAIL_CLOSED_RECOVERY_REQUIRED` with no automatic mutation:

1. Current pointer names NEW but its generation directory or manifest is OLD, or current pointer fields disagree with the generation manifest.
2. Current pointer is OLD while an output, accepted state, decision, or M3U/XMLTV file is taken from NEW.
3. Current pointer's `GenerationManifestHash`, `AcceptedStateHash`, or `AcceptedOutputManifestHash` does not hash to the named NEW bytes.
4. NEW accepted state or output manifest carries OLD `GenerationId`; an active artifact carries OLD `AcceptedStateHash`/`OutputManifestHash`; or an active XMLTV Generated/NotGenerated nullability rule is violated.
5. NEW `PreviousOutputManifestHash` names anything other than OLD's exact previous-output manifest, or a previous M3U/XMLTV snapshot has a different `PreviousGenerationId` or bytes.
6. NEW decision has a stale/missing `AcceptedParentGenerationManifestHash`, candidate hash, or decision hash, even if all NEW output bytes otherwise validate.
7. `accepted-lineup.json.previous` is absent when an old pointer existed, contains bytes different from the replaced pointer, names NEW, or has invalid OLD lineage.
8. Journal expected old/new pointer hashes or generation IDs disagree with actual pointer files, final generation, or the phase rank; a journal from a different transaction is never adopted.
9. Journal `OldJournalHash` does not equal the immediately prior authoritative journal, or `JournalHash` is invalid; a journal backup cannot resolve the mismatch.
10. A valid NEW pointer coexists with a malformed OLD previous generation, or cleanup would delete a generation still named by either current or previous pointer.
11. Any path, FileIdentity, byte length, or hash changes between validation and mutation, including a reparse-point or path-swap substitution.

## 13. Acyclic transaction ordering

Promotion follows this dependency order; each arrow is a required happens-before edge:

`lock and safe-input validation`
`-> candidate artifact bytes and hashes`
`-> decision bytes and hash`
`-> accepted active artifacts`
`-> previous-output snapshot (or first-generation absence)`
`-> output-manifest hash`
`-> accepted-state hash`
`-> complete generation manifest hash`
`-> staged new pointer hash`
`-> staged MutationRecords and Prepared JournalHash`
`-> Prepared journal publication`
`-> final generation directory move`
`-> GenerationPublished JournalHash/publication`
`-> old-pointer compare-and-swap to staged new pointer`
`-> PointerSwapped JournalHash/publication`
`-> reopen/hash/identity verification of the complete NEW graph`
`-> Committed JournalHash/publication`
`-> owner-only cleanup`

The semantic hash graph is independently acyclic: candidate bytes/manifests precede decisions; decisions and accepted artifacts precede the output manifest; the output manifest precedes accepted state because `AcceptedStateV2` carries `AcceptedOutputManifestHash`; previous output, output manifest, and accepted state precede the generation manifest; the generation manifest precedes the pointer. `JournalHash` hashes only the ordered Journal projection without itself and points backward through `OldJournalHash`; it does not participate in any semantic hash. `PointerHash` does not include the journal; the journal does not include its own hash or any hash that depends on the journal. Therefore no node hashes itself, a later node, or a journal that contains the node's own derived hash.

A transaction may retry an idempotent boundary only after revalidating all predecessor facts. It may never run a later boundary after a failed predecessor, publish a lower phase after a higher phase, mutate accepted output in place, or use rollback bytes to satisfy a missing predecessor. Cleanup is outside the authority graph and can only follow Committed.
