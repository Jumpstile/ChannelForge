## 1. Scoped semantic version registry

`CandidateContractVersion` is exactly `blocker-2-contract/v7` for all unchanged candidate schemas and artifacts. `AcceptanceContractVersion` is exactly `blocker-2-contract/v8-acceptance` for pointer, accepted-state, output, decision, generation, previous-output, and journal schemas defined by this proposal. Validation first checks scope, then exact version, then schema/projection, then hashes and links.

All bytes are UTF-8 without BOM. Canonical JSON is compact ordered JSON. Hashes are lowercase SHA-256 hex over `UTF8(domain) || 0x00 || canonical-bytes`. A self-hash field is omitted from its input projection.

## 2. Shared binding rules

Every accepted pointer names one `GenerationId`, `GenerationManifestHash`, `AcceptedStateHash`, and `AcceptedOutputManifestHash`. The generation manifest names exactly one candidate manifest, decision manifest, accepted state, output manifest, M3U, and optional XMLTV. Every named hash is recomputed from exact bytes before authority is declared. A missing required field is invalid; null is accepted only where explicitly stated; empty strings are invalid for IDs, hashes, paths, and domain strings.

## 3. Revision identity

RevisionContentId uses the frozen five-file procedure: ascending file-name manifest of exact bytes, then `H(contract-revision-content/v1, manifest)`. This proposal is not frozen and has no minted ContractRevisionId.

## 4. Hash dependency graph

Topological order: candidate manifest and candidate artifact hashes; decision-m3u/v2 and decision-xmltv/v2; accepted M3U/XMLTV artifact hashes; previous-output-manifest/v2 (or absent on first generation); accepted-state/v2; generation-manifest/v2; pointer/v2. JournalHash is computed independently from the prior journal projection and points backward through OldJournalHash only. PreviousStateHash is the prior generation's AcceptedStateHash and is never computed from current state. PointerHash, JournalHash, DecisionManifestHash, AcceptedStateHash, AcceptedOutputManifestHash, GenerationManifestHash, and OutputManifestHash each omit their own field. No node hashes a later node or itself; the graph is acyclic.
