# Guide comparison intelligence

`Compare-ChannelForgeXmltvGuides` is a deterministic, report-only comparison prototype. Its inputs are `ChannelForgeExternalEvidenceObservation/v1` objects created by `ConvertTo-ChannelForgeExternalEvidenceObservation`; XMLTV adapters and acquisition are outside this boundary. `Programme` and `GuideEvidenceRecord` are not neutral external-ingestion contracts.

## Scope and ownership

The caller supplies one playlist context, explicit evaluation time, optional expected-coverage windows, existing durable channel bindings, and previously accepted knowledge for comparison. The comparer owns candidate event correlations, ambiguity, freshness assessments, conflicts, coverage gaps, overlap findings, assignment anomalies, and historical-knowledge comparisons. It does not create or change durable bindings, confidence policy, accepted knowledge, XMLTV, playlists, or lineup state.

Only observations with an explicit `SourceScoped` or `Shared` binding context for the requested playlist can participate in comparison. `Shared` means explicitly shared by the observation contract; a source bound to a different playlist is out of scope. Unbound evidence remains in provenance and is reported, never assigned by inference. Existing durable channel bindings may map a source channel reference to a `ChannelId`; suspicious `ChannelAssignment` or `Network` fields are compared against that mapping and cannot retarget it.

## Correlation and findings

Candidate events are compared only within the same resolved channel scope. Correlation uses explicit source-record or provisional-subject hints when compatible, otherwise normalized title and participant evidence plus a bounded near-time interval. Correlated candidates are selected only when each side has a unique reciprocal candidate; ambiguous candidate sets are reported without choosing an enumeration-order winner. Start and stop shifts are assessed after event correlation, so a time change is not automatically treated as a different event. Stable identifiers and canonical ordering make equivalent input sets produce equivalent JSON and Markdown reports.

Findings include exact agreement, harmless metadata variation, title and participant conflicts, separate start/stop time conflicts, stale or future-dated observations, source-unavailable and rejected evidence, out-of-scope and unbound evidence, explicit-window coverage gaps, missing programmes only where another source has declared covering scope, benign duplicate overlaps, correlated time-shift overlaps, material overlaps, suspicious assignments, and conflicts with accepted historical knowledge. Missing coverage is never inferred without a supplied expected window. Source-data, observation, and fetch timestamps remain distinct; freshness uses source-data time when present and fetch time only as a fallback, relative to the caller's explicit evaluation time.

## Safety

The report is `REPORT_ONLY` and `ReadOnly`; it declares `CanPublish = false` and records no accepted-state or accepted-knowledge mutation. Every correlation, assignment assessment, and accepted-knowledge comparison is diagnostic evidence only. No finding automatically accepts evidence, modifies existing channel bindings, publishes XMLTV, or changes a lineup. The caller remains responsible for any separately authorized review or acceptance workflow.
