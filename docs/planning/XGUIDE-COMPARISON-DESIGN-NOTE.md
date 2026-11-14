# Design note: cross-guide comparison of overlapping guides (issue #175 step 8, slices 1 to 3)

Contract: xguide-compare/v1 (report only).

This is a design note. It adds no product code and no tests. It comes from reading this tree on Nov 14, 2026, plus the text of issue #175. Anything not confirmed is under "Not verified".

## The problem

The owner enrolls two or more XMLTV guides that cover the same channels. He cannot see where they disagree: one guide lacks a channel, one shows another start time or title for the same slot, one is stale. He finds out only in the player. He needs to SEE the disagreement, with a plain reason, before he accepts a build.

## What exists today

| File                                                                                                                                                    | What it does                                                                                                                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Private\New-ChannelForgeCandidateProposalFromSourceSet.ps1, Public\New-ChannelForgeSourceSetCandidateProposal.ps1, Public\Get-ChannelForgeSourceSet.ps1 | Source-set candidate path (steps 1 to 6, shipped). Playlists are ordered by `Priority`, then `SourceId`. Guides and bindings are passed in.                                                                                                                                                                                                               |
| scripts\Build-Lineup.ps1 (XMLTV block, about lines 696 to 800)                                                                                          | Imports each enabled XMLTV source with `Import-ChannelForgeConfiguredXmltvSource` into one `$allProgrammes` list of `Programme` objects (`SourceId`, `ChannelId`, `Start`, `End`, `Title`). Then `Merge-ChannelForgeXmltvProgrammes`, then `Resolve-ChannelForgeM3UXmltvBinding`.                                                                         |
| Public\Merge-ChannelForgeXmltvProgrammes.ps1                                                                                                            | Groups by source-scoped binding key (SourceId plus channel id) and exact interval. Identical content merges (`DuplicateMerged`). Same interval with different content is a `Conflict`. A conflict makes the build stop with "XMLTV merge contains conflicts". Different intervals are not compared. Guides are never compared with each other by channel. |
| Public\Resolve-ChannelForgeM3UXmltvBinding (in the module)                                                                                              | Exact tvg-id to XMLTV channel-id binding. Ambiguity stays review-needed (`UNBOUND`, `REVIEW NEEDED`, `XMLTV-ONLY` lines in `lineup-plan.md`).                                                                                                                                                                                                             |
| scripts\Build-Lineup.ps1 `Get-ChannelForgeGuideEnd`, `Get-ChannelForgeEpgCoverage`                                                                      | Latest programme end per source (`GuideEndsUtcBySource`), a 48 hour warning, and first start and last stop per bound channel. This is the only freshness check today. It is not shown per guide in the Markdown.                                                                                                                                          |
| Public\Compare-ChannelForgeXmltvGuides.ps1 (tests: XmltvGuideComparison.Tests.ps1, DeterministicComparisonEvidence.Tests.ps1)                           | Pure comparison over `ChannelForgeExternalEvidenceObservation/v1` objects. Finds `TitleConflict`, `TimeConflict`, `ExactAgreement`, stale and unavailable sources, with a near-time window (default 15 minutes) and a freshness TTL. Nothing in the build calls it. Its input is the heavy observation shape (field lists, adapter ids, provenance).      |
| Private\Get-ChannelForgeCategorySummaryLines.ps1 and the "Category check" block in Build-Lineup.ps1                                                     | The pattern to copy: pure lines function, one call per build, a failure is one warning, report only.                                                                                                                                                                                                                                                      |

Where the owner reads today: `output\reports\lineup-plan.md`. Nothing there says that two guides disagree.

What is NOT true today, so nobody assumes it: the merge does not "pick one guide by priority" per channel. It keeps each guide's programmes under that guide's own binding key, and the M3U to XMLTV step picks the exact binding. [INFERENCE] The silent pick the owner fears happens in that binding step and in the player, when two guides carry the same channel id. Slice 1 reports that overlap without changing it.

## Contract xguide-compare/v1

### Inputs

- The `Programme` list the build already holds (`$allProgrammes`): `SourceId`, `ChannelId`, `Start`, `End`, `Title`.
- The build time (`$BuildTimeUtc`, already in the build).
- The list of enabled guide source ids and their import outcome (`$xmltvAcquisitionStatuses`, already in the build), so a guide that gave no programmes is still named.
- Nothing else. No network, no files read again, no M3U needed.

### What is compared

Only guides that share a channel. Channel key = `RawChannelId` when non-empty, else `ChannelId`, compared ordinally with no trimming of its own (the same rule `Resolve-ChannelForgeM3UXmltvBinding` uses). Two guides "share" a channel when both have that channel id.

| Check            | Rule                                                                                                                                                                                                                                                                                 | Owner reads                                                               |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------- |
| Channel presence | A channel id carried by at least one guide but missing from another enabled guide that carries other channels.                                                                                                                                                                       | `channel X: in guide A, not in guide B`                                   |
| Start time       | For one shared channel, programmes with the same normalized title (trim, lower case, collapse spaces) in two guides whose start times differ by more than 0 and at most the tolerance (default 15 minutes, the same value as `NearTimeWindow` in `Compare-ChannelForgeXmltvGuides`). | `channel X: "Evening News" starts 20:00 in A, 20:10 in B`                 |
| Title            | For one shared channel, two programmes whose start times are within the tolerance but whose normalized titles differ.                                                                                                                                                                | `channel X: 20:00 is "Evening News" in A, "News Hour" in B`               |
| Freshness        | Last programme end per guide against the build time. A guide whose last end is before the build time is `ended`. A guide that ends more than 24 hours before another overlapping guide is `behind`.                                                                                  | `guide A ends 14 Nov 02:00, guide B ends 16 Nov 02:00 (A is 48 h behind)` |
| Exact duplicates | Same channel, same start, same normalized title: counted as agreement, not listed.                                                                                                                                                                                                   | One count: `agree N`                                                      |

Only programmes inside the window both guides cover (the later of the two first starts to the earlier of the two last ends) are compared, so a guide that simply covers fewer days is not reported as a pile of mismatches. That shorter coverage is reported once, under freshness.

### Output (returned, nothing saved in slice 1)

One object: `Contract` = `xguide-compare/v1`, `Guides` (source id, programme count, channel count, first start, last end, state `ok`, `ended` or `empty`), `SharedChannelCount`, `AgreeCount`, `Findings` (each: `Kind` of `MissingChannel`, `StartShift`, `TitleDiffers`, `GuideBehind`; `ChannelId`; `SourceIds` sorted; plain `Message`), `Truncated` (more findings than shown). Order is deterministic: kind, channel id, start, source id. Enumeration order of guides never changes the result.

### Reuse and why not the observation comparer

`Compare-ChannelForgeXmltvGuides` already does the title and time logic for external evidence. Slice 1 does NOT call it, because it needs each programme wrapped as an observation with adapter and provenance fields, and it is built for online evidence (step 9). Wrapping thousands of programmes just to get two comparisons adds more code than the comparison. Slice 1 reuses its rules instead (the 15 minute window, the title normalization) and keeps them as one named value each. If the owner prefers one comparer for steps 8 and 9, see owner question 3.

Also reused: `Get-ChannelForgeGuideEnd` data (last end per source), `Get-SafeReportText`, the "Category check" call pattern.

## Where it is shown and stored

- Shown: one short section in `output\reports\lineup-plan.md`, after the Category Check block and before "M3U/XMLTV Identity Binding". Built by a pure lines function (name suggestion: `Get-ChannelForgeXguideSummaryLines`), same pattern as `Get-ChannelForgeCategorySummaryLines`.
- Stored: nowhere extra in slice 1. The Markdown is the record. Slice 3 may save a JSON copy under `output\guide-compare\<candidate-hash>.json`, never inside a candidate directory (an extra file fails `Test-ChannelForgeCandidateNamespace`).
- Never in: `lineup-change-review.md`, the manifest, any hash input, BuildIdentityInput, `merged.m3u`, `merged.xml`, or the accepted state.

## What the owner sees before accepting

- Fewer than two enabled guides, or two guides with no shared channel: nothing, or one line `Guide comparison: needs two guides that share channels.` Recommend nothing (silent).
- Two or more guides that agree: one line `Guide comparison: 2 guides, 140 shared channels, all programmes agree.`
- Disagreement: a `## Guide Comparison` section with the counts line, a count per kind, up to 5 plain findings per kind, `and N more`, and one hint line: `Check the guide source or remove the guide that is wrong. Nothing was changed.`

Every line uses the guide's safe label. No URL, path, cache key or server id.

## Failure semantics

| Event                                                            | Result                                                                                                                                                                             |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One guide only                                                   | No section. Not an error.                                                                                                                                                          |
| A guide could not be read or gave zero programmes                | Named once as `empty` with its import reason (existing `$xmltvAcquisitionStatuses`). Other guides are still compared.                                                              |
| All guides empty or no programmes at all                         | No section. The build already fails or defers on its own.                                                                                                                          |
| Programme with an empty channel id or an end not after its start | Skipped (the merge already rejects these before this point).                                                                                                                       |
| Any error inside the comparison                                  | One console warning (`The guide comparison could not run, so the comparison section is left out of the summary.`). The build result, exit state and candidate bytes are unchanged. |
| Too many findings                                                | Capped at 5 shown per kind, `Truncated` set, count still exact.                                                                                                                    |

Always true: no channel dropped, `guide: null` stays, no guide rewritten, no winner picked, no network, no secrets printed.

## Frozen contracts

guide-id v1.0, raw digest projections, M3U entry byte format, BuildIdentityInput and blocker-2-contract/v7, accepted-state code, transport and trust code. No slice below touches them. The comparison runs after the candidate is sealed (like the Category check), so no frozen item is needed. If a later slice wants the comparison to gate acceptance or change a hash, that needs its own contract and owner approval.

## Slices (at most 3, each under about 150 lines of product code)

| #   | Slice                                                                                                                                                                                                                                                      | Size             |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| 1   | Pure comparison function over the build's `Programme` list plus a lines function, one report section in `lineup-plan.md`. Presence, start time, title, freshness.                                                                                          | About 150 lines. |
| 2   | Binding awareness: compare only guides bound to the same playlist (from source-set bindings), name the playlist in each line, so a guide bound to Playlist A is never compared with one bound to B. Needs the bindings passed into the build summary path. | About 80 lines.  |
| 3   | Saved JSON copy `output\guide-compare\<candidate-hash>.json` and a read command `Get-ChannelForgeGuideComparison`, so headless users and later UI read the same report.                                                                                    | About 100 lines. |

Later (not designed here): browser display of the report (step 7), online evidence comparison (step 9, may reuse `Compare-ChannelForgeXmltvGuides`), enrichment (step 10).

## Owner questions

1. **Tolerance.** 15 minutes for "same programme, different start", 24 hours for "a guide is behind". Recommend yes. Same value as the existing comparer, easy to explain.
2. **Show when all agree?** Recommend one short agreement line only when two or more guides share channels. Silent otherwise.
3. **One comparer or two.** Recommend a small purpose-built comparer now (no observation wrapping) and revisit merging it with `Compare-ChannelForgeXmltvGuides` when step 9 adds real observations.
4. **Playlist scoping.** Slice 1 compares by channel id across all enabled guides, which can compare a guide bound to Playlist A with one bound to B. Recommend accepting that for slice 1 (report only, no harm) and doing slice 2 right after.
5. **Existing build stop.** Today an exact-interval conflict inside the merge stops the build. Recommend leaving that alone; this report is about different guides, not about that rule.

## Not verified

- Slice 1 does not report a pair with different titles whose starts differ by more than the tolerance, or a programme present in one guide and absent from the other inside the shared window. Those are real disagreements and are left out of slice 1; the slice 1 task must add one fallback kind (`Unmatched`, both times and titles) or the owner must accept the gap.
- `npx prettier` was run with no local install, so it may have fetched prettier over the network, against the lane rules. Not confirmed.

- No code was run. No test was run. The tree is not a git repository, so no history was checked.
- The exact input of `Resolve-ChannelForgeM3UXmltvBinding` when two guides carry the same channel id (which one is `Exact`, whether it becomes review-needed) was not read in full. Slice 1 must read it first.
- Whether `$allProgrammes` is still in scope after the XMLTV block when the XMLTV step fails or is deferred, and what `$xmltvAcquisitionStatuses` holds in that case.
- Cost on large guides (hundreds of thousands of programmes). The plan is one pass grouped by channel, not measured.
- That source labels are always safe to print (`Get-SafeReportText` is assumed to be enough).
- Which file the existing build summary tests use for an end-to-end `lineup-plan.md` check.
