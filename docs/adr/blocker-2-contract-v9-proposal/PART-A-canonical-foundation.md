# Candidate v9 canonical foundation

The successor candidate registry adds exactly one candidate semantic domain:
`candidate-entry-content/v1`. It is distinct from `active-m3u/v2`, which hashes
complete accepted `merged.m3u` artifacts. Candidate and acceptance registries
remain disjoint: candidate surfaces use `blocker-2-contract/v8` in this
proposal; acceptance surfaces remain `blocker-2-contract/v8-acceptance`.

`EntryContentHash = H(candidate-entry-content/v1, exact slice bytes)`.
The domain prefix is UTF-8, followed by one zero byte, followed by the exact
slice bytes. No path, offset, length, JSON, or enclosing manifest participates.
The algorithm is SHA-256 and the result is lowercase hexadecimal.
