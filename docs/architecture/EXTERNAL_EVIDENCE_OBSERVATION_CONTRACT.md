# ChannelForgeExternalEvidenceObservation/v1

This contract is the neutral adapter-to-intelligence boundary. It describes what an external source observed, not what ChannelForge accepts as canonical.

## Ownership

Adapters own source parsing, adapter/parser identity, source-scoped references, normalized observed field values, source-data/fetch facts, bounded availability status, and field-level provenance. They do not assign canonical event/channel identity, confidence, contradiction groups, or acceptance state.

Guide Intelligence owns event correlation, canonical identity, binding assessment, freshness policy, coverage and overlap findings, suspicious assignment, contradiction groups, confidence, review disposition, enrichment proposals, and candidate/accepted-state policy.

`Programme` remains normalized XMLTV/domain state. `GuideEvidenceRecord` remains a Guide Intelligence evidence/readiness projection. Neither is the neutral external adapter contract.

## Time facts

`SourceDataTimeUtc`, `ObservationTimeUtc`, and `FetchTimeUtc` are independent optional facts. Evaluation time is deliberately excluded and belongs to Guide Intelligence assessment output. Fetch time is excluded from semantic `ObservationId` identity.

## Identity and safety

`ProvisionalSubjectKey` and `SourceChannelReference` are source-scoped hints only. They cannot create or redefine ChannelForge event or channel identities. Observation identity is deterministic and hashes a canonical projection that excludes fetch and observation timestamps. Sensitive URLs, credentials, tokens, private paths, cache validators, and unsafe raw diagnostics are excluded.

The schema is intentionally generic for sports and non-sports schedules. Sports-specific fields such as odds, predictors, team records, and league-specific taxonomy are not v1 fields.
