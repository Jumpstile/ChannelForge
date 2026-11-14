# Design note: category quality, pre-accept category check (issue #191, slices 1 to 3)

Contract: category-quality/v1 (slices 1 and 2). Slice 3 adds category-programme-check/v1.

This note was restored from the shipped code and the lane task files. Everything below comes from reading this tree and those task files on Nov 14, 2026. Anything that could not be confirmed is under "Not verified". Slices 1 and 2 are merged. Slice 3 is a design plus the code that goes with this note.

## The problem

1. A channel lands in a vague or wrong group (everything under one Sports bucket, a sports channel under a movies group). The owner finds out only after the guide is in the player. He needs to see the grouping, with a plain reason, before he accepts a build.
2. A correction he makes must survive rebuilds and never be replaced silently.
3. No guessing shown as fact. Every automatic grouping says how it was decided (rule, reason, confidence `high`, `medium` or `none`). When unsure the channel stays ungrouped and the report says so.
4. (Slice 3) A channel under the right group can still carry programmes that belong elsewhere (a movie channel airing a ball game). He finds that out only in the player too.

## What exists today (slices 1 and 2)

| File                                                                    | What it does                                                                                                                                                                                            |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Private\Get-ChannelForgeOneGuideCategoryRegistry.ps1                    | The one category list. Entries have `Key`, `DisplayName`, `Group`, `Aliases` and, on some, `NameTokens` (for example `WWE`, `NFL`, `UFC`). Two `temporal` keys exist and are not allowed as categories. |
| Private\Get-ChannelForgeChannelCategory.ps1                             | One channel in (name, provider group, key, override map), one decision out: `Category`, `Confidence`, `Decision`, `Reason`. No file access. Whole words, case-insensitive.                              |
| Private\Read-ChannelForgeCategoryOverrides.ps1                          | Strict reader for `state\category-overrides.json`. Missing file gives no records. Anything wrong stops with "Fix or delete the file. Nothing was written."                                              |
| Public\Get-ChannelForgeCategoryReport.ps1                               | Reads a sealed candidate (`merged.m3u`), applies overrides, returns the report and saves it as `output\category-reports\<candidate-hash>.json`.                                                         |
| Public\Set-ChannelForgeCategoryOverride.ps1                             | Adds, replaces or (`-Clear`) removes one override record. Writes the whole file atomically.                                                                                                             |
| Private\Get-ChannelForgeCategorySummaryLines.ps1                        | Turns a report into the lines for the build summary.                                                                                                                                                    |
| scripts\Build-Lineup.ps1 (block "Category check (category-summary/v1)") | Calls the report once per build after the XMLTV result, adds the summary lines to `output\reports\lineup-plan.md`. A failure is one `Write-Warning`.                                                    |
| tests\unit\CategoryReport.Tests.ps1, CategorySummary.Tests.ps1          | Pin what the owner sees (decisions, overrides, stale overrides, corrupt file, no URL in the report, same bytes twice, summary text, hash unchanged).                                                    |

## Contract category-quality/v1

### Decision rules (in order)

1. Override: category as set, `high`, decision `override`.
2. Name and group agree (or the group is generic Sports): `high`, `name-and-group`.
3. Name only: `medium`, `name`.
4. Group only: `medium`, `group`. A generic Sports group gives `other-sports` and says it is generic.
5. Two different specific categories in name and group: no category, `none`, `conflict`, the reason names both.
6. No evidence: no category, `none`, `no-rule`.

### Report (returned and saved)

Fields: `Contract`, `CandidateManifestHash`, `ChannelCount`, `Summary` (`Categories` count per registry key, `Ungrouped`, `High`, `Medium`, `None`, `OverridesApplied`, `OverridesStale`), `Overrides` (`File` `Loaded` or `Absent`, `Applied`, `Stale` list), and `Rows` (`ChannelKey`, `DisplayName`, `ProviderGroup`, `Category`, `Confidence`, `Decision`, `Reason`). `ChannelCount` equals `Rows.Count`. The key of a channel is `Get-ChannelForgeChannelKey` of its stream URL. No URL is stored or printed. Written as canonical JSON with no clock value, so the same input gives the same bytes.

### Override file

`state\category-overrides.json`: `version` (exactly `category-quality/v1`) and `overrides`, each record `key` (64 hex), `name`, `category` (a registry key, not temporal), `decidedAt` (UTC). One record per key. A record whose channel is not in the candidate is kept and listed as stale.

### Where files live

| File                                            | Folder                                                  | Written by                         |
| ----------------------------------------------- | ------------------------------------------------------- | ---------------------------------- |
| `state\category-overrides.json`                 | state root from `Get-ChannelForgeSourceEnrollmentPaths` | `Set-ChannelForgeCategoryOverride` |
| `output\category-reports\<candidate-hash>.json` | repository output folder                                | `Get-ChannelForgeCategoryReport`   |

Nothing is written inside a candidate directory (an extra file would fail `Test-ChannelForgeCandidateNamespace`).

## Failure semantics (as implemented)

| Event                                                                    | Report command                                | Set command            | Build                                                                       |
| ------------------------------------------------------------------------ | --------------------------------------------- | ---------------------- | --------------------------------------------------------------------------- |
| Overrides file missing                                                   | Works, `Overrides.File` is `Absent`.          | Creates the file.      | Works.                                                                      |
| Overrides file corrupt (bad JSON, version, key, category, duplicate key) | Stops, writes nothing, file bytes unchanged.  | Stops, writes nothing. | One warning, category section left out, build and candidate hash unchanged. |
| Candidate directory not valid or no `merged.m3u`                         | Stops, writes nothing.                        | Not involved.          | Same one warning.                                                           |
| Overrides file read-only                                                 | Only reads, so it should work (not verified). | Not verified.          | Not verified.                                                               |
| Stale override                                                           | Kept and listed.                              | Kept.                  | Not shown.                                                                  |

Always true: no channel is dropped or changed, `guide: null` stays, nothing is read from the network.

## What the owner sees before accepting

`output\reports\lineup-plan.md`, after the XMLTV result and before "M3U/XMLTV Identity Binding" (Build-Lineup.ps1, block "Category check"):

- A clean build: one line, `Categories: N channels; <counts>; no category M.`
- A build with `medium` or `conflict` rows: a `## Category Check` section with the counts line, the low-confidence and conflict counts, up to 5 channel names with their decision, and one hint line naming `Set-ChannelForgeCategoryOverride`.
- If the check fails: no section and one console warning.

## Owner defaults already taken

- Report only. Never rewrite `group-title` or `Channel.Group` or `Channel.Category`.
- Never gate acceptance. Nothing enters any hash input, BuildIdentityInput, the candidate, `lineup-change-review.md` or the manifest.
- Override key is the channel key (hash of the stream URL).
- Reuse the One Guide registry plus `NameTokens`. No second list, no machine learning, no network, no external catalog.
- A generic Sports group gives `other-sports` at `medium`.

## Frozen contracts

guide-id v1.0, raw digest projections, M3U entry byte format, BuildIdentityInput and blocker-2-contract/v7, accepted-state code, transport and trust code. No slice touches them.

## Slices

| #   | Slice                                                                                                                   | Status                                  |
| --- | ----------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| 1   | Classifier, registry `NameTokens`, override file, `Get-ChannelForgeCategoryReport`, `Set-ChannelForgeCategoryOverride`. | Shipped, PR #238.                       |
| 2   | Category section in the build summary and `lineup-plan.md`.                                                             | Shipped, PR #240.                       |
| 3   | Programme titles against the channel category, one line in the Category Check block.                                    | Designed here and built with this note. |

### Slice 3: programme versus channel check (category-programme-check/v1)

What it does. For each channel that already has a category, read the titles of its programmes from the candidate's `merged.xml`, classify each title, and compare with the channel category. The owner sees one line with a count and up to 5 channel names. Title text only. No network.

Reuse. `Find-ChannelForgeCategoryWord` (registry `Aliases` and `NameTokens`, whole words, case-insensitive), the category report rows (channel decision), `Read-ChannelForgeM3UReader` through the same candidate read as the report, the `Category Check` block in `Get-ChannelForgeCategorySummaryLines`.

Channel to programmes. `merged.xml` writes each guide channel with `channelforge:channel-reference` (the guide channel id) and each programme with the channel element id. A programme belongs to the M3U channel whose `tvg-id` equals that reference (exact, case-sensitive, as guide-id v1.0). A channel with no `tvg-id` or no match has no programmes and is silent.

Title classification. A title has a category when its words match exactly one registry category, counting `Aliases` and `NameTokens`, and not `other-sports` (too generic). Zero matches or two different categories means "not classified".

Sample and threshold (decided here to keep it simple):

- Sample: the first 20 programmes of the channel in file order.
- Needs at least 3 classified titles in the sample. Fewer: silent.
- Disagreement: one category holds a simple majority (more than half) of the classified titles and it is not the channel category.
- A channel whose category is `other-sports` agrees with any `sports` category (football, wrestling and so on).

Output. In the `## Category Check` block of `lineup-plan.md`, one line: `Programme titles disagree with the channel category: N (name, name, ... and M more). Check the channel group or the guide source.` Up to 5 names. Silent when nothing disagrees. If this is the only finding, the block still appears with the counts line and this line.

Report only. No `group-title` change, no gate, nothing in any hash, the candidate, `lineup-change-review.md` or the manifest. Same candidate hash as before. Any error in this check is one warning (`The category programme check could not run, so it is left out of the category section.`) and the build continues; the rest of the category section still shows.

## Owner questions

1. **Disagreement threshold.** Simple majority of classified titles, at least 3 classified, first 20 programmes? Recommend yes. It is easy to explain and quiet.
2. **Title words.** Titles use the same words as channel names plus the group aliases (`movie`, `news`, `comedy` and so on). A title such as "Movie Night" on a sports channel counts as `movies`. Accept some noise? Recommend yes for now; the majority rule and the 3-title minimum absorb one-off titles.
3. **Fix path.** The line only points at channels. There is no per-programme override. Recommend leaving it so; the owner fixes the guide source or the channel group.
4. **Later.** More `NameTokens` (for example `ESPN`, `HBO`) would catch more channels. Recommend adding only when a real miss shows up.

## Not verified

- No code in slices 1 and 2 was re-run for this note; behavior is from reading and from the test names.
- Overrides file read-only behavior (the atomic writer was not traced for a read-only target).
- The exact `lineup-plan.md` line numbers move with every build change; use the block name "Category check".
- Whether other ids than `tvg-id` are ever used to bind guide channels in `merged.xml` (the check relies on `channelforge:channel-reference` equal to the `tvg-id`).
- The PR numbers #238 and #240 come from the task file, not from GitHub.
