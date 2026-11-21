# Milestone 1 completion map (Guides and Events)

Status: analysis only. No product code or tests were changed. Nothing was run: no tests, no build, no git. Every "met on main" line comes from reading the work tree, so "test X covers it" means the test exists and appears to cover it, not that it passed.

Open issues: #28, #29, #30, #32, #38, #40, #41, #59, #121, #175, #191.

## How to read this

- Many old comments on these issues describe an older beta checkout that is not on main. Those items are treated as not done.
- Owner decisions applied:
  - No UI. UI items move to Milestone 3.
  - Every category equal.
  - Logos are real public https links only. No caching, no hosting.
  - Facts only, own-words descriptions. Free sources only.
  - Event handling is fully automatic.
  - Public guide sources: the provider's own guide plus time agreement; reuse-permitted sources (Wikipedia/Wikidata with attribution, official feeds); user-supplied guides (facts only). Scraping adapters live only in the owner's private builds.
  - AEW stays out. This beats the October comment on #191 that named it as a first adapter.
  - Catch-up is report-only, because attributes would change the frozen M3U entry byte format.
  - The event guide is a separate file outside `accepted\`.
  - Frozen and untouched: guide-id v1.0, raw digest projections, M3U entry byte format, BuildIdentityInput, blocker-2-contract v7/v8/v10, accepted-state, candidate-manifest, decision-manifest, transport/trust.
- Slice names look like `32-B`: issue number, then letter. A slice under about 300 changed lines, code plus tests.
- Shared slices: one slice can close parts of several issues. They are listed once, under the first issue that names them, and cross-referenced.

## #28 Event Intelligence (epic)

- **Met on main:** automatic detection and time agreement; event guide for high-rated channels with fallback to the provider guide; doubleheaders; provider-error text kept out; force on/off override; saved schedule answers. Files: `Get-ChannelForgeEventChannelCandidate`, `Get-ChannelForgeEventTimeAgreement`, `Get-ChannelForgeEventGuidePlan`, `Get-ChannelForgeEventProgrammeBlocks`, `Set-ChannelForgeEventChannel`, `Compare-ChannelForgeScheduleEvidence`. Tests: `tests/unit/Event*.Tests.ps1`, `ScheduleAnswer.Tests.ps1`.
- **Left:** nothing of its own. It closes when #29, #30 and #32 close.
- **Later milestone or rejected:**
  - Ranking "why" screen and opportunities panel: Milestone 3.
  - Scheduler for unattended refresh: the build already runs the event logic on every build, so "unattended" is met by that. A separate scheduler is a later milestone.
  - Paid feeds, AEW adapter, scraping in the public product, artwork hosting: rejected.
- **Slices:** none. Close when #29, #30, #32 are closed.

## #29 Foundation: neutral models, source adapter, cache, fixtures

- **Met on main:**
  - Neutral evidence boundary `ChannelForgeExternalEvidenceObservation/v1`: `docs/architecture/EXTERNAL_EVIDENCE_OBSERVATION_CONTRACT.md`, `schemas/external_evidence_observation.schema.json`, `ConvertTo-ChannelForgeExternalEvidenceObservation`, test `ExternalEvidenceObservationContract.Tests.ps1`.
  - Local schedule-evidence reader and comparer: `Read-ChannelForgeScheduleEvidence`, `Compare-ChannelForgeScheduleEvidence`, tests `ScheduleEvidence.Tests.ps1`, `ScheduleAnswer.Tests.ps1`.
  - Bounded https transport (ADR-0014).
  - Deterministic title keys and doubleheader labels.
- **Left:**
  - Nothing writes `state/schedule-evidence.json`. Only a reader exists.
  - No evidence cache with fetch time, expiry and last-known-good.
  - The evidence record only fits home-vs-away games. No event, session or race kind.
  - No reuse-permitted network adapter.
- **Later milestone or rejected:**
  - Public league endpoints whose terms limit automated reuse, Sportradar, SportsDataIO, paid TheSportsDB tiers: rejected (not free or not reusable).
  - The 43-sport catalog, follows/opportunities report, indexed storage (#36): later milestone.
  - Wrestling card-v2 contract and AEW adapter: rejected.
- **Slices:**
  - **29-A User-supplied schedule importer.** About 180 lines. New `Import-ChannelForgeScheduleEvidence`, small change to the evidence reader, one test file. Output bytes: no (only changes questions).
  - **29-B Widen the evidence record** with optional `kind` (game, session, race, card) and name. About 100 lines. `Read-` and `Compare-ChannelForgeScheduleEvidence`, tests. Output bytes: no. Also serves #38 session events.
  - **29-D Evidence cache** with fetch time, expiry, last-known-good. About 150 lines. New private helper, tests. Output bytes: no.
  - **29-C Wikipedia/Wikidata text adapter** through the ADR-0014 transport, with attribution, revision id and fetch time. Offline fixtures first. About 280 lines. New private adapter, fixtures, tests. Output bytes: no. Also closes the first adapter asked for in #175 step 9 and #38.

## #30 Discovery, matching and lifecycle

- **Met on main:** scored detector with plain reasons (`EventChannelCandidate.Tests.ps1`); time agreement `agreed`/`conflict`/`single-source` (`EventTimeAgreement.Tests.ps1`); doubleheader pair key and review questions (`EventProviderErrorDoubleheader.Tests.ps1`); provider error text rejected; saved answers.
- **Left:**
  - Cross-channel grouping is exact-title only. "A vs B" and "A v B" on two channels do not group.
  - No explicit test that "missing from a later read" means unknown, not gone.
  - No fixtures for session events with their own start and end.
- **Later milestone or rejected:**
  - "Why did this rank higher" screen: Milestone 3.
  - Ranking with rejected-alternatives report: later milestone. Not needed for a usable event guide.
  - Create/delete temporary event channels: rejected here, because it would change M3U entries. Lifecycle stays report-only.
  - Learning: #31, not in this milestone list.
- **Slices:**
  - **30-A Cross-channel pair-key grouping** in time agreement, reusing the doubleheader helper. About 80 lines. `Get-ChannelForgeEventTimeAgreement`, `Get-ChannelForgeEventDoubleheader`, tests. Output bytes: no (report).
  - **30-D Missing-means-unknown regression tests**, small guard if a test fails. About 60 lines. Event blocks and tests. Output bytes: no.
  - **30-B Session fixtures and lifecycle report.** About 150 lines. Moved to the later list; see "Not needed to close".

## #32 Event guide delivery

- **Met on main:** high-rated channels get an event guide from their own provider programmes; gaps show the channel name (a working idle state); guide id `ChannelForge-<32 hex>`; https-only icons (`Add-ChannelForgePlaceholderGuide`, `Get-ChannelForgePlaceholderIconMap`); logo lookup reused; overrides win. Wiring: `scripts/Build-Lineup.ps1` (report), `scripts/Build-My-Lineup.ps1` (apply).
- **Left:**
  - The event blocks are written inside the candidate guide bytes, not in a separate file. This conflicts with the owner decision.
  - Event-channel logos by link.
- **Later milestone or rejected:**
  - Refresh/publish command with confirm token: rejected, handling is automatic.
  - Artwork render report, templates, asset publishing, caching, hosting: rejected.
  - Any browser page for event delivery: Milestone 3.
  - "No scheduled event" text in place of the channel name: later milestone, low value.
- **Slices:**
  - **32-A Owner check, no code.** Does the event channel's `tvg-id` move to the separate file? Moving the blocks out changes the candidate guide bytes and may change the tvg-id in M3U lines for event channels. Without a yes, 32-B must not start. See decisions at the end.
  - **32-B Separate `event-guide.xml`** written outside `accepted\`, replacing the in-candidate injection. About 250 lines. `scripts/Build-My-Lineup.ps1`, `Add-ChannelForgePlaceholderGuide`, tests. Output bytes: yes. Candidate guide loses event blocks; event channels point at the separate guide. Raw digest projections and the M3U entry format are unchanged, but check `BuildIdentityInput` does not read event blocks. Also closes the same item in #38.
  - **32-C Event logos by link** from the existing logo lookup. About 100 lines. Plan and icon map. Output bytes: event guide only. Do after 32-B and after 41-A has real lookup data.

## #38 Sports channel lifecycle, templates, artwork

- **Met on main:** report-only detection and time agreement; automatic apply of high-rated only, with fallback; gap filler, missing stop time, doubleheaders (`EventGuidePlan.Tests.ps1`); force on/off (`EventChannelOverride.Tests.ps1`); facts-only schedule evidence; team aliases by league with Review instead of guessing (`TeamAliasContext.Tests.ps1`); date/time pattern parsing (`EventPatternDateTime.Tests.ps1`); absence is not cancellation (design note).
- **Left:**
  - Anti-mismerge fixtures: adjacent-day rematch, league boundary, window vs start, zero-game or partial source must not erase a channel.
  - Session type in evidence and labels (practice, qualifying, race).
  - Replay/archival rejection.
  - Separate event guide file (same work as 32-B).
- **Later milestone or rejected:**
  - Archetypes, create/delete buffers, per-league overrides, dynamic groups, collision-aware channel numbers for event channels: rejected for this milestone. They create and delete channels, which changes M3U entries. Report-only lifecycle plan moves to a later milestone.
  - Per-event artwork, SVG renderer, template picker: rejected (no hosting) or Milestone 3 (picker).
  - Paid WBC and MotoGP adapters: rejected (not free).
  - AEW and wrestling-promotion adapters: rejected. Note: `aew` is still in the `eventWords` list in the event-pattern code. Leave it as a generic word unless the owner wants it removed.
  - Olympic and badminton feeds: need a recorded rights decision first; otherwise user-supplied facts only.
  - DVR slot handoff, Top Matchups ranking: rejected (provider-owned, plugin).
  - Team-ID XMLTV pass-through: unknown semantics, nothing to build.
- **Slices:**
  - **32-B** closes the separate-file item.
  - **38-C Anti-mismerge fixtures.** About 200 lines, mostly tests. `Compare-ChannelForgeScheduleEvidence`, `Get-ChannelForgeEventProgrammeBlocks`. Output bytes: no. Do after 29-B.
  - **38-D Session type in labels** (uses 29-B). About 150 lines. Evidence reader, blocks. Output bytes: event guide only. Optional; see later list.
  - **38-E Replay rejection** by naming evidence. About 100 lines. Detector, tests. Output bytes: no (changes which channels count as events). Optional.

## #40 XMLTV acquisition, merge and guide quality

- **Met on main:**
  - Parse and compressed input: `Read-ChannelForgeXmltvDocument`, `Open-ChannelForgeXmltvSourceStream` (xml, gz, one-entry zip); `XmltvParser.Tests.ps1`, `XmltvCompressedIngestion.Tests.ps1`.
  - Remote fetch with cache, 304 revalidation, fail-closed stale cache: `Open-ChannelForgeRemoteXmltvSourceStream`, `RemoteXmltvFetchCache.Tests.ps1`.
  - Merge with duplicate and conflict reports and provenance: `Merge-ChannelForgeXmltvProgrammes`, `New-ChannelForgeXmltvEvidenceRecord`; tests `XmltvProgrammeMerge`, `XmltvEvidenceRecord`, `XmltvSerialization`.
  - Binding: `Resolve-ChannelForgeM3UXmltvBinding`, `Resolve-ChannelForgeProgrammeBinding`; tests `M3UXmltvBinding`, `BuildLineupIdentityBinding`.
  - Reports: `Get-ChannelForgeXguideReport` (matched channels with no programmes, 48-hour horizon, empty or ended state); `BuildLineupFailedGuideSource.Tests.ps1`.
  - Cross-guide comparison: `Compare-ChannelForgeXmltvGuides`, `XmltvGuideComparison.Tests.ps1`.
- **Left:**
  - A real Build-Lineup run on the trial files with the new reports is not recorded.
  - Fixture for two guides that share a `tvg-id` (source-scoped), and for a failed refresh keeping last-known-good.
  - Unverified: whether `<new/>`, `<previously-shown>`, `<date>` and bare `episode-num` survive parse, merge and export. A search found only `episode-num`.
- **Later milestone or rejected:**
  - All web panels, find-a-guide filter, monitoring digest, cron builder: Milestone 3.
  - Schedules Direct adapter: rejected (paid). Scraping-style adapters and a public iptv-org worker catalog: rejected for the public product (private builds only).
  - Source catalog, preflight, contract-report scripts, fit/set-cover analysis, manifest preview, request budgets, mixed local-plus-remote setup: later milestone. They were on the old beta checkout, not main, and the owner wants usable, not perfect.
  - Per-channel guide authority across downstream providers: rejected (touches accepted-state).
  - DVR and catch-up notes, Docker/NAS evidence: rejected, out of scope.
  - XZ input: later, low value.
- **Slices:**
  - **40-A Real run, no code.** Run Build-Lineup on the trial files and record the report results. Output bytes: no. Needs the owner's files.
  - **40-B Fixtures:** shared `tvg-id` across two guides, failed refresh keeps last-known-good. About 120 lines, tests only. `XmltvProgrammeMerge`, `BuildLineupFailedGuideSource` tests. Output bytes: no.
  - **40-C Preserve `<new/>`, `<previously-shown>`, `<date>`, bare `episode-num`** only if a check shows they are lost. About 200-300 lines. `Read-ChannelForgeXmltvDocument`, `ConvertTo-ChannelForgeXmltvBytes`. Output bytes: yes for guides that carry these tags. Check the frozen raw digest projections first. First step is a 10-line check; do the rest only if tags are lost and the owner agrees.

## #41 Channel visual identity (logos)

- **Met on main:**
  - Public https rule: `Get-ChannelForgeLogoStatus` (Public, Empty, NotHttps, PrivateAddress); `LogoStatus.Tests.ps1`.
  - Publish order pin, provider logo, lookup, group default, empty, never drops a channel: `Get-ChannelForgePublishLogo`; `LogoDefault.Tests.ps1`, `LogoFingerprint.Tests.ps1`.
  - Pins: `Set-`/`Get-`/`Read-ChannelForgeLogoPin`; `LogoPin*.Tests.ps1`.
  - Offline lookup and refresh with host allow-list, `-WhatIf`, atomic write, drop guard: `Get-ChannelForgeLogoLookupMap`, `Update-ChannelForgeLogoLookup`; `LogoLookup.Tests.ps1`, `LogoLookupRefresh.Tests.ps1`.
  - Report fields and XMLTV `<icon>` follows the published logo: `Get-ChannelForgeLogoReport`, `Get-ChannelForgeGuideIconMap`; `LogoGuideIcon.Tests.ps1`.
- **Left:**
  - `data/logo-lookup.json` is an empty skeleton. The owner must review hosts and licences and run the first real refresh. The list address in `Get-ChannelForgeLogoListDownload` is marked unverified in code.
  - Bad-logo safety: very long, data-URI, control characters. Today only scheme and host are checked.
  - M3U `tvg-logo` vs XMLTV icon agreement report.
- **Later milestone or rejected:**
  - Web publication summary, logo picker: Milestone 3.
  - Local image inspection, hashing, asset publisher, content-hash filenames, overwrite-409 handling, SVG derivatives: rejected (no caching or hosting).
  - Paid artwork, VOD/DVR artwork: rejected.
  - tv-logos second source, last-known-good logo on a bad refresh, programme-icon evidence, live link checking: later milestone. Usable without them.
- **Slices:**
  - **41-A Owner-run first lookup refresh,** then review and merge `data/logo-lookup.json`. No code. Output bytes: yes (more `tvg-logo` values and icons; entry format unchanged).
  - **41-B Bad-logo hardening:** length cap, data-URI, control characters, new status words. About 100 lines. `Get-ChannelForgeLogoStatus`, report, tests. Output bytes: only for channels that now fall back to the group default.
  - **41-D Logo agreement report** (M3U vs XMLTV, by exact channel id, no URLs printed). About 150 lines. New private function, test. Output bytes: no.

## #59 Catch-up/timeshift metadata

- **Met on main:** `catchup_timeshift` capability set to unknown with evidence rule (`schemas/compatibility-profile.schema.json`, `data/compatibility/generic-m3u-xmltv.profile.json`, `CompatibilityProfile.Tests.ps1`); `TimeshiftSupported = $null` in `Get-ChannelForgeOneGuide`; the no-playback boundary in `docs/user/CURRENT_LIMITATIONS.md`.
- **Left:** nothing reads catch-up attributes. No template-family shape check, archive-duration report, sanitized fixtures, or test that old XMLTV rows do not prove playback.
- **Later milestone or rejected:**
  - Writing catch-up attributes into output: rejected (changes the frozen M3U entry bytes).
  - Handoff route, "Open catch-up", entitlement resolution, archive probes: rejected (playback, proxying, provider-owned).
  - Guide button or page: Milestone 3.
- **Slices (all report-only, no output bytes):**
  - **59-A Shape classifier:** path-template, query-template, declared-only, none. Emits no URL, user, password or query text. About 120 lines. New private function, sanitized fixtures, test. Open question: the M3U reader keeps raw text only. Prefer a side read of the raw attributes. Any reader change must prove the raw digest is identical.
  - **59-B Catch-up report** per candidate stream: declared archive days, family, evidence source, "XMLTV history is not proof" flag. About 180 lines. New report function. Needs 59-A.
  - **59-C Profile statement** that the generic target ignores catch-up, with fallback wording. About 60 lines. Profile JSON, docs, `CompatibilityProfile.Tests.ps1`. Independent of 59-A and 59-B.

## #121 Event-pattern inference and IPTVBoss/AED interoperability

- **Met on main:**
  - Stage A evidence: `New-ChannelForgeGuideEvidence`, `Get-ChannelForgeGuideReadiness`.
  - Stage B inference, candidate only, cannot publish: `Invoke-ChannelForgeGuidePatternInference`, `Invoke-ChannelForgeGuidePatternAnalysis`.
  - Stage C review: `Get-ChannelForgeGuidePatternReview`.
  - Stage D preview `-EventPatternPreview` in `scripts/Build-My-Lineup.ps1`, redacted reports, rejects `-Accept`.
  - Stage E acceptance plan: `Get-ChannelForgeGuidePatternAcceptancePlan`, `schemas/guide-pattern-acceptance-plan.schema.json`.
  - Tests: `EventPatternDateTime.Tests.ps1` and the `GuidePattern*` tests. Drift is reported without adoption. Redaction excludes URLs, tokens, raw examples.
- **Left (all hardening of an already usable path):**
  - Expert regex/date/time overrides with one compile path.
  - Typed input domain (channel name vs stream name) for lifecycle rules.
  - Weekday default and tolerance, explicit time-presence provenance (a parsed 00:00 is not "no clock").
  - AED JSON import. Blocked: no real export fixture. Do not guess the schema.
  - Cross-day programme id and event-day timezone policy.
  - Schedule corroboration adapters.
- **Later milestone or rejected:**
  - Beginner GUI, Live Now UX: Milestone 3.
  - Stream priority 0-9 attributes in M3U: rejected (frozen entry bytes). Could be report-only.
  - Boss Player Output, Sports Hub, DVR/timeshift: out of scope.
  - Public one-to-one IPTVBoss database reads: rejected.
  - Unattended refresh, learned rule store, automatic relearning, event guide publication (done by 32-B): later milestone or covered elsewhere.
  - Catch-up: report-only (see #59).
- **Slices (none change output bytes):**
  - **121-A Expert regex canonical compile path,** fail closed. About 200 lines. `Invoke-ChannelForgeGuidePatternAnalysis`, one new private helper, tests.
  - **121-B Input-domain typing** and fail-closed lifecycle rule. About 150 lines. `GuideEventPatternRule`, Stage B input handling. Needs 121-A (same file).
  - **121-C Weekday default and tolerance, time-presence provenance.** About 150-250 lines. Same analysis file plus fixtures. Needs 121-B.
  - Slices for AED import, cross-day policy and corroboration adapters move to the later list.

## #175 Multi-guide enrollment, bindings, cross-guide validation, evidence

- **Met on main:**
  - No implicit ALL binding: single playlist auto-binds, several playlists write none, `AppliesToAll=true` is the only ALL form: `Write-ChannelForgeSourceSet`; tests `SourceSetAddRemove.Tests.ps1`, `SourceEnrollment.Tests.ps1` (around line 151).
  - Identity uniqueness: `Assert-ChannelForgeSourceEnrollmentV2Integrity` runs on write and on read; rejects duplicate source ids, duplicate `BindingId`s, duplicate effective bindings, more than one binding per guide, missing guide or playlist. Tests `SourceEnrollment.Tests.ps1` lines 219-226.
  - Add, remove, edit, bind, refresh plan: `Edit-ChannelForgeSourceSet`, `Set-ChannelForgeSourceSetBinding`, `Get-ChannelForgeSourceRefreshPlan`; tests `SourceSetAddRemove`, `SourceSetBinding`, `SourceSetBindingIdentity`, `SourceSetAcceptRefresh`, `SourceRefresh*`.
  - Browser proposal conversion: `Convert-ChannelForgeGuidedSetupSourceSet`.
  - Step 8 cross-guide comparison: `Compare-ChannelForgeXmltvGuides`, `Get-ChannelForgeXguideReport`.
  - Event slice 1: `EventGuidePlan.Tests.ps1`.
- **Left:**
  - Possible test gaps: duplicate `BindingId` with the exact error, hand-edited record with duplicate ids, two playlists plus one guide with no binding. Not verified, check before adding.
  - Step 9 online evidence adapters: none on main.
  - Step 10 enrichment: not started.
- **Later milestone or rejected:**
  - Browser sections for enrolling and binding, "Guide checked / Needs attention" wording: Milestone 3.
  - Scraping adapters for promotions: private builds only. AEW: out. Catch-up routing: report-only.
  - Journal v2, promotion, recovery, accepted-state changes: not allowed.
  - Step 10 enrichment into the published guide: later milestone. It needs a design note first.
  - Official feed/iCal adapter: later milestone, verify each feed's reuse terms first.
- **Slices (none change output bytes):**
  - **175-1 Tests only,** where a search shows a gap. About 80-120 lines. `SourceEnrollment.Tests.ps1`.
  - **175-2 Wikipedia/Wikidata adapter:** same slice as **29-C**.
  - **175-3 User-supplied second guide as evidence,** facts only (title, start, stop), reusing the XMLTV reader and comparer. About 150-200 lines. Xguide report, tests.

## #191 Guide truth and categories

- **Met on main:**
  - 23-key One Guide taxonomy: `Get-ChannelForgeOneGuideCategoryRegistry`; `OneGuide.Tests.ps1`.
  - Generic Sports to `other-sports` only with no specific sport; group checked against league tags: `Get-ChannelForgeChannelCategory`.
  - Honest scorecard and guide evidence from playlist: `Get-ChannelForgeGuideQualityScorecard`, `ConvertTo-ChannelForgeGuideEvidenceFromPlaylist`; `GuideQualityScorecard.Tests.ps1`, `GuideEvidenceFromPlaylist.Tests.ps1`.
  - No-guide-expected groups (adult, music): `Test-ChannelForgeNoGuideExpectedGroup`.
  - Music, pay-per-view, adult in `data/rules/categories.json`; `CategoryFromText.Tests.ps1`.
  - Empty-group fill (v10, off by default, fails closed): `Export-ChannelForgeM3UPlaylist`, `Get-ChannelForgePublishGroup`; `PublishGroupFill.Tests.ps1`.
  - https-only guide icons: `LogoGuideIcon.Tests.ps1`. Logo lookup: see #41.
- **Left:**
  - Two category vocabularies. `categories.json` (20 entries, has music, pay-per-view, adult) feeds fill, no-guide-expected and the XMLTV genre step. The One Guide registry (23 keys, no music, pay-per-view, adult) feeds the classifier behind the scorecard counts. The owner-approved keys are therefore missing from the classifier. Defect.
  - The "17-category list" in #312 vs 20 entries: unverified, check which list #312 meant.
  - Real 16 MB guide hang (S191H): no fix found on main, not reproduced.
  - `Build-Lineup.ps1` still says "could not be imported" for an empty `<tv/>` guide (near line 834).
  - Logo data is a skeleton (see 41-A).
- **Later milestone or rejected:**
  - Category-hub actions, Watch/Info targets, latency budgets, UX: Milestone 3.
  - Promotion-site scraping: private builds only. AEW adapter: rejected.
  - Per-event guides and artwork: covered by #32, #38 or rejected.
  - Dead-host icon liveness check: later milestone.
  - Wrestling card adapters: blocked by source rights and rejected for public build.
- **Slices:**
  - **191-A Unify the category list** into one source. About 120 lines. `categories.json`, `Get-ChannelForgeOneGuideCategoryRegistry`, `OneGuide.Tests.ps1`. Output bytes: scorecard counts change. M3U bytes unchanged if group names stay the same. Owner picks the key set first.
  - **191-C Empty-guide message fix.** Under 30 lines. `scripts/Build-Lineup.ps1`, one test. Output bytes: no (message).
  - **191-B Fix the 16 MB guide hang** after profiling. About 100-200 lines. Output unchanged if correct. Needs the real file from the owner. Do after 191-C (same script).

## Ordered list of all remaining slices

"Parallel" means no shared files with other slices in the same wave. "Serial" means it needs the slice before it. Waves can start together; lanes inside a wave run in parallel.

### Decisions and no-code steps (start now, in parallel)

| Step | What | Who |
| ---- | ---- | --- |
| 32-A | Allow event-channel tvg-id to move to the separate file? | Owner |
| D-191 | Choose the category key set (191-A) and check the #312 list | Owner |
| 41-A | Review hosts and licences, run first lookup refresh | Owner |
| 40-A | Real Build-Lineup run on trial files, record reports | Owner |
| 191-B input | Provide the 16 MB guide for profiling | Owner |

### Wave 1: all parallel (no shared files)

| Lane | Slice | Size | Files |
| ---- | ----- | ---- | ----- |
| Events | 30-A Cross-channel pair-key grouping | ~80 | EventTimeAgreement, EventDoubleheader |
| Evidence | 29-A User-supplied schedule importer | ~180 | new importer, evidence reader |
| Logos | 41-B Bad-logo hardening | ~100 | LogoStatus, report |
| Logos | 41-D Logo agreement report | ~150 | new function |
| Catch-up | 59-A Shape classifier | ~120 | new function, fixtures |
| Catch-up | 59-C Profile statement | ~60 | profile JSON, docs |
| Categories | 191-A Unify category list (after owner choice) | ~120 | categories.json, registry |
| Build script | 191-C Empty-guide message | <30 | Build-Lineup |
| Patterns | 121-A Expert regex compile path | ~200 | PatternAnalysis |
| Tests | 175-1 Enrollment test gaps | ~100 | SourceEnrollment tests |
| Tests | 40-B Shared tvg-id and failed-refresh fixtures | ~120 | XmltvProgrammeMerge, BuildLineupFailedGuideSource tests |

41-B and 41-D can run in parallel because 41-D adds a new file. 59-A and 59-C touch different files.

### Wave 2: serial inside each lane, lanes parallel

| Lane | Slice | Needs | Size |
| ---- | ----- | ----- | ---- |
| Events | 32-B Separate event-guide file | 32-A yes, and 30-A done (shares event files) | ~250 |
| Evidence | 29-B Widen evidence record | 29-A | ~100 |
| Catch-up | 59-B Catch-up report | 59-A | ~180 |
| Build script | 191-B Fix 16 MB hang | 191-C, owner file | ~150 |
| Patterns | 121-B Input-domain typing | 121-A | ~150 |
| Guides | 175-3 User-supplied second guide as evidence | none, parallel | ~180 |

### Wave 3: serial inside each lane

| Lane | Slice | Needs | Size |
| ---- | ----- | ----- | ---- |
| Events | 30-D Missing-means-unknown tests | 32-B | ~60 |
| Events | 38-C Anti-mismerge fixtures | 29-B, 32-B | ~200 |
| Evidence | 29-D Evidence cache | 29-B | ~150 |
| Patterns | 121-C Weekday, tolerance, time provenance | 121-B | ~200 |

### Wave 4: serial

| Slice | Needs | Size |
| ----- | ----- | ---- |
| 29-C Wikipedia/Wikidata adapter (also 175-2) | 29-D | ~280 |
| 32-C Event logos by link | 32-B, 41-A | ~100 |
| 40-C Preserve XMLTV tags, only if the 10-line check shows loss | 40-A, owner OK | 200-300 |

### Not needed to close (move to a later milestone)

- 30-B Session fixtures and lifecycle report; 30-C "why" lines.
- 38-A Lifecycle plan report; 38-D session labels; 38-E replay rejection; 38-F reuse-permitted adapter (same as 29-C).
- 40-D Source-readiness summary; 40-E XZ input.
- 41-C Last-known-good logo; 41-E tv-logos source; 41-F programme icon evidence.
- 59 beyond A, B, C: nothing.
- 121 AED import (blocked on fixture), cross-day policy, corroboration adapters.
- 175 step 9 other adapters (official feed/iCal), step 10 enrichment.
- 191-D logo data beyond 41-A; 191-E wrestling adapter.

## Shortest honest path to close the milestone

1. Owner answers 32-A (event tvg-id) and picks the category key set. These are the only two decisions that block code.
2. Run Wave 1. Eleven small slices, about 1,300 lines total, no file overlap.
3. Run Wave 2 and Wave 3 lanes in parallel. The critical path is the events lane: 30-A, 32-B, then 38-C. The evidence lane is the longest: 29-A, 29-B, 29-D, 29-C.
4. Owner does the no-code steps in parallel: logo refresh (41-A), the real trial run (40-A), the 16 MB guide.
5. Close issues as follows:
   - #28 when #29, #30, #32 are closed.
   - #29 after 29-A to 29-D.
   - #30 after 30-A and 30-D. Move 30-B and 30-C to a new issue.
   - #32 after 32-B and 32-C. Move the idle-text item.
   - #38 after 32-B and 38-C. Move lifecycle, session, replay and artwork items to later milestones or close as rejected.
   - #40 after 40-A and 40-B. Move the rest to a later milestone.
   - #41 after 41-A, 41-B, 41-D. Move the rest.
   - #59 after 59-A, 59-B, 59-C. It is report-only by owner decision.
   - #121 after 121-A to 121-C. Move AED import (needs fixture) and the rest.
   - #175 after 175-1, 175-3 and 29-C. Move step 10.
   - #191 after 191-A, 191-B, 191-C and 41-A. Move wrestling adapters and liveness checks.

Fewest steps if the owner wants even less: skip Wave 4's 29-C and 32-C, and close #29 and #175 with their remainder moved. That leaves the event guide working from the provider's own guide plus time agreement and user-supplied facts, which are the owner's primary public sources.

## Questions for the owner

1. **32-A:** may the event channels' `tvg-id` point at the separate event guide? Recommendation: yes. It is the only way to keep event blocks out of `accepted\`, and the frozen M3U entry format stays the same.
2. **Category keys (191-A):** use the 23-key One Guide list and add music, pay-per-view and adult to it. Recommendation: yes, one list.
3. **AEW:** the October comment on #191 names it as a first adapter. Recommendation: owner decision stands, AEW is out. Also decide whether the generic `aew` word in the event-pattern code stays. Recommendation: leave it.
4. **XMLTV tags (40-C):** if the check shows tags are lost, may the published guide gain them? Recommendation: only if the raw digest projections are untouched; otherwise skip.
5. **Logo data (41-A):** which hosts are approved after the `-WhatIf` run? Owner action, no recommendation without the licence text.
6. **AED import (121):** supply a real export fixture, or move to a later milestone. Recommendation: later milestone.
