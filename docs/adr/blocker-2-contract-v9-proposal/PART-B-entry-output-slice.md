# EntryOutputSlice successor semantics

## Scope

`EntryOutputSlice` is a candidate-stage field. This proposal amends only its
content-hash meaning; all v8 acceptance and promotion domains remain unchanged.
The successor candidate version is `blocker-2-contract/v8`.

## EntryOutputSlice

The exact ordered fields are `RelativePath,ByteOffset,ByteLength,EntryContentHash`.
`RelativePath` MUST equal `merged.m3u`. `ByteOffset` and `ByteLength` are unsigned
byte counts into the exact UTF-8 candidate `merged.m3u` artifact. `ByteLength`
MUST be positive. The checked interval is `[ByteOffset, ByteOffset+ByteLength)`;
the addition MUST be overflow-safe and MUST be less than or equal to the exact
artifact byte length. A slice MUST contain the complete two-line M3U entry and
its terminating LF. Slices for retained entries MUST be disjoint and together
cover exactly the retained entry records in EntryId order.

`EntryContentHash` is the lowercase SHA-256 digest of the exact slice bytes,
without path, offset, length, JSON, or any surrounding record. Its dedicated
hash domain is `candidate-entry-content/v1`:
`H(candidate-entry-content/v1, exact slice bytes)`.
The same bytes retain the same hash when copied into an accepted `merged.m3u`;
its containing artifact hash is separately computed under `active-m3u/v2`.

A producer MUST fail closed on missing fields, invalid path, non-integer values,
zero length, overflow, out-of-bounds ranges, malformed entry boundaries, or a
hash mismatch. A consumer implementing `KeepAcceptedEntry` MUST first verify
the complete prior accepted M3U descriptor, then verify and extract this exact
interval, then recompute this domain-separated hash and require equality before
using the bytes. It MUST NOT use current provider input, candidate approximation,
cache, display-name matching, tvg-id similarity, or compatibility output.

The path is metadata only and is not included in the hash input. The slice hash
is portable because it authenticates content bytes independently of the artifact
that contains them.
