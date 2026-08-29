# Issue #102 accepted-state implementation

Status: local implementation/review work only on `review/issue-102-accepted-state-v9`. The v9 freeze itself did not resume Issue #102; #102 remained held until the #110 Candidate Version Registry Migration completed. #110 is now integrated, and the later #102 restart authority clears that implementation hold. This branch still carries no merge or release authorization until its own gates pass.

## Scope

The acceptance projection module in `src/ChannelForge/Private/New-ChannelForgeAcceptanceProjection.ps1` constructs and validates the pure data surfaces required by Issue #102:

- v8-acceptance subordinate M3U/XMLTV decision projections and aggregate `DecisionManifest`;
- accepted-state and accepted-output-manifest projections, including semantic self-hash rules;
- active and previous M3U/XMLTV descriptors with exact Generated/NotGenerated nullability;
- exact `KeepAcceptedEntry` reconstruction from verified prior bytes and the frozen `candidate-entry-content/v1` slice hash domain;
- candidate-to-accepted entry comparison, deterministic `ChangeRecord` ordering, accepted binding selection, and fail-closed `ReviewRecord` construction;
- first-generation and later-generation lineage validation.

The implementation does not publish a pointer, replace accepted files, advance a journal, promote a generation, recover a transaction, or add runtime/provider/scheduler/UI behavior. Those operations remain outside this Issue #102 change.

## Authority and versions

The frozen v9 EntryOutputSlice erratum is preserved byte-for-byte under [`docs/adr/blocker-2-contract-v9-proposal`](blocker-2-contract-v9-proposal). Candidate inputs use `blocker-2-contract/v8`; acceptance projections use `blocker-2-contract/v8-acceptance`. The v9 revision identity is recorded by its freeze record and was verified before source edits.

## Verification

`tests/unit/Issue102AcceptedState.Tests.ps1` covers deterministic field order and hashes, Generated/NotGenerated XMLTV vectors, exact prior-slice reconstruction, candidate/accepted comparison, and invalid actionable review cardinality. Full repository gates are recorded in the local delivery packet for this branch.
