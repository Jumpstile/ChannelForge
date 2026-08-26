## 8. Acceptance protocol and journal


Acceptance takes the exclusive lineup-operation.lock. The lock is opened with exclusive OS semantics, contains only a non-secret TransactionId and process start metadata, and is never trusted as state without a live handle. If a stale marker has no live handle it is diagnostic and may remain; a live handle blocks.

Before any authority mutation, the complete candidate, decision manifest, and parent generation are re-read from safe local handles, reparsed, schema-validated, and hash-verified. CandidateManifestHash, BuildIdentity, DecisionManifestHash, AcceptedParentGenerationManifestHash, and every source artifact hash must equal the requested values. This is the TOCTOU check. A path swap, reparse point, changed FileIdentity, changed bytes, missing parent, or changed candidate rejects before publication.

Write every generation file into state/.staging/<TransactionId>/generation/<GenerationId>/. For each file: create exclusively, write all bytes, Flush(true), close, reopen by safe handle, verify byte length, schema, semantic hash, and FileIdentity. After all files pass, stage the new pointer file and backup, if any, using the same process. The staged journal is state/.staging/<TransactionId>/accepted-lineup.journal.json.

Journal property order is Version, TransactionId, JournalStage, ExpectedOldPointerHash, ExpectedNewPointerHash, ExpectedOldGenerationId, ExpectedNewGenerationId, MutationRecords, OldJournalHash, JournalHash. Stages and ranks are None=0, Prepared=1, GenerationPublished=2, PointerSwapped=3, Committed=4. None has no authoritative journal and OldJournalHash=null. Prepared and later require OldJournalHash to be the lowercase 64-hex hash of the previous authoritative journal, or null only when no prior journal exists; after the first publication all later transitions use the prior non-null hash. JournalHash omits itself and hashes the rest in journal/v2. NewJournalHash is never stored as a field.

All schema-version validation, including IdentityRulesVersion mismatch validation and the allowed-version set used by the no-journal unknown-version rule, uses the central version registry in PART-A section 3.1. IdentityRulesVersion is therefore exactly the registry value lineup-history-v1; unknown values for every registry-controlled schema fail closed.

Journal publication is the same exact sequence for each transition: create staged bytes; Flush(true); close; reopen; verify bytes, schema, OldJournalHash, and JournalHash; verify journal path and parent are not reparse points; atomically replace state/accepted-lineup.journal.json with staged journal using File.Replace and backup state/accepted-lineup.journal.json.previous when an old journal exists, or File.Move when none exists; reopen authoritative journal and verify its hash; only then regard the new phase durable; delete the journal backup only after the authoritative reopen succeeds. A crash before replacement trusts the old phase; a crash after replacement trusts the new phase. Journal backups never replace accepted-state backups.

Exact operation sequence:
1. Acquire lock and validate candidate, decisions, parent, and paths.
2. Build and fully verify immutable generation stage.
3. Publish Prepared. Current pointer/generation remain OLD.
4. Directory.Move generation stage to state/generations/<GenerationId>/. Current pointer/generation remain OLD.
5. Publish GenerationPublished. Final new generation exists; pointer remains OLD.
6. Verify old pointer has the expected hash and new generation has the expected manifest. Atomically File.Replace the staged new pointer over state/accepted-lineup.json, backing the old pointer to state/accepted-lineup.json.previous; on first acceptance use File.Move only when current is absent. The new generation becomes NEW in one pointer operation; no output bytes are edited.
7. Publish PointerSwapped. Current pointer and generation are NEW; previous pointer is the exact OLD pointer when one existed.
8. Reopen and verify pointer, generation, state, decision, output manifest, M3U, optional XMLTV, all semantic hashes, and previous linkage.
9. Publish Committed. Only cleanup remains.
10. Delete the exact transaction staging directory, journal backup, and obsolete generation only when not referenced by current or previous pointer. Cleanup failure leaves NEW and is retryable; it never rolls back.

If an expected old hash differs, the current pointer is missing unexpectedly, the final generation name collides with non-identical bytes, or any authoritative file fails revalidation, acceptance stops and does not mutate the pointer. If failure occurs after Directory.Move but before GenerationPublished, recovery either completes the journal transition after validating the final generation or removes only the exact unreferenced new generation while preserving OLD; it never edits accepted output. If failure occurs after pointer replacement, recovery validates the new pointer and generation and completes NEW. If validation fails, it fails closed rather than guessing or reverting.

## 9. No-journal recovery: total ordered table

This table is first-match-wins and is exhaustive. It applies only when state/accepted-lineup.journal.json is absent. A valid journal is handled by the journal state machine, not this table.

1. A live exclusive lineup-operation.lock handle exists: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.
2. Any required path is a reparse point, UNC/SMB path, path-swap target, or cannot be safely opened: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.
3. Any journal file is malformed, unknown-version, hash-invalid, has impossible phase/identity, or has an orphan journal backup: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.
4. Any acceptance transaction remnant exists in state/.staging/<TransactionId>/, including generation staging, pointer staging, journal staging, pointer backup, journal backup, or an unowned transaction directory: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.
5. A final generation directory exists but is malformed, unknown-version, hash-invalid, contains an extra child, has invalid FileIdentity metadata, or is not byte-complete: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing. A valid unreferenced final generation is not an error and is eligible only for later owner cleanup.
6. accepted-lineup.json is absent while any accepted generation is referenced by an output/compatibility pointer, while accepted-lineup.json.previous exists, or while any active legacy output claims acceptance: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.
7. accepted-lineup.json exists but its PointerHash, generation ID, GenerationManifestHash, AcceptedStateHash, AcceptedOutputManifestHash, or referenced generation is invalid/mismatched: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.
8. accepted-lineup.json.previous exists without a valid current pointer, or its generation/linkage is invalid: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.
9. A valid current pointer exists but a required generation file is absent, has wrong bytes, wrong schema, wrong semantic hash, wrong output hash, wrong XMLTV nullability, or wrong previous linkage: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.
10. No current pointer, no previous pointer, no journal, no acceptance staging/remnant, no accepted generation, no active accepted output, and one or more valid immutable candidate namespaces exist: INITIAL_BASELINE_REQUIRED; preserve candidates and mutate nothing.
11. The same completely empty initial filesystem as row 10 but with zero candidate namespaces: INITIAL_BASELINE_REQUIRED; mutate nothing.
12. A valid current pointer/generation exists, an optional valid previous pointer/generation exists, and only valid candidate diagnostics, an unlocked diagnostic lock marker, or unreferenced valid generations exist: ACCEPTED_STATE_VALID; no automatic mutation.
13. Any filesystem state not matched by rows 1 through 12: FAIL_CLOSED_RECOVERY_REQUIRED; mutate nothing.

Candidate staging is not an accepted-state remnant. A final candidate remains valid only when its complete candidate manifest and referenced artifacts validate. A decision child under a valid final candidate does not invalidate that candidate; malformed decision staging is cleaned only by the owner of that decision transaction and otherwise causes fail-closed recovery for acceptance, not deletion of the candidate. No valid candidate is deleted during baseline classification.

## 10. Individually named fault hooks

Each hook is injected immediately at the named boundary. “OLD” means the old current pointer and old generation remain authoritative. “NEW” means the new pointer and complete new generation are authoritative. “FAIL_CLOSED” means no recovery mutation is allowed until an operator reruns the validated recovery procedure. Stage bytes are complete only after Flush and reopen/hash verification.

A01 StageWrite.GenerationManifest: before write absent/OLD; after injected failure partial or absent stage, no journal, no final generation, acceptance unchanged, restart FAIL_CLOSED.
A02 StageFlush.GenerationManifest: before flush partial/unflushed; after failure stage may contain partial bytes, no final generation, restart FAIL_CLOSED.
A03 StageReopenHash.GenerationManifest: staged bytes flushed but invalid/unverified, no final generation, restart FAIL_CLOSED.
A04 StageWrite.AcceptedState; A05 StageFlush.AcceptedState; A06 StageReopenHash.AcceptedState: same respective before/after states for accepted-state.json, OLD or FAIL_CLOSED, never NEW.
A07 StageWrite.AcceptedOutputManifest; A08 StageFlush.AcceptedOutputManifest; A09 StageReopenHash.AcceptedOutputManifest: same, OLD or FAIL_CLOSED.
A10 StageWrite.DecisionManifest; A11 StageFlush.DecisionManifest; A12 StageReopenHash.DecisionManifest: same, OLD or FAIL_CLOSED.
A13 StageWrite.M3U; A14 StageFlush.M3U; A15 StageReopenHash.M3U: same, OLD or FAIL_CLOSED.
A16 StageWrite.XMLTV; A17 StageFlush.XMLTV; A18 StageReopenHash.XMLTV: same when Generated; for NotGenerated no file is staged and the same no-file validation is required.
A19 JournalWrite.Prepared; A20 JournalFlush.Prepared; A21 JournalReopenHash.Prepared: no authoritative journal, complete generation stage may exist, current OLD; injected failure leaves no trusted journal and any stage remnant makes restart FAIL_CLOSED.
A22 JournalBeforeReplace.Prepared: staged journal verified, old authoritative journal unchanged, current OLD; failure leaves OLD and stage remnant, restart FAIL_CLOSED.
A23 JournalAfterReplace.Prepared: authoritative Prepared journal verified, stage consumed, generation stage complete, current OLD; failure/restart trusts Prepared and may remove only exact unused stage after validation, OLD.
A24 GenerationDirectoryMove.Before: Prepared journal, verified generation stage present, final generation absent, current OLD; failure leaves OLD and stage, recovery may retry exact Directory.Move or fail closed.
A25 GenerationDirectoryMove.After: Prepared journal, final generation complete, stage source absent, pointer OLD; because journal still says Prepared, restart validates final generation then either publishes GenerationPublished or returns FAIL_CLOSED; it never deletes a referenced/current generation.
A26 JournalBeforeReplace.GenerationPublished: final generation NEW but pointer OLD, staged journal verified, old journal authoritative; failure leaves final generation unreferenced and pointer OLD, restart FAIL_CLOSED unless exact Prepared recovery validates and publishes the next phase.
A27 JournalAfterReplace.GenerationPublished: final generation complete, pointer OLD, GenerationPublished authoritative; restart may atomically retry pointer promotion, OLD until that operation succeeds.
A28 PointerReplace.Before: GenerationPublished journal, staged pointer verified, current pointer exact OLD, previous absent or exact OLD backup target; failure leaves OLD, restart may retry, no output mutation.
A29 PointerReplace.After: current pointer exact NEW, previous pointer exact OLD when applicable, journal still GenerationPublished; restart validates both and publishes PointerSwapped, NEW; mismatch is FAIL_CLOSED.
A30 JournalBeforeReplace.PointerSwapped: pointer NEW/previous OLD, staged phase verified, journal still GenerationPublished; failure leaves NEW pointer with recoverable prior phase; restart validates and may publish PointerSwapped, NEW.
A31 JournalAfterReplace.PointerSwapped: pointer NEW, previous OLD, PointerSwapped authoritative; restart verifies and publishes Committed, NEW.
A32 VerifyCurrentPointer.Before: pointer NEW and complete generation, verification not yet run; failure leaves PointerSwapped or GenerationPublished authority, recovery retries verification, OLD/NEW according to the authoritative pointer, never mixed.
A33 VerifyCurrentPointer.After: verification complete and all hashes match; failure injection after verification leaves bytes unchanged and retryable, NEW.
A34 JournalBeforeReplace.Committed: pointer NEW/previous OLD, all generation hashes verified; failure leaves PointerSwapped authority, retryable, NEW.
A35 JournalAfterReplace.Committed: Committed authoritative, all accepted bytes NEW; any later failure is cleanup-only and NEW.
A36 CleanupDelete.GenerationStage.Before: Committed, final generation NEW, staging path present; failure leaves staging, NEW.
A37 CleanupDelete.GenerationStage.After: Committed, staging absent, final generation NEW; restart cleanup-only, NEW.
A38 CleanupDelete.PointerJournalBackup.Before: Committed, journal backup present; failure leaves backup, NEW.
A39 CleanupDelete.PointerJournalBackup.After: Committed, backup absent; restart cleanup-only, NEW.
A40 CleanupDelete.TransactionDirectory.Before: Committed, transaction directory present; failure leaves it, NEW.
A41 CleanupDelete.TransactionDirectory.After: Committed, transaction directory absent; restart cleanup-only, NEW.
A42 Verify.GenerationManifest.Before: pointer NEW, generation manifest not reopened; failure leaves NEW but recovery must reverify before declaring success.
A43 Verify.GenerationManifest.After: manifest verified, NEW.
A44 Verify.AcceptedState.Before: same pointer/generation NEW, state not reopened; failure leaves NEW and retryable verification.
A45 Verify.AcceptedState.After: state verified, NEW.
A46 Verify.OutputManifest.Before: output manifest not reopened; failure leaves NEW and retryable verification.
A47 Verify.OutputManifest.After: output manifest verified, NEW.
A48 Verify.M3U.Before: M3U not reopened; failure leaves NEW and retryable verification.
A49 Verify.M3U.After: M3U verified, NEW.
A50 Verify.XMLTV.Before: XMLTV not reopened when Generated; failure leaves NEW and retryable verification.
A51 Verify.XMLTV.After: XMLTV verified or NotGenerated validated, NEW.
A52 JournalStageWrite.GenerationPublished: old authoritative Prepared, staged new journal absent/partial, final generation present, pointer OLD; failure leaves stage and Prepared, restart FAIL_CLOSED until exact retry.
A53 JournalStageFlush.GenerationPublished: staged journal partial/unflushed, Prepared authoritative, final generation present, pointer OLD; failure leaves Prepared/OLD, restart FAIL_CLOSED.
A54 JournalStageReopenHash.GenerationPublished: staged journal flushed but invalid/unverified, Prepared authoritative, final generation present, pointer OLD; restart FAIL_CLOSED.
A55 JournalStageWrite.PointerSwapped; A56 JournalStageFlush.PointerSwapped; A57 JournalStageReopenHash.PointerSwapped: journal remains GenerationPublished, pointer is NEW if the swap already occurred, and restart validates the pointer then retries publication; malformed stage is FAIL_CLOSED and never changes pointer.
A58 JournalStageWrite.Committed; A59 JournalStageFlush.Committed; A60 JournalStageReopenHash.Committed: journal remains PointerSwapped, pointer/generation NEW; failure leaves NEW and retryable, never OLD rollback.

C01 CandidateStageWrite.Manifest; C02 CandidateStageFlush.Manifest; C03 CandidateStageReopenHash.Manifest: final candidate absent and accepted pointer unchanged; partial/invalid stage causes owner retry/delete only after exclusive ownership, otherwise FAIL_CLOSED for acceptance.
C04 CandidateStageWrite.M3U; C05 CandidateStageFlush.M3U; C06 CandidateStageReopenHash.M3U: same for candidate M3U.
C07 CandidateStageWrite.XMLTV; C08 CandidateStageFlush.XMLTV; C09 CandidateStageReopenHash.XMLTV: same for candidate XMLTV.
C10 CandidateStageWrite.ReviewJSON; C11 CandidateStageFlush.ReviewJSON; C12 CandidateStageReopenHash.ReviewJSON: same for review JSON.
C13 CandidateStageWrite.ReviewMarkdown; C14 CandidateStageFlush.ReviewMarkdown; C15 CandidateStageReopenHash.ReviewMarkdown: same for review Markdown.
C16 CandidateDirectoryMove.Before: verified complete candidate stage, final namespace absent, accepted pointer unchanged; failure leaves stage and OLD.
C17 CandidateDirectoryMove.After: final candidate namespace complete, stage source absent, accepted pointer unchanged; restart validates final candidate, leaves it immutable, and OLD.

Candidate hook numbers are stable identifiers, not execution-order numbers. The required candidate publication dependency order is: finalize BuildIdentity; finalize and hash candidate M3U/XMLTV (C04 CandidateStageWrite.M3U, C05 CandidateStageFlush.M3U, C06 CandidateStageReopenHash.M3U, then C07 CandidateStageWrite.XMLTV, C08 CandidateStageFlush.XMLTV, C09 CandidateStageReopenHash.XMLTV when XMLTV is Generated); finalize and hash candidate review JSON (C10, C11, C12); finalize and hash candidate review Markdown (C13, C14, C15); construct CandidateManifest with all ArtifactRecords; write, flush, reopen, hash-verify CandidateManifest (C01, C02, C03); independently validate every referenced artifact and the complete namespace; then perform the final namespace publication boundary (C16 and C17). The numeric ordering C01 through C17 does not define this execution order. Candidate success requires every required artifact, every ArtifactRecord, a valid CandidateManifestHash, independently verified artifact bytes and hashes, and passing final namespace validation. Failure at any candidate hook leaves no valid complete candidate namespace.

For every hook, no operation may infer bytes from cache, output, rollback, prior parser state, or a different namespace. A failed stage hook never mutates accepted authority. A failure after pointer replacement never rolls back by copying output; it validates and completes the new pointer or fails closed.

## 11. Test and acceptance gate

Before implementation can be accepted, tests must prove:

- canonical JSON bytes, escaping, property order, null/missing/empty/whitespace representation, enum ranks, and all hash domains;
- no semantic hash cycle and equal semantic hashes on different filesystems with different FileIdentity;
- exact M3U extraction, URL/logo/channel-number presence, escaping, order, duplicate representative, normalized collision EntryIds, and PR #100 pre-dedup guide collision behavior;
- exact XMLTV channel/programme occurrence cardinality, ordinals under source permutation, missing/empty/whitespace IDs, BindingKeys, programme identity/conflict, source-set projection, timestamps, repeated fields, category, episode and booleans, and exact XML bytes;
- complete BindingRecord, ReviewRecord, DecisionManifest, AcceptedState, AcceptedOutputManifest, GenerationManifest, and pointer schema projections;
- exact review coverage, decision predicates, stale candidate/parent rejection, IdentityRulesVersion mismatch, unresolved-review rejection, and deterministic accepted M3U/XMLTV reconstruction including KeepAcceptedEntry;
- Generated and NotGenerated XMLTV status and AcceptedXMLTVHash nullability;
- every no-journal row has exactly one classification;
- every A01-A60 and C01-C17 hook produces its specified before/after bytes, journal stage, path contents, restart classification, and OLD/NEW/fail-closed result;
- reparse/path swap/UNC rejection, exclusive locking, TOCTOU rejection, crash recovery, cleanup retry, and preservation of old accepted generation;
- no state, decision, or review artifact contains stream URLs, provider URLs, credentials, tokens, account IDs, raw XMLTV, absolute paths, or cache content;
- Build-Lineup remains candidate-only and acceptance is the only operation that can replace the current accepted pointer.

The implementation must be one bounded PR only if these tests can be implemented without changing runtime/provider/scheduler/UI scope. This contract is not release evidence.
