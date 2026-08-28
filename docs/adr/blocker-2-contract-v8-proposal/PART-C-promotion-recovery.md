## 5. Transaction state machine

The only authoritative current generation is the generation named by pointer/v2. Staging is never authoritative. Phases are ordered: `Prepared`, `GenerationPublished`, `PointerSwapped`, `Committed`.

1. Acquire exclusive `state/lineup-operation.lock`; validate candidate, decision, parent, and all hashes.
2. Write and verify complete generation under `state/.staging/<TransactionId>/generation/<GenerationId>/`.
3. Write/verify Prepared journal; current pointer remains OLD.
4. Atomically move the complete generation directory to `state/generations/<GenerationId>/`.
5. Write/verify GenerationPublished journal; pointer remains OLD.
6. Verify OLD pointer, atomically replace pointer and create exact previous pointer backup.
7. Write/verify PointerSwapped journal; pointer and generation are NEW.
8. Reopen and verify every linked state, decision, output manifest, M3U, and optional XMLTV byte/hash.
9. Write/verify Committed journal.
10. Delete staging and obsolete unreferenced backups/generations; cleanup failure is retryable and never rolls back NEW.

Each journal transition is staged, flushed, closed, reopened, schema/hash verified, then atomically replaced. JournalHash omits itself and uses `journal/v2`; OldJournalHash is null only before the first journal and otherwise equals the prior authoritative journal hash.

## 6. Recovery matrix

| Crash/failure | Authoritative result | Recovery |
|---|---|---|
| Before Prepared journal | OLD | remove only owned incomplete staging; malformed remnants fail closed |
| Prepared with generation staging | OLD | validate exact stage; retry or fail closed |
| GenerationPublished with final generation | OLD | validate final generation; retry pointer path or fail closed |
| After pointer replacement | NEW | validate pointer, previous pointer, generation, state, decision, and outputs; complete NEW or fail closed |
| Pointer damaged | neither trusted | fail closed; never infer from latest file |
| Journal damaged | neither trusted | fail closed; operator repair required |
| Generation missing/extra/altered | OLD or NEW pointer remains authoritative | fail closed; no guessed cleanup |
| Reparse/path substitution | current authority unchanged | fail closed before mutation |

No recovery path edits accepted output bytes. A valid current pointer plus valid referenced generation is authoritative even when cleanup remnants remain.

## 7. Fault boundaries

Every write/flush/reopen operation has a before/after durability boundary. Before pointer replacement, recovery is OLD. After pointer replacement, recovery is NEW. Directory move never alone changes authority. All partial staging, journal, pointer, and backup states either retry the exact transaction or fail closed. Mixed-generation state is invalid.
