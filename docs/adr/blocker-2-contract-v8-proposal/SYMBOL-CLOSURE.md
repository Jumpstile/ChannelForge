## 8. Successor symbol closure

ProposalId is `blocker-2-contract/proposal-4`. Proposed revision label is `blocker-2-contract/v8`. Neither is authority until freeze.

| Symbol | Owner | Scope | Definition |
|---|---|---|---|
| CandidateContractVersion | v7 retained candidate registry | candidate | `blocker-2-contract/v7` |
| AcceptanceContractVersion | proposal-4 registry | acceptance | `blocker-2-contract/v8-acceptance` |
| PointerV2 | PART-B | acceptance | pointer/v2 ordered projection |
| AcceptedStateV2 | PART-B | acceptance | accepted-state/v2 ordered projection |
| ActiveM3UV2 | PART-B | output | active-m3u/v2 ordered projection |
| ActiveXMLTVV2 | PART-B | output | active-xmltv/v2 ordered projection |
| PreviousM3UV2 | PART-B | previous output | previous-m3u/v2 ordered projection |
| PreviousXMLTVV2 | PART-B | previous output | previous-xmltv/v2 ordered projection |
| DecisionM3UV2 | PART-B | decision | decision-m3u/v2 ordered projection |
| DecisionXMLTVV2 | PART-B | decision | decision-xmltv/v2 ordered projection |
| GenerationManifestV2 | PART-B | generation | generation-manifest/v2 ordered projection |
| PreviousOutputManifestV2 | PART-B | previous output | previous-output-manifest/v2 ordered projection |
| TransactionPhase | PART-C | recovery | Prepared, GenerationPublished, PointerSwapped, Committed |
| JournalHash | PART-C | journal | H(journal/v2, ordered journal projection without JournalHash) |
| OldJournalHash | PART-C | journal | prior authoritative journal hash or null only before first publication |
| GenerationId | PART-C | generation | lowercase 32-byte operational identifier, carried by all generation bindings |

Retained v7 candidate symbols are not redefined. Every successor symbol has one owner, one scope, one exact domain, and one reference to its ordered schema. No successor file changes the v7 candidate manifest, candidate artifacts, or BuildIdentity.
