# Issue #109 narrow impact evidence

Issue #109 is limited to the EntryOutputSlice / EntryContentHash erratum. Full candidate-v8 registry activation is owned by #110 and is intentionally disabled by the production candidate builder.

## Proven by #109

- `EntryContentHash = H(candidate-entry-content/v1, exact complete serialized entry bytes)`.
- Slice bytes include the complete two-line M3U record and terminating LF.
- Slice coverage follows exact serialized `merged.m3u` artifact order.
- CandidateManifest entries remain canonical EntryId order independently of artifact byte order.
- Provider artifact-order mapping, duplicate-byte behavior, malformed-boundary rejection, contiguous/disjoint/EOF geometry, and frozen-v7 preservation.
- Default frozen-v7 deterministic evidence remains 2/2.

## Deferred to #110

End-to-end candidate-v8 evidence is not authoritative in #109. The following are deferred until the complete CandidateContractVersion registry migration:

- candidate-v8 BuildIdentity;
- candidate-v8 CandidateManifestHash;
- raw M3U/XMLTV candidate-version identity cascade;
- EntryId, fingerprint, guide, binding, collision, structural, change, and review identity impact;
- complete v7/v8 artifact impact matrix;
- successor end-to-end deterministic repeatability.

The production `Build-Candidate.ps1` path fails closed for candidate-v8 activation until #110 is complete. The private/bounded slice producer remains testable for the #109 contract without publishing a mixed-version candidate.

Independent domains remain unchanged, including `entry-id/v2`, `stream-fingerprint/v2`, `safe-tvg-name-fingerprint/v2`, and `candidate-entry-content/v1`.
