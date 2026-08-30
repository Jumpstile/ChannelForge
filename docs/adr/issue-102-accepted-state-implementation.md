# Issue #102 accepted-state implementation

Status: Issue #102 implementation is integrated on `main` at `2cf8051275fb6d9f34d68fc12c18a631fde026dd`; its pure acceptance projections remain the input boundary for Issue #103. This record is historical and nonnormative.

## Scope

The acceptance projection module in `src/ChannelForge/Private/New-ChannelForgeAcceptanceProjection.ps1` constructs and validates the pure data surfaces required by Issue #102. The exported `New-ChannelForgeAcceptance` function is the production acceptance boundary: it validates the complete decision manifest before producing accepted entries or accepted bindings.

- v8-acceptance subordinate M3U/XMLTV decision projections and aggregate `DecisionManifest`;
- accepted-state and accepted-output-manifest projections, including semantic self-hash rules;
- active and previous M3U/XMLTV descriptors with exact Generated/NotGenerated nullability;
- exact `KeepAcceptedEntry` reconstruction from verified prior bytes and the frozen `candidate-entry-content/v1` slice hash domain;
- candidate-to-accepted entry comparison, deterministic `ChangeRecord` ordering, accepted binding selection, and fail-closed `ReviewRecord` construction;
- first-generation and later-generation lineage validation;
- required `IncludedCandidateEntryIds` and `ExcludedCandidateEntryIds` partition fields. Missing fields are invalid; they are never reconstructed from decision records.

The implementation does not publish a pointer, replace accepted files, advance a journal, promote a generation, recover a transaction, or add runtime/provider/scheduler/UI behavior. Issue #103 now owns those filesystem publication and recovery operations in separate runtime commands; this Issue #102 slice remains pure.

## Authority and versions

The frozen v9 EntryOutputSlice erratum is preserved byte-for-byte under [`docs/adr/blocker-2-contract-v9-proposal`](blocker-2-contract-v9-proposal). Issue #116's current corrective attestation is the `RCID byte-source integrity` entry in [`FREEZE-RECORD.md`](blocker-2-contract-v9-proposal/FREEZE-RECORD.md): `ContractRevisionId = blocker-2-contract/v9` and `RevisionContentId = 1396db7098973a1ef7469e851d308dc7aad47a8cd61a0d675e85717e7ae84192`. Candidate inputs use `blocker-2-contract/v8`; acceptance projections use `blocker-2-contract/v8-acceptance`. This rebind changes authority metadata only; it does not change the acceptance implementation or frozen semantics.

## Verification

`tests/unit/Issue102AcceptedState.Tests.ps1` covers deterministic field order and hashes, Generated/NotGenerated XMLTV vectors, exact prior-slice reconstruction, candidate/accepted comparison, and invalid actionable review cardinality. Issue #103 adds the immutable generation publication and restart-recovery boundary without changing these projections.
