# Phase 1 design note: EPG acquisition and merge (issue #40)

Contract: epg-slice/v1

Design only. No product code, test, schema or workflow was changed. No product code was run. Facts below come from reading the code on this tree and from counting the 479-channel trial files (ETV.m3u, ETV.xml).

## Why

Eli needs one correct merged guide for a one-time run of his real lineup (Plex plus Dispatcharr). The issue text describes a platform. The code already has most of the pipeline. This note finds only what a one-time run still lacks.

## What main does today

| Step              | Real file and function                                                                                     | Behavior                                                                                                                                                               |
| ----------------- | ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Config            | scripts\Build-Lineup.ps1 `Select-ChannelForgeEpgConfig`, data\epg\epg_sources.json                         | A local override file wins and must be valid. Sources sorted by priority, name, path.                                                                                  |
| Ingest            | Public\Import-ChannelForgeConfiguredXmltvSource.ps1 (local and remote), Read-ChannelForgeXmltvDocument.ps1 | Remote uses a cache (6 hour TTL, Private\Get-ChannelForgeRemoteXmltvCachePolicy.ps1). A failed or empty source throws; the whole XMLTV stage fails. No stale fallback. |
| Merge             | Public\Merge-ChannelForgeXmltvProgrammes.ps1                                                               | Groups by source-scoped channel plus time slot. Same facts merge as a duplicate. Different facts become a conflict.                                                    |
| Conflict handling | Build-Lineup.ps1 (around line 670), Private\ConvertTo-ChannelForgeXmltvBytes.ps1                           | Any conflict throws and no merged XMLTV is written.                                                                                                                    |
| Channel to guide  | Public\Resolve-ChannelForgeM3UXmltvBinding.ps1                                                             | Exact, case-sensitive tvg-id equals XMLTV channel id. Statuses: Exact, Unbound, NeedsReview, OrphanedXmltv.                                                            |
| Export            | Public\Export-ChannelForgeXmltv.ps1                                                                        | Writes bytes to the staging path. Build-Lineup then stages a candidate.                                                                                                |
| Report            | Build-Lineup.ps1 (`XMLTVAcquisitionStatus`, `M3UXmltvUnbound*`, markdown section near line 1020)           | Per-source Outcome (Fetched or CacheHit) and Reason. Unbound and review lists.                                                                                         |
| Build-My-Lineup   | scripts\Build-My-Lineup.ps1, Build-Candidate.ps1                                                           | Takes ONE guide file (`-XMLTVPath`). It does not read epg_sources.json. Collision choices: KeepWithoutGuide or OwnPlaceholder (Add-ChannelForgePlaceholderGuide).      |

Correction to the logo note: `Add-ChannelForgePlaceholderGuide` does have a caller, Build-My-Lineup.ps1 line 778.

## What a 479-channel run still lacks

Evidence from the trial files: the M3U has 482 entries, 451 distinct tvg-ids, 3 ids used more than once. ETV.xml has 451 channels and 37,476 programmes. All 451 distinct M3U ids match an XMLTV channel id after normal XML decoding (checked by a separate count, Nov 13, 2026).

1. **Bound but empty guide.** 102 of 451 XMLTV channels have zero programmes, and M3U ids match all 102 of them. Those channels count as Exact today and show an empty guide in Plex. Nothing reports them. Not found in code: any per-channel programme count in the report. This is the biggest gap.
2. **Silently old guide.** A local XMLTV file is never checked for age. Remote CacheHit inside the TTL is reported, but the report has no "guide ends on" date. A file that ended last week builds fine.
3. **Unmatched channels: no problem found.** Unbound channels are already in the report with Reason `TvgIdNotFoundInXmltv`. In the trial every id matches, so no user problem exists here. (A first search that skipped XML decoding showed 20 false mismatches from `&amp;`; the product reader parses XML, so it is not a real gap.)
4. **One bad source stops all guides.** One failed source, or one conflict, throws and no XMLTV is produced. This fails closed and is honest. But the message says only "could not be imported". It does not name the source.
5. **Several sources do not fill gaps.** Merge groups by source-scoped channel. A channel bound to source A never borrows programmes from source B. For one user with one big file this is not a problem today.
6. **Build-My-Lineup ignores the source list.** Only one guide path. A user with two files must pre-merge by hand.
7. **Outcome words.** Report uses Fetched and CacheHit. The issue wants Stale, Failed, NeedsReview too. Failed already stops the build, so adding names only helps the report.

## Smallest slice: small PRs in build order

Each PR is about 80 changed lines, never over 150, and has no behavior change to published bytes.

1. **PR 1: per-channel coverage in the report.** For each Exact binding, add programme count, first start and last stop. List Exact channels with zero programmes as `EmptyGuide`. Fixes gap 1: Eli sees the 102 before Plex does. Reuse `Resolve-ChannelForgeM3UXmltvBinding` candidates (they already carry `ProgrammeCount`) and `ConvertTo-SafeChannelForgeIdentityRecord`.
2. **PR 2: guide end date and age warning.** Add `GuideEndsUtc` per source and overall to the build report. Warn when the last stop is earlier than build time plus a set number of hours (default 48). Never block. Fixes gap 2.
3. **PR 3: name the failing source.** Make the import and conflict errors carry the source name and the Reason, using the existing `XMLTVAcquisitionStatus` shape. Add `Failed` there. Fixes gap 4.
4. **PR 4 (only if Eli needs two files): Build-My-Lineup reads more than one guide.** Pass a list of paths to Build-Candidate and reuse the existing import and merge loop. Fixes gap 6.

Dropped: an "explain unbound ids" PR. The trial has no unbound ids, so it protects no real user (gap 3).

Total about 320 lines over four PRs. PR 1 to 3 cover the one-time run.

## Out of scope for Phase 1

| Item                               | Why                                                                                       |
| ---------------------------------- | ----------------------------------------------------------------------------------------- |
| Guide catalog and fit analyzer     | Eli supplies his own files. No user problem in a one-time run.                            |
| Scheduling and safe refresh        | Not live. Scripts\Install-ChannelForgeScheduledRefresh.ps1 already exists for later.      |
| Mirrors and rights                 | No second source of the same guide is in the trial. Legal review needs an owner.          |
| Remote acquisition work            | Fetch, cache and URL safety already exist. Nothing found broken.                          |
| Compatibility profiles             | Plex and Dispatcharr accept the current XMLTV. No failure observed.                       |
| Cross-source fill-in merge (gap 5) | Needs a policy design and touches binding identity. Revisit when a second source is real. |
| Stable identity across renames     | Exact tvg-id is the rule today and is frozen by contract v1.0. Do not extend it now.      |

## Decisions (provisional, Nov 13, 2026)

Recommended defaults. Eli can override any of them before the matching PR merges.

1. Should an Exact channel with zero programmes block the build? Recommend: warn and list only. Never drop the channel.
2. How old is too old? Recommend: warn when the guide ends less than 48 hours after build time. Never block.
3. Does a source conflict still stop the whole XMLTV build? Recommend: yes, keep it, and name the source. Fail closed.
4. Add Stale and NeedsReview outcome words now? Recommend: add Failed only (PR 3). The others have no new cause yet.
5. Is PR 4 (several guide files in Build-My-Lineup) needed? Recommend: skip until Eli has a second guide file.

## Risks to frozen contracts

- **Guide-id contract v1.0.** PR 1 to 3 only read binding results and add report fields. No binding rule changes, so no channel is dropped and `guide: null` stays. No PR rewrites a tvg-id. PR 4 adds sources into the existing import loop and must keep the exact-match rule.
- **raw-xmltv-occurrence/v2 and raw-m3u-occurrence/v2.** No PR touches the readers or projection helpers. Coverage counts come from parsed programmes, not from edited source text.
- **M3U byte format (ConvertTo-ChannelForgeM3UEntryBytes).** Untouched.
- **Candidate manifest and report.** New report fields must be added beside existing ones; check the manifest hash inputs before PR 1 so a report-only field does not change a build identity. Not verified: whether report fields reach the hash.

## Not verified

- Whether bound-but-empty channels reach the manifest as Exact (needs a run).
- Whether the product reader decodes ids exactly like the separate trial count did (that count used standard XML decoding and matched all 451 ids).
- Whether the report markdown or JSON feeds any hash.
- Tests were not run. No script was imported.
