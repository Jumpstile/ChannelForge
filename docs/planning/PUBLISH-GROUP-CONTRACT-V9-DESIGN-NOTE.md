# Publish group step and candidate contract (file V9, version v10): design note (issue #191)

Status: design only. No code, tests or data were changed.

File name note: the file name says V9 as the task asked. The candidate version proposed inside is v10, for the reason in section 2.

## 1. Problem and current blocker

Many provider channels have an empty `group-title`. IPTV apps show playlist groups, so those channels land in one unnamed bucket. ChannelForge has a category list (`data/rules/categories.json`, read by `Get-ChannelForgeCategoryFromText`) that could fill the empty group, but filling it today breaks the candidate manifest.

The mechanism that blocks it:

- `Export-ChannelForgeM3UPlaylist` writes entry bytes with `ConvertTo-ChannelForgeM3UEntryBytes`. Before that call it swaps in the published logo (`Get-ChannelForgePublishLogo`). It does not change `Group`.
- `ConvertTo-ChannelForgeCandidateManifest` (v8 branch) rebuilds the same bytes from the raw channel, searches the M3U bytes for them at a moving cursor, and throws `FAIL_CLOSED: successor slices are not contiguous.` on any difference.
- It stores `ByteOffset`, `ByteLength` and `EntryContentHash` (`candidate-entry-content/v1`) per entry, and a per-entry `GroupTitle` projected from the raw occurrence.
- If the exporter fills a group and the manifest does not, every filled entry fails closed. If only the manifest is patched ad hoc, the two copies of the logic drift.

The previous lane (S191W) stopped for this reason and asked for a contract version first.

## 2. Proposed shape

### One shared private step

Add one private function, `Get-ChannelForgePublishGroup`. It has the same shape as `Get-ChannelForgePublishLogo`: channels in, one result per channel out, never drops a channel, never changes the channel.

Each result has:

- `RawGroup`: what the provider sent.
- `Group`: what gets published.
- `Source`: one of `Provider`, `Pin`, `Config`, `CategoryList`, or `None`.
- `ReviewCandidates`: category names when two or more match, otherwise empty.

Both callers use it:

- The exporter calls it next to the logo step and writes the entry bytes with the published group, the same way it does for the logo today.
- The manifest builder calls it with the same inputs, then calls `ConvertTo-ChannelForgeM3UEntryBytes` on a channel carrying the published group. Bytes, slices, offsets and `EntryContentHash` come from one rule, so they agree.

The manifest already receives `GroupDefaultLogo` and `LogoPin` for the logo step. It needs the group inputs the same way (see the new parameter below).

### Version string

The new candidate version is `blocker-2-contract/v10`.

Why not `v9`: `blocker-2-contract/v9` is already the frozen revision id of the EntryOutputSlice erratum (`docs/adr/blocker-2-contract-v9-proposal`, `scripts/Verify-ContractRevisionId.ps1`). That revision carries candidate version v8. A test in `tests/unit/Issue109EntryContentHashContract.Tests.ps1` also uses `blocker-2-contract/v9` as an unsupported candidate version that must be rejected. Reusing the name would clash with both. Candidate v10 skips the number, so neither is touched. The matching frozen revision id would be chosen at freeze time (owner decision 1).

### What the manifest records per entry

Existing fields stay. For `blocker-2-contract/v10` each entry gains exactly two fields:

| Field       | Meaning                                                     |
| ----------- | ----------------------------------------------------------- |
| RawGroup    | Group exactly as the provider sent it (redacted like today) |
| GroupSource | `Provider`, `Pin`, `Config`, `CategoryList` or `None`       |

Changed meaning, no new name:

- `GroupTitle` is the published group in v10 (it is the raw group in v7 and v8).
- `PresentationFingerprint` hashes the published group in v10, because it already hashes the published logo and the presentation is what the app shows.
- `EntryOutputSlice` (`ByteOffset`, `ByteLength`, `EntryContentHash`) covers the bytes that were really written, filled group included.

The new fields are `RawGroup` and `GroupSource`. Two fields, nothing else.

Why filled: `GroupSource` answers it. `Provider` means the provider group was kept (nothing filled). `Pin` and `Config` mean an owner choice won. `CategoryList` means one category matched. `None` means the group stays empty.

A review line is not stored per entry. It goes in the candidate review output (section 4).

Today no owner pin or config for a group exists in the code (searched `src` for group pin and override helpers; only the logo pin and group-default-logo exist). The step must accept an optional `GroupPin` map keyed like `LogoPin` (by TvgId). Where that map comes from is owner decision 3.

## 3. Backward compatibility

### v7 and v8

- `CandidateContractVersion` still defaults to v7. v7 and v8 keep their exact code paths and values.
- The shared step runs for v7 and v8 callers too (the exporter is shared), but with group filling switched off. The step then returns the raw group unchanged, so the bytes are identical to today.
- Rule: when no group is filled, bytes and hashes are identical to today, for every version. A v10 candidate with no fill has the same `M3U` bytes and the same `EntryContentHash` values as the v8 candidate of the same input. Only the version string and the two new fields differ.

### Consumers that stay untouched

- Entry bytes and hashes: `Get-ChannelForgeKeepAcceptedEntry` (in `New-ChannelForgeAcceptanceProjection.ps1`) slices prior M3U bytes and compares `candidate-entry-content/v1` over those bytes. It never parses the group, so a filled group is just bytes to it.
- Guide-id contract v1.0: the guide id comes from the TvgId and the XMLTV binding, not from `group-title`. The M3U entry id (`Get-ChannelForgeRawM3UProjection`) hashes the raw projection, which reads `RawGroupTitle` (falling back to `Group`). The raw projection stays raw, so `EntryId` and `RawM3UOccurrenceDigest` do not move. No channel is dropped and `guide: null` stays.
- Raw projections: unchanged. They are built before the publish step and never see the filled value.
- Transport and trust: they move bytes and check hashes of whole files. A filled group is inside the bytes that are already hashed.
- XMLTV: not touched by this note. `ConvertTo-ChannelForgeXmltvBytes` writes `<category>` from programme categories; whether any manifest hashes XMLTV bytes is unverified (section 6).

### Consumers that are touched (smallest change each)

- `Assert-ChannelForgeCandidateVersion` in `New-ChannelForgeAcceptanceProjection.ps1` has a hard-coded allow list of v7 and v8. Add v10. Without this a v10 manifest fails closed at acceptance.
- Every `ValidateSet('blocker-2-contract/v7','blocker-2-contract/v8')` on the reader, importer and projection functions needs v10 added. These are the files found by searching `blocker-2-contract/v8` in `src` and `scripts`. The change is one string each.
- Decision manifest and accepted state compare `StreamFingerprint` and `PresentationFingerprint`. In the manifest builder both hash `Version = $CandidateContractVersion` for v8 and later (only v7 uses fixed strings). A new version string therefore changes both fingerprints for every entry, so the first v10 build against a v8 accepted state would classify the whole lineup as changed (`StreamAndPresentationChanged`, with review records), not just filled channels. Fix: in v10 keep the fixed internal fingerprint version strings (as v7 does: `stream-fingerprint-v2`, `safe-tvg-name-fingerprint-v2`). Then only the presentation hash of filled entries moves, because it now hashes the published group. Owner decision 4.
- `Get-ChannelForgeGuidedSetupProposal`, `New-ChannelForgeEnrolledCandidate` and `Build-My-Lineup.ps1` pick v7 or v8 explicitly. They get v10 only when the owner turns the feature on; they are not switched by default.

## 4. Review rule

The decision comes from `Get-ChannelForgeCategoryFromText`, which already returns one of three results. The shared step applies it in this order:

1. A non-empty provider group is kept. Never overwritten. `Source = Provider`.
2. Otherwise an owner pin for the channel wins. `Source = Pin`.
3. Otherwise a config rule wins. `Source = Config`.
4. Otherwise ask the category list, using the display name as the text:
   - exactly one match: fill with that name, `Source = CategoryList`;
   - two or more matches: no fill, group stays empty, `ReviewCandidates` lists the names;
   - none: no fill.

For two or more matches the candidate review output gets one plain line per channel, for example: `Channel Example One could match Hockey and Football. Pick one group for it.` The line is built from invented-style data only in tests; in real use it carries the channel's own name.

`Get-ChannelForgeCategoryFromText` already treats "existing name set" as a win, so rule 1 is enforced twice by design.

## 5. Test plan

Only things a user sees or loses. All fixtures use `example.invalid` and invented channel names.

1. Fill works: a channel with an empty group and the name "Example Hockey Night" is published with `group-title="Hockey"`. The manifest `GroupTitle` is `Hockey`, `RawGroup` is empty, `GroupSource` is `CategoryList`.
2. Existing group never overwritten: a channel with group `My Sports` and a hockey-looking name keeps `My Sports`. `GroupSource` is `Provider`.
3. Pin and provider win: a pinned channel gets the pinned group even when the category list would pick another one.
4. Two matches: the group stays empty, one review line is written, the channel is still published.
5. v8 candidate still verifies byte for byte: same input as today gives the same M3U bytes, the same offsets and the same `EntryContentHash` values (compare to a stored v8 result).
6. v10 candidate with a fill verifies: the slice at `ByteOffset` for `ByteLength` hashes to `EntryContentHash`, and slices cover the whole file.
7. Tampering fails closed: change the filled group text in the M3U bytes after the build. Acceptance throws `FAIL_CLOSED` and nothing is published.
8. No fill gives identical hashes: v10 with nothing to fill has the same `EntryContentHash` list as v8.

Not planned: tests of the helper's internals, of parameter wiring, or of the category list contents.

## 6. Risks and what was not verified

Risks:

- The exporter is called from three places (`New-ChannelForgeCandidateProposal`, `New-ChannelForgeCandidateProposalFromSourceSet`, `scripts/Build-Lineup.ps1`). If one caller forgets the group inputs, that path publishes unfilled groups while the manifest expects filled ones and fails closed. Failing closed is safe, but it would be a confusing error.
- The source-set path accepts only v7 today (`ValidateSet('blocker-2-contract/v7')`). Filling groups there needs its own decision (owner decision 5).
- A frozen contract file set exists for v9 under `docs/adr`. A v10 freeze needs its own ADR folder and `RevisionContentId`, as v8 and v9 did. That is governance work and is not sized below.
- Category matching is word based on the display name. Wrong single matches are possible. The review rule only covers multiple matches.
- Without the fixed fingerprint strings (section 3), the first v10 build flags every accepted entry for review. With them, only filled entries change.

Not verified (not run, not read):

- Whether any manifest or accepted state hashes XMLTV bytes.
- Whether any other test pins `group-title` bytes of the exporter.
- No code or test was run. No parse check was needed (markdown only).
- Behavior of `Find-ChannelForgeCategoryWord`; only the caller was read.

Size estimate for the code slice, code plus tests: about 220 to 280 changed lines.

| Part                                        | Lines |
| ------------------------------------------- | ----- |
| Shared step `Get-ChannelForgePublishGroup`  | 50    |
| Exporter and manifest builder wiring        | 50    |
| Version allow lists and ValidateSet entries | 25    |
| Review line in candidate review output      | 25    |
| Tests (8 cases above, shared fixtures)      | 100   |

Recommendation: split in two.

- Slice 1: the shared step used by exporter and manifest builder, with fill switched off. Prove the v8 hashes do not move. This is safe to ship alone and removes the drift risk.
- Slice 2: v10 version string, the two new fields, the fill, the review line and the allow list changes.

Each slice stays under the 300 line budget, and slice 1 can be reviewed by byte comparison alone.

## 7. Owner decisions

1. Version name: use `blocker-2-contract/v10` for the candidate version, because v9 is already taken by a frozen revision. Recommended: yes.
2. Fill rule: fill only when the category list finds exactly one match, and never touch a group the provider already set. Recommended: yes.
3. Owner pins and config for groups: today none exist. Recommended: ship the fill without them first, keep the step ready to accept a pin map, and add pins in a later slice.
4. First-build noise: a new version string would flag the whole lineup as changed. Recommended: keep the fixed fingerprint version strings so only channels whose group was filled show as changed. That change is real and should stay visible.
5. Source-set path: it only supports v7 today. Recommended: leave it alone in this work and fill groups on the v8-based paths first.
6. Split: build the shared step first and the fill second. Recommended: yes.
