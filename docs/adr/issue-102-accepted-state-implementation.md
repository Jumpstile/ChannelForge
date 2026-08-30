# Issue #102 accepted-state implementation

Status: local implementation/review work only on `review/issue-102-accepted-state-v9`. The v9 freeze itself did not resume Issue #102; #102 remained held until the #110 Candidate Version Registry Migration completed. #110 is now integrated, and the later #102 restart authority clears that implementation hold. This branch still carries no merge or release authorization until its own gates pass.

## Scope

The acceptance projection module in `src/ChannelForge/Private/New-ChannelForgeAcceptanceProjection.ps1` constructs and validates the pure data surfaces required by Issue #102. The exported `New-ChannelForgeAcceptance` function is the production acceptance boundary: it validates the complete decision manifest before producing accepted entries or accepted bindings.

- v8-acceptance subordinate M3U/XMLTV decision projections and aggregate `DecisionManifest`;
- accepted-state and accepted-output-manifest projections, including semantic self-hash rules;
- active and previous M3U/XMLTV descriptors with exact Generated/NotGenerated nullability;
- exact `KeepAcceptedEntry` reconstruction from verified prior bytes and the frozen `candidate-entry-content/v1` slice hash domain;
- candidate-to-accepted entry comparison, deterministic `ChangeRecord` ordering, accepted binding selection, and fail-closed `ReviewRecord` construction;
- first-generation and later-generation lineage validation;
- required `IncludedCandidateEntryIds` and `ExcludedCandidateEntryIds` partition fields. Missing fields are invalid; they are never reconstructed from decision records.

The implementation does not publish a pointer, replace accepted files, advance a journal, promote a generation, recover a transaction, or add runtime/provider/scheduler/UI behavior. Those operations remain outside this Issue #102 change.

## Authority and versions

The frozen v9 EntryOutputSlice erratum is preserved byte-for-byte under [`docs/adr/blocker-2-contract-v9-proposal`](blocker-2-contract-v9-proposal). Issue #116's current corrective attestation is the `RCID byte-source integrity` entry in [`FREEZE-RECORD.md`](blocker-2-contract-v9-proposal/FREEZE-RECORD.md): `ContractRevisionId = blocker-2-contract/v9` and `RevisionContentId = 1396db7098973a1ef7469e851d308dc7aad47a8cd61a0d675e85717e7ae84192`. Candidate inputs use `blocker-2-contract/v8`; acceptance projections use `blocker-2-contract/v8-acceptance`. This rebind changes authority metadata only; it does not change the acceptance implementation or frozen semantics.

## Verification

`tests/unit/Issue102AcceptedState.Tests.ps1` covers deterministic field order and hashes, Generated/NotGenerated XMLTV vectors, exact prior-slice reconstruction, candidate/accepted comparison, and invalid actionable review cardinality. Full repository gates are recorded in the local delivery packet for this branch.
