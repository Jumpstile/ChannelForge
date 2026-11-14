# Design note: event-aware channels, found automatically, with correct times, places and carrying channels

Contract: event-channel/v2 (proposed, not built). It replaces the event-channel/v1 draft in the first version of this note.

This is a design note. It adds no product code, no tests and no schema. It comes from reading this tree, the `_pr204` copy and the `_pr205` copy on Nov 14, 2026. There is no network and no git history here. Anything not read or not confirmed is marked [UNVERIFIED] or listed under "Not verified". IPTV Boss is a separate third-party product. Its ideas are described in our own words. We copy none of its text, data or code.

## What changed from the first version

The owner direction on Nov 14, 2026 replaced the first step. The user no longer lists event channels or supplies an event file to begin with. ChannelForge must work out by itself which channels are event channels (like PPV 1). Match details (bouts, card) are optional and left out when no usable source has them. What matters most is correct event times, venue and city, and which channels carry the event.

## Short answers

- **A. Finding event channels.** A small scored detector reads what the build already has: channel name, provider group, category, and how the provider guide titles behave on that channel. It reports a confidence and plain reasons. It is fully automatic: `high` confidence channels get the event guide with no confirm step; `medium` and `low` channels keep their normal provider guide and are only listed in the report. An optional override file may force a channel on or off, but nothing waits on it.
- **B. Where the facts come from.** (1) The user's own provider guide in the build supplies title, start and end. It may supply venue and city in a description, but often does not. (2) The same event on several channels lets us agree on times and list every carrier. Where channels disagree, each keeps its own time and the report marks the conflict. This needs one small new comparison, because the shipped xguide report does not compare different channels. (3) An optional user correction is the fallback. Venue and city stay unknown unless a provider guide supplies them. No online source is used until its rights questions are answered; free sources and provider guides only, no paid service, no API keys.
- **C. Neutral event shape.** One shape: title, start and end (UTC plus the zone the source showed), venue, city, carrying channel keys, confidence, a source for every field. A field can be known, unknown or in conflict. Unknown is not empty.
- **D. Slices.** 1) detect and report, nothing hashed. 2) agree on times across channels. 3) automatic apply rule and per-channel event guide. 4) optional override file. Each under 150 product lines.
- **Safety net.** Only `high` acts. Any parse problem, missing time or conflict falls back to the normal provider guide and never drops the channel. The report always lists which channels were treated as event channels and why. See "Safety net and cost of a wrong guess".

## What exists on main today (read)

| Piece                            | File                                                                                                                                                                                                     | Use for this design                                                                                                                                     |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Channel key                      | `src\ChannelForge\Private\Get-ChannelForgeChannelKey.ps1`                                                                                                                                                | SHA-256 of the stream URL. Survives renames. The key of every per-channel state record.                                                                 |
| Channel list with group title    | `Private\Read-ChannelForgeCandidateChannels.ps1` (reads the sealed `merged.m3u`; each channel has `DisplayName`, `TvgId`, `Url`, `GroupTitle`)                                                           | Name and group for the detector. Already used by the category programme check.                                                                          |
| Programmes per channel           | `Classes\Programme.ps1` (`Title`, `Description`, `Start`, `End` as `datetimeoffset`, `Categories`, `SourceId`, `RawChannelId`); `$allProgrammes` in `scripts\Build-Lineup.ps1`                           | Guide behavior per channel, and which guide source said what. The M3U to guide channel join is the existing `Resolve-ChannelForgeM3UXmltvBinding` rule. |
| Category registry and word match | `Private\Get-ChannelForgeOneGuideCategoryRegistry.ps1` (wrestling, mma, boxing and other sports, with name tokens and aliases), `Find-ChannelForgeCategoryWord`, `Get-ChannelForgeChannelCategory.ps1`   | Whole-word matching and the sports category. Reused as is.                                                                                              |
| Programme title category         | `Private\Get-ChannelForgeCategoryProgrammeCheck.ps1` (`Get-ChannelForgeProgrammeTitleCategory`, `Read-ChannelForgeProgrammeTitles`)                                                                      | Reads the first programme titles per channel and points them at a category. The detector reuses the same reading step.                                  |
| Report-only summary pattern      | `Private\Get-ChannelForgeCategorySummaryLines.ps1`, `Get-ChannelForgeXguideSummaryLines.ps1`; blocks in `scripts\Build-Lineup.ps1` (about lines 1123 to 1150)                                            | A pure lines function, one call per build, a failure is one warning. Same for the event section.                                                        |
| Strict state file pattern        | `Private\Read-ChannelForgeCategoryOverrides.ps1`, `Public\Set-ChannelForgeCategoryOverride.ps1` (takes a 64-hex `-ChannelKey`, `-Clear`, path from `Get-ChannelForgeSourceEnrollmentPaths` `.StateRoot`) | One strict reader, one `Set-` command, atomic write, a damaged file refuses to be replaced. The state root helper is now known.                         |
| Guide comparison                 | `Private\Get-ChannelForgeXguideReport.ps1` (142 lines), `Get-ChannelForgeXguideSummaryLines.ps1`                                                                                                         | Compares the same channel id across guide sources: 15-minute tolerance, exact normalized title. Never compares two different channels. See B2.          |
| Name-only guide                  | `Private\Add-ChannelForgePlaceholderGuide.ps1`, called from `scripts\Build-My-Lineup.ps1` (about line 778)                                                                                               | Base for the event guide in slice 3.                                                                                                                    |
| Stage B pattern rules            | `Classes\GuideEventPatternRule.ps1`, `Public\Invoke-ChannelForgeGuidePatternInference.ps1`, `Public\Get-ChannelForgeGuidePatternAcceptancePlan.ps1`                                                      | Candidate-only rules that read a title into fields (`CanPublish = false`, explicit acceptance). The only safe route to read venue and city from text.   |
| Safe text                        | `Private\ConvertTo-ChannelForgeGuideSafeText.ps1`                                                                                                                                                        | Bounded, redacted free text for titles, venue and city.                                                                                                 |
| Evidence boundary, research      | `docs\architecture\EXTERNAL_EVIDENCE_OBSERVATION_CONTRACT.md`, `docs\research\issue-175-sports-evidence-strategy.md`                                                                                     | The adapter boundary and field provenance idea for any later online source. Not used in slices 1 to 3.                                                  |

## A. Detecting event channels automatically

### The problem in one sentence

A channel such as PPV 1 shows one thing now and another thing tomorrow, and the provider guide for it is missing, name-only, or full of fillers. ChannelForge should notice such channels without a list from the user, say how sure it is and why, and act on the sure ones by itself. Nobody has to approve anything.

### What the detector reads (nothing new)

Per channel, from data the build already holds: the channel name, the provider group title, the category decision (`Get-ChannelForgeChannelCategory`), the programmes the provider guide gives that channel in the build window (title, start, end), and the other channels in the same group.

### Signals, strong and weak

Slice 1 measured two real guides (28,239 and 6,100 channels). Filler share alone flagged 129 and 57 normal channels (off-air and blacked-out feeds) and missed event channels whose placeholder is the channel name or one generic word. Average block length, distinct titles per day and venue text did not separate event channels from normal ones, so they are not used. The rules below replace the first guess of points and scores.

Placeholder time is programme time whose title is a filler ("Next Event Coming Soon", "SIGN OFF", "Channel No Longer Available", "To Be Announced", "No Event", "TBA", "Event Not Started", "Coming Soon"), equals the channel name (ignoring case and punctuation), or is one generic word such as "Pay-Per-View". The filler list is one small data list in `Get-ChannelForgeEventChannelCandidate.ps1`.

| Signal                                                                                                                                                      | Where              | Result                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ | -------------------------------------------------------------------------------------------------------- |
| Name has PPV, Pay Per View or Pay-Per-View                                                                                                                  | channel name       | `high`, always; `medium` only with 3 or more different real programmes and placeholder time at most half |
| Name has an event word (PPV, Pay Per View, Event, Events, UFC, WWE, AEW, Boxing, Fight, Wrestling, Live Event) and placeholder time over half of guide time | name and guide     | `high`                                                                                                   |
| Name has an event word and real programmes                                                                                                                  | name and guide     | `medium`                                                                                                 |
| Name has an event word and no programmes at all                                                                                                             | channel name       | `medium`, reason "no guide data"                                                                         |
| No event word, category is a sports category, and most guide time is in single blocks of 6 hours or more                                                    | category and guide | `low`                                                                                                    |

Rules for the result:

- A channel that matches none of the rows is not reported. A normal channel with filler and no event word is not flagged.
- Each rule adds one plain reason, for example `name has "ppv"; 78% of guide time is placeholder titles`.
- Only `high` will act (slice 3). `medium` and `low` keep their normal guide and are only listed.
- The 6 hour block limit for `low` is a first guess [UNVERIFIED]; it was not tuned on the measured guides.

### False-positive and false-negative risk (plain)

- Pay-per-view movie channels carry PPV in the name and many long blocks, but are not live event channels. The detector may rate them high. They would show the channel name instead of their schedule until the user forces them off.
- A normal channel whose brand has "Event" or "Main Event" in the name gets weak points only. The "Against" signal and the guide pattern should keep it low.
- Channels that sign off at night with "Off Air" get at most one point.
- A provider may dump unrelated channels into a group named PPV or Events. That group signal is medium, not strong.
- Event channels with no keyword in the name ("Fight 4"), or with no guide at all, are missed or stay `low`. They keep their normal guide. The user can force one on with the optional override (slice 4); the detector never blocks that.
- A guide with no programmes for a channel proves nothing. It adds no points.

Because the detector can be wrong, nothing in slices 1 and 2 changes any output. Slice 3 acts automatically, but only on `high` channels and only with the fallbacks under "What fails safely".

### What the user sees

1. After a build, one more section in `output\reports\lineup-plan.md`, in the style of the category section. It always names the channels treated as event channels and why:

   ```
   ## Event Channels
   3 channels look like event channels: 1 high, 2 medium.
   Treated as event channels (high): PPV 1
   Listed only (medium, normal guide kept): Event 2, Fight 4
   - PPV 1 (group 'PPV', high, event guide applied): name has "PPV"; 3 sibling channels; 78% of guide time is "No Event"
   - Event 2 (group 'Sports', medium, normal guide kept): name has "Event" and a slot number; guide titles change by day
   ```

   Before slice 3 is built, the same section says "Nothing was changed."

2. `Get-ChannelForgeEventChannelReport` (like the category report, slice 4) lists every guess with its key, score and reasons.
3. Optional: `Set-ChannelForgeEventChannel -ChannelKey <64 hex> -Decision ForceOn` or `-Decision ForceOff`, or `-Clear` (slice 4). Same shape as `Set-ChannelForgeCategoryOverride`. Nothing needs it.
4. A channel forced off is treated as normal and reported as overridden. A channel forced on is listed as overridden.

### What is stored and where

| What                                                 | Where                       | Written by                               | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ---------------------------------------------------- | --------------------------- | ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Optional user override per channel (force on or off) | `state\event-channels.json` | `Set-ChannelForgeEventChannel` (slice 4) | Optional. Nothing waits on it. `version` exactly `event-channel/v2`. Records: `key` (64 hex), `name`, `decision` (`forceOn` or `forceOff`), `decidedAt`. One record per key. Strict reader copied in style from `Read-ChannelForgeCategoryOverrides`: a damaged file makes the reader throw and is never repaired or replaced. The build catches that throw (see "What fails safely"). A key no longer in the playlist is kept and listed as stale. |
| Detector results                                     | Nowhere                     | The build, each time                     | Recomputed from the build inputs. Not stored, so there is no stale guess to trust.                                                                                                                                                                                                                                                                                                                                                                  |

### What is hashed

Nothing, in slices 1 and 2. No new hash input, manifest field or hash type. The state file is read at build time, not copied into the candidate directory (an extra file fails `Test-ChannelForgeCandidateNamespace`, per the category note). Slice 3 adds event blocks to candidate `merged.xml` in the same way the name-only guide already does. [INFERENCE] The name-only path edits `$candidateXMLTVBytes` before they are written. Slice 3 must confirm the order against the candidate manifest and prove the same bytes come out twice from the same inputs.

### What fails safely

| Event                                                                          | Result                                                                                                                                                                                                                                                                                                                                             |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `event-channels.json` (optional override) damaged                              | The set command refuses and never repairs the file. In the build (the report block runs after publish inside try/catch, like the category block) it is one warning and the override is ignored. The automatic rule still runs on the detector alone; no channel is dropped and every channel the rule does not rate `high` keeps its normal guide. |
| Detector or summary throws                                                     | One warning. The build result and bytes are unchanged (same as the category and xguide blocks).                                                                                                                                                                                                                                                    |
| Channel has no guide programmes                                                | Name and group signals only. Confidence stops at `medium`, so the channel keeps its normal provider guide.                                                                                                                                                                                                                                         |
| Two guess rules disagree                                                       | Both reasons are shown. The score is the sum. Nothing is hidden.                                                                                                                                                                                                                                                                                   |
| Parse problem, missing start or end time, or time conflict on a `high` channel | The channel keeps its normal provider guide. It is never dropped. The report lists it and says why.                                                                                                                                                                                                                                                |
| Stale override record                                                          | Kept, listed as stale, nothing acts on it.                                                                                                                                                                                                                                                                                                         |

### Safety net and cost of a wrong guess (no human check)

Nobody approves a channel before it acts, so the design relies on these limits:

1. Only `high` acts. `medium` and `low` are listed in the report and change nothing.
2. Any parse problem, missing time or conflict falls back to the channel's normal provider guide. A channel is never dropped and `guide: null` is never created.
3. Nothing is hashed and no tvg-id changes, so identity and guide-id v1.0 are untouched.
4. The report always lists which channels were treated as event channels and why, so a wrong guess is visible.
5. The user can override a wrong guess with the optional override file (slice 4).

What a wrong guess costs: a normal channel wrongly rated `high` would show the channel name (and an event title when the provider guide has one) instead of its provider schedule. The channel stays in the lineup and keeps its stream and id. The loss is its programme listing until the guess is fixed. The design limits this by requiring a score of 6 or more, by the "Against" signal for normal TV patterns, and by capping confidence at `medium` when the channel has no guide signal. A missed event channel (false negative) costs nothing new: it keeps its provider guide as today.

## B. Where times, venue, city and carrying channels come from

No source here needs permission from AEW or any league. All claims about outside terms are [UNVERIFIED]. No outside source is named or approved by this note.

### What each source can and cannot supply

| Field                | (1) Provider guide on the channel                                                                                          | (2) Same event on several channels                          | (3) Optional user correction                           |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------ |
| Title                | Yes. The provider's own text, not a verified fact.                                                                         | Yes, when channels use the same normalized title.           | Yes.                                                   |
| Start and end        | Yes. As the provider claims. A guide time with an offset keeps it. See the zone note below.                                | Agreement or conflict between channels and guide sources.   | Yes.                                                   |
| Venue and city       | Only if the provider writes them in the description (`Description` is free text; XMLTV has no venue field). Often missing. | Only if some carrier's description has them. Often missing. | Yes, typed by the user.                                |
| Carrying channels    | Only this channel.                                                                                                         | Yes. This is the one source that can list every carrier.    | Only if the user lists them. Not needed; use source 2. |
| Match or card detail | No. At most one title per slot.                                                                                            | No.                                                         | Only if typed. Left out by default.                    |

Honest limits:

- Venue and city are often missing from guides. When they are missing, they stay unknown. We never fill them from a guess, from the channel name, or from the user's time zone.
- Descriptions can be read for venue and city only through a Stage B pattern rule that the user accepted on real samples (`GuideEventPatternRule`, `CanPublish = false` until accepted). Until then slice 3 copies no venue or city. This is slower but never invents data.
- **Zone note.** `Read-ChannelForgeXmltvDocument.ps1` keeps the offset when a guide time has one (`+0100`). A guide time with no offset is read as UTC, which is a guess. The neutral event must mark such a time as zone unknown, not proven UTC. [INFERENCE] Whether the offset survives the merge step was not checked. Slice 2 must confirm it before it writes `shownZone`.
- A provider guide often shows the real event only shortly before it starts, and "No Event" before that. A channel can therefore have fillers today and a real event tomorrow. The times are the provider's claim either way.

### B1. The user's own provider guide

This is the main source because it is already in the build. It needs no network and no new rights beyond what the user already has. The detector (part A) and the time agreement (B2) both read the same `Programme` objects. Filler titles are never events.

### B2. The same event on several channels

What exists: `Get-ChannelForgeXguideReport` compares the **same channel id across different guide sources** (for example the same channel in two guides): 15-minute tolerance, exact normalized title, findings such as `StartShift` and `TitleDiffers`. It never compares two different channels, and its findings are cut to five per kind, so a later step cannot rely on them as data.

What slice 2 adds (small, one pure function):

- Over the `high` event channels only, group programmes by exact normalized title with start times within the same 15 minutes. Every channel in a group is a carrier. The list of carrier keys is the answer to "which channels carry the event".
- Times agree when all carriers are within the tolerance. The agreed start and end are the most common exact values. A tie is not broken: the event is marked `conflict`, both values are kept, and slice 3 uses each channel's own times. Where channels disagree on a time, each channel keeps its own time and the report marks the conflict. No question is asked.
- Confidence: `high` when two or more different guide sources agree (independent). `medium` when two or more channels of one guide agree (they may copy one error, so this proves consistency, not truth). `low` for a single channel.
- Reuse, not copy: the tolerance and the normalized-title rule in `Get-ChannelForgeXguideReport` are two lines. Slice 2 extracts them once into one private helper that both functions call, and proves the xguide report is unchanged. [UNVERIFIED] Whether a test already pins the xguide output.
- Exact title match only. The fuzzy cross-channel matcher in `_pr205` (`Get-ChannelForgeCrossChannelProgrammeCorrelation.ps1`, 339 lines) is a later option, not taken now.

### B3. A user-confirmed correction (fallback)

If the guide has wrong times or no venue, the user may supply the fact. This is optional and nothing waits on it. It is the only source that can supply everything, and it carries the user's responsibility for the data. It needs a small strict state file, `state\event-corrections.json`, keyed by channel key plus the original title and start the build saw, so a correction that no longer matches is listed as stale and never applied silently. It is not part of slices 1 to 4 (see D). Provenance is `user`.

### Rights questions that must be answered before any online source is used

A source passes only when every line is written down and answered. Until then it is [UNVERIFIED] and unused. Public access is not permission.

1. Who owns the data, and which page or document states the terms? Date checked.
2. Is automated reading allowed in writing? If the terms are silent, the answer is no.
3. May we cache it, for how long, and may we show it in a guide?
4. Rate limits, key or account needs, cost, and who pays.
5. Is redistribution implied? A guide the user passes on may reach people who never agreed to the terms.
6. Does the data change after we read it? What counts as stale? Is a missing listing a cancellation? (Default: no.)
7. Secrets: no key, token or signed link is printed, stored in a report, or put in a state file in plain text (`SECURITY.md`).
8. Transport: any online read uses the existing bounded HTTPS transport (`docs\adr\0014-secure-bounded-https-acquisition-transport.md`) and the evidence boundary, not a new downloader.
9. Accuracy: what does the source say about its own accuracy, and what do we show when it is wrong?
10. Who approves. The owner records the decision.

## C. The neutral event shape

Every source in part B is turned into this one shape. It has no company or sport field. It is a build-time value, not a stored file, in slices 1 to 3.

| Field         | Meaning                                                                                                                                                      |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `title`       | Safe text, at most 200 characters.                                                                                                                           |
| `start`       | `utc` (ends in `Z`) and `shownZone`: the offset the source showed (for example `+01:00`), or `unknown` when the source showed none.                          |
| `end`         | Same two parts as `start`.                                                                                                                                   |
| `venue`       | The place name, or unknown.                                                                                                                                  |
| `city`        | The city, or unknown.                                                                                                                                        |
| `channelKeys` | Sorted list of carrying channel keys (64 hex). At least one.                                                                                                 |
| `confidence`  | `high`, `medium` or `low`, from the agreement rule in B2.                                                                                                    |
| `provenance`  | For each field above: which source said it (`provider-guide`, `cross-channel`, `user`), with the guide source id and channel key. No online kind exists yet. |
| `card`        | Optional list of segments or bouts, each with a source-scoped reference. Left out by default. Never filled in slices 1 to 3.                                 |

Unknown is not empty. Each field is one of three states:

- `known`: a value and its provenance.
- `unknown`: not observed. There is no value and nothing is inferred.
- `conflict`: sources disagree. All values are listed with their sources. Nothing is chosen.

Minimum for a guide entry (owner rule, Nov 14, 2026): an event needs only a title and a start time. With those two, the guide entry is always created. When the end is unknown, the entry runs to the next event on that channel, or for a default length when there is no next event. Venue, city, extra carrying channels and card detail are bonuses: they are added to the entry's description when known and left out when unknown. A missing bonus field never stops an entry from being written and never lowers an event below being usable. More known fields only make the entry richer.

Rules kept from #204: absence is not cancellation, no canonical bout id, and a changed event is a new observation. The slices build no revision store; each build computes events fresh from the guides.

## D. Slices

All slices share contract event-channel/v2. Sizes are product lines only. Each slice adds a few user-visible tests. If a slice with its tests passes about 300 changed lines, stop and say so. Slices 1 to 3 are the whole automatic feature. Slice 4 is an optional override.

| #            | Slice                                                                                                                                                                                                                                                                                                                                    | Product lines | What the user gets                                                                                                                                |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1            | Pure detector `Get-ChannelForgeEventChannelCandidate`, summary lines, one report block in `scripts\Build-Lineup.ps1`. Report only. Nothing hashed. No state file.                                                                                                                                                                        | About 110     | The "Event Channels" section with confidence and reasons, for all three levels.                                                                   |
| 2            | Agree on times across `high` channels (B2): one pure function, one shared helper extracted from the xguide report, summary lines. Per-channel times kept, conflicts marked. Report only. Nothing hashed.                                                                                                                                 | About 130     | A section listing each event, its agreed times, every carrying channel, and conflicts.                                                            |
| 3            | Build slice: the automatic apply rule plus the per-channel event guide. Event blocks from slice 2 plus channel-name blocks for every gap, written through `Add-ChannelForgePlaceholderGuide`, guide id `ChannelForge-<first 32 hex of key>` (the `OwnPlaceholder` rule). Report lists every channel treated as an event channel and why. | About 145     | `high` event channels get a guide with the event title and times, venue and city only when known, and the channel name in gaps. No approval step. |
| 4 (optional) | Strict reader for `state\event-channels.json`, `Set-ChannelForgeEventChannel -Decision ForceOn` or `ForceOff`, `Get-ChannelForgeEventChannelReport`. An override only; nothing waits on it. Build after slice 3.                                                                                                                         | About 90      | Force one channel on or off if the detector guessed wrong.                                                                                        |

Later, only if real use shows the need: B3 corrections (about 100 lines); an accepted Stage B rule to read venue and city from descriptions; sign-off and cutoff-hour controls; a browser page to pick event channels (`GUIDED-SETUP-BROWSER-DESIGN-NOTE.md`).

Slice 3 reuse and rules:

- `Add-ChannelForgePlaceholderGuide` is extended or split once so it can take blocks per channel. The day-block rule stays for plain `OwnPlaceholder` channels, byte for byte.
- A new pure function `Get-ChannelForgeEventProgrammeBlocks` turns events and the build window into ordered blocks, without overlap and without holes.
- A conflicted event uses each channel's own provider times. Unknown venue and city write no text.
- Event title, venue and city pass through `ConvertTo-ChannelForgeGuideSafeText` and the existing XML escape.
- No tvg-id is rewritten, no channel is dropped, no network, no transport code. A channel whose event step fails keeps its normal provider guide, so `guide: null` is never created by this feature.
- Automatic apply rule (lives here): only a channel rated `high` gets event blocks. `medium` and `low` channels keep their normal provider guide and are only listed. A channel with a parse problem, a missing start or end time, or an unresolved conflict keeps its normal provider guide. The apply step reads the optional override file (slice 4) if one exists, but never waits for it.

### Frozen contracts it must not touch

guide-id v1.0, raw digest projections, M3U entry byte format (`ConvertTo-ChannelForgeM3UEntryBytes`), `BuildIdentityInput`, blocker-2-contract/v7, accepted-state code, transport and trust code. If a later step wants an event to change a hash or gate acceptance, that needs its own contract and owner approval.

## E. #204 and #205 in short

PR #204 (`_pr204`) holds a synthetic-only v2 card proposal.

- **Keep (general ideas):** an event with title, start and end; optional card detail with source-scoped references; "unknown is not empty"; separate clocks with UTC only when proven; "absence is not cancellation"; a written gate before a source is used (the rights list above).
- **Drop:** the fixed `AEW` promotion, `AEWEventEvidenceProposal/0.1`, every `aew.*` name, the `Availability` block (carriage comes from the user's provider, and slice 2 finds it from the guides), the full v2 envelope for now, and a wrestling-only schema.

PR #205 is a draft and `_pr205` is a copy. Do not run it or copy it into `src`. Compared with main:

| Part of #205                                                             | Verdict                                                                                                                                                                                           |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Extended XMLTV comparer (`Compare-ChannelForgeXmltvGuides.ps1`)          | Duplicates main (`Get-ChannelForgeXguideReport.ps1` is the build's comparer).                                                                                                                     |
| Cross-channel correlation                                                | Usable later, cut to report only, after slice 2 proves the exact-title rule is not enough.                                                                                                        |
| Alias proposals, knowledge store, scheduled comparison                   | Not wanted. A second durable store conflicts with `DURABLE_STATE_PERSISTENCE_MATRIX.md` and ADR 0009; scheduled comparison adds a second path in the refresh script. Keep as draft, do not merge. |
| Stronger safe-text redaction (`ConvertTo-ChannelForgeGuideSafeText.ps1`) | Usable after a check, as its own small change before slice 3. Risk: the path pattern could hide a title such as `/Round 1/Final`. Needs a test with real event titles.                            |
| GUI category page, wrestling e2e                                         | Byte-identical to main. Nothing to take.                                                                                                                                                          |
| Intent-fit audit doc                                                     | Usable as a process rule.                                                                                                                                                                         |

#205 also changes the XMLTV reading side (`Read-ChannelForgeXmltvDocument.ps1`, `Import-ChannelForgeXmltvSource.ps1`). A reviewer must prove the raw digest output is unchanged before any of that is taken. Nothing from #205 is needed for slices 1 to 3.

## Owner questions

Answered by the Nov 14, 2026 decision (removed): whether the user confirms a channel before it acts (no, fully automatic on `high`); whether disagreeing times are kept per channel with a marked conflict (yes, automatic); and venue and city (unknown unless a provider guide supplies them, no online source until its rights list is answered, free sources and provider guides only). These are rules now, not questions.

1. When no event is on, show the channel name (the name-only guide behavior), not the provider's filler titles? Recommend yes.
2. Take the #205 safe-text hardening as its own small change before slice 3, with real event-title tests? Recommend yes.
3. Is `high` (score 6 or more) the right bar for acting with no human check? Recommend yes for the first release; the report-only slice 1 on your real lineup is the test. Raise the bar if it flags a channel you do not want treated as an event channel.

## Not verified

- No code was run. No test was run. The tree has no git history; which side changed a file was inferred by comparing `_pr204`, `_pr205` and main.
- The signal points and the 50 percent, 2 hour and 60 minute limits are first guesses. No real provider guide was read for this note, so the filler title list and the false-positive rates are not measured.
- Whether the XMLTV offset survives the merge step, and whether a test already pins the xguide report output.
- The exact way `$allProgrammes` is joined to a channel for the detector (the existing M3U to guide binding rule is named, not traced end to end).
- Whether `Build-My-Lineup.ps1` (the slice 3 wiring point) and the headless `Build-Lineup.ps1` (the report wiring point) both need the same calls.
- Whether `Resolve-ChannelForgeGuideChoices.ps1` can take a fifth choice, or whether event channels need their own check before it runs. A high-confidence event channel that also has a `BindTrueMatch` decision: the safe default is that the explicit user decision wins and the channel keeps its normal guide, with a line in the report. [UNVERIFIED]
- `INTENT_FIT_AUDIT.md` was read in part (lines 1 to 140). The #204 fixture JSON was read in part. The GUI files that #205 changes were only compared with main for sameness.
- All outside terms, rights and costs in part B. No source was checked.
- `npx prettier` was not run on this note.
