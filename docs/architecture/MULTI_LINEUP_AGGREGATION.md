# Multi-Lineup and Guide Aggregation

This note explains how ChannelForge turns several M3U playlists and one or more XMLTV guides into one accepted output. It describes what the code on `main` does today. It does not describe plans. Plans are in the last section.

Terms: an M3U playlist is a text file of channels and stream URLs. An XMLTV guide is an XML file of channels and programmes (the shows). Each section ends with a "Where this lives" line that names the code.

## What a playlist gives us

For each channel entry, the M3U reader keeps:

- the stream URL
- the display name
- the group (`group-title`)
- the provider's `tvg-id` hint, plus `tvg-name`
- the logo (`tvg-logo`)
- the provider channel number (`tvg-chno`), kept as raw evidence
- the source: which provider and playlist it came from

Where this lives: `Read-ChannelForgeM3UReader.ps1`, `Import-ChannelForgeM3UPlaylist.ps1`, the `Channel` class in `Classes\Channel.ps1`.

## What a guide gives us

An XMLTV guide gives:

- channel identities (the XMLTV channel id)
- programmes, each with a title, a description, start and end times, and categories
- provenance: which guide source each programme came from

Where this lives: `Import-ChannelForgeXmltvSource.ps1`, `Read-ChannelForgeXmltvDocument.ps1`, the `Programme` class in `Classes\Programme.ps1`.

## Words we use

- **Canonical channel.** The one visible channel in the final lineup. Several playlist entries can lead to one. In code this is a survivor of `Merge-ChannelForgeLineup`, after name cleanup and alias lookup.
- **Source variant.** One playlist entry that was folded into a canonical channel. It stays on record as a duplicate with a warning. It is not shown.
- **Guide binding.** The link that says "this playlist channel uses that guide channel." Today a binding is only made when the `tvg-id` matches the XMLTV channel id exactly.

Where this lives: `Merge-ChannelForgeLineup.ps1` (canonical and variants), `Resolve-ChannelForgeM3UXmltvBinding.ps1` (bindings).

There is also a second, different "binding" word. A source set can say which guide serves which playlists. That is set with `Set-ChannelForgeSourceSetBinding.ps1`. See step 6.

## Why many playlist entries are not many channels

Two providers may both carry ESPN. After cleanup, both entries get the same identity key. The first one stays. The other is marked `IsDuplicate`, gets a warning, and is left out of the merged output. It is not thrown away silently. The result reports `DuplicateCount` and a `Duplicates` list.

Where this lives: `Merge-ChannelForgeLineup.ps1`.

## Why many guide entries are not many programme rows

Duplicate rows merge only inside one guide. The group key is the guide source ID plus the guide channel id (the binding key), then start time and end time.

- If the show facts are identical, the rows become one programme. It is marked `DuplicateMerged`, and every contributor is remembered.
- If the facts differ (for example, a different title), nothing is picked. Both are kept, marked `Conflict`, and the group is reported as `NeedsReview`.

Where this lives: `Merge-ChannelForgeXmltvProgrammes.ps1`, `Resolve-ChannelForgeProgrammeBinding.ps1`.

Limit: two different guides never merge. Their programmes get different binding keys, so each guide keeps its own channel in the XMLTV output, even if the channel ids match. `ConvertTo-ChannelForgeXmltvBytes.ps1` writes one channel per binding key. Where this lives: `New-ChannelForgeProgrammeBindingKey.ps1`.

## How ChannelForge tells channels apart

| Kind                 | What the code does today                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Identical channels   | Same `tvg-id` (or, with no `tvg-id`, same cleaned name). Treated as one channel. The first wins.                                                                                                  |
| Regional variants    | No detector. The `Channel` class has a `Region` field, but nothing fills it or reads it. Two regional feeds with different `tvg-id` values stay as separate channels. Same `tvg-id` merges.       |
| Alternate feeds      | Only the words Backup, Alt and Alternate are removed from names. After that, the entry usually matches the main channel and is a duplicate. There is no separate "alternate feed" type.           |
| Event channels       | Detected by `Get-ChannelForgeEventChannelCandidate.ps1`. It scores names like PPV 1 or UFC, and how much of the guide is filler like "To Be Announced." Output is high, medium or low confidence. |
| Ambiguous candidates | Never guessed. They are held for review and get no guide until you decide. See steps 5 and 7.                                                                                                     |

Categories use a related rule set. A name word and a provider group word must not disagree. If they do, the result is `conflict` and no category is set. Where this lives: `Get-ChannelForgeChannelCategory.ps1`.

Where this lives (names): `Normalize-ChannelForgeName.ps1`, `Resolve-ChannelForgeAlias.ps1`.

## Merging many playlists, step by step

1. **Order the sources.** Sources are sorted by a stable `OrderKey`. Local files without one are sorted by path. The same inputs always give the same order. Where this lives: top of `Merge-ChannelForgeLineup.ps1`.
2. **Give each source a stable ID.** The ID is a hash of provider, playlist name, kind and position. Each channel is stamped with it. Where this lives: `Get-ChannelForgeLogicalSourceId.ps1`.
3. **Clean the names.** Quality tags like HD and 4K are removed. Backup, Alt and Alternate are removed. Original names are kept for audit. Where this lives: `ConvertTo-ChannelForgeNormalizedChannel.ps1`, `Normalize-ChannelForgeName.ps1`.
4. **Apply aliases.** An exact, case-insensitive match against the alias file swaps in the canonical name. There is no fuzzy matching. Where this lives: `Resolve-ChannelForgeAlias.ps1`.
5. **Remove duplicates.** The key is the lowercase `tvg-id` when there is one. Otherwise it is the lowercase display name. The first channel in the step 1 order wins. Channels that shared a key are also recorded as `IdentityCollisions`, so the guide step can refuse an automatic bind for them. Where this lives: `Merge-ChannelForgeLineup.ps1`.
6. **Number the channels.** A channel gets a number only if its group name equals a block category in the numbering blocks file. Numbers go up inside the block in name order. A full block leaves the extra channels unnumbered, with a warning. Output order is numbered channels first, then the rest by name. Where this lives: `Set-ChannelForgeChannelNumber.ps1`, `Merge-ChannelForgeLineup.ps1`.
7. **Build the saved source set.** Playlists and guides are saved as enrolled sources with a priority. They are read in priority order. Where this lives: `Invoke-ChannelForgeSourceEnrollment.ps1`, `New-ChannelForgeEnrolledCandidate.ps1`, `New-ChannelForgeCandidateProposalFromSourceSet.ps1`.

## Guide-to-playlist bindings

A guide is not applied to every playlist by default. You say which playlists it serves.

A saved binding for a guide is one of:

- **Selected playlists.** A list of playlist IDs.
- **All playlists.** `AppliesToAll`.
- **No playlist.** `ExplicitlyUnbound`. The guide is read, but its programmes are not published.
- **Disabled.** The binding is turned off.

Each binding has a revision number that goes up on every change.

Then the matching runs, per guide, against only the playlist channels that guide may serve:

| Result          | When                                                                                             |
| --------------- | ------------------------------------------------------------------------------------------------ |
| `Exact`         | The `tvg-id` equals the XMLTV channel id, byte for byte. Only one such channel, one declaration. |
| `Unbound`       | No `tvg-id`, or the id is not in the guide.                                                      |
| `NeedsReview`   | Two playlist channels share the id or the cleaned identity. Or the guide has the id twice.       |
| `OrphanedXmltv` | A guide channel that no playlist channel uses.                                                   |

Only `Exact` is publishable. Nothing is fuzzy-matched.

Where this lives: `Set-ChannelForgeSourceSetBinding.ps1`, `Get-ChannelForgeEnrolledCandidateRoute.ps1`, the guide loop in `New-ChannelForgeCandidateProposalFromSourceSet.ps1`, `Resolve-ChannelForgeM3UXmltvBinding.ps1`.

## How duplicate channels are handled

Two cases are different.

**Playlist duplicates.** Handled in step 5. First wins. The rest are listed.

**Duplicate guide ids.** When channels are held for review because they share a guide id, `scripts\Build-My-Lineup.ps1` uses a saved choice per channel. The choice file is `state\channel-decisions.json`. The channel is keyed by a hash of its stream URL, so renaming does not lose the choice. Four choices exist:

- `KeepWithoutGuide` (the default)
- `OwnPlaceholder`: a name-only programme per day
- `BindTrueMatch`: bind to a guide id you name, if it exists exactly once in the guide
- `ShareOnPurpose`: share the id, but only if every channel in the group says so

Strict mode (`-AmbiguousAction Cancel`) stops if any held channel has no saved choice. Nothing is published in that case.

Where this lives: `Read-ChannelForgeChannelDecisions.ps1`, `Resolve-ChannelForgeGuideChoices.ps1`, `Add-ChannelForgePlaceholderGuide.ps1`, `scripts\Build-My-Lineup.ps1`.

## Comparing guides

`Compare-ChannelForgeXmltvGuides.ps1` is a report. It does not change the output. It checks guide observations for agreement and conflict. Its findings include `ExactAgreement`, `TitleConflict`, `TimeConflict`, `ProgrammeMissing`, `StaleObservation`, `CoverageGap` and `AmbiguousCorrelation`. See [Guide comparison intelligence](GUIDE_COMPARISON_INTELLIGENCE.md).

## Worked example

Two playlists, A and B, both carry ESPN. One guide, G.

1. A has `ESPN HD`, `tvg-id="espn.us"`. B has `ESPN [FHD]`, `tvg-id="espn.us"`.
2. Names are cleaned. Both become `ESPN`.
3. Both share the key `id:espn.us`. A is first in order. A's entry stays. B's entry is a duplicate and is left out. `DuplicateCount` is 1. The pair is also in `IdentityCollisions`.
4. G has a channel `espn.us`. G is bound to playlist A and playlist B.
5. Because the two entries collided, the match is `NeedsReview` with reason `MultipleM3UChannelsShareNormalizedIdentity`, not `Exact`. It is not published automatically.
6. When run by `Build-My-Lineup.ps1`, ESPN is held. With no saved choice, a normal run keeps ESPN without a guide. You may then save `BindTrueMatch` with `espn.us`.
7. If A and B had different `tvg-id` values, they would be two channels. Each could bind exactly.

[INFERENCE] Step 5 follows from reading `Resolve-ChannelForgeM3UXmltvBinding.ps1` (the collision check runs before the exact check). It was not run.

## Not built yet (tracked in #153)

The planned design for the items below is in [Aggregation policies and channel numbers](AGGREGATION_POLICIES_AND_CHANNEL_NUMBERS.md). It is a decision record. Nothing in it is built.

- **User-chosen channel numbers.** Not found. `PreferredNumber` exists on `Channel` but nothing reads it. Numbers come only from numbering blocks by group. `tvg-chno` is stored as raw evidence only.
- **The six-choice duplicate decision.** Only four choices exist (`KeepWithoutGuide`, `OwnPlaceholder`, `BindTrueMatch`, `ShareOnPurpose`). The other two are not found. The choice is only reached through `Build-My-Lineup.ps1`.
- **Failover policy between providers.** Not found. No code searches for failover, backup order or stream health. The enrolled `Priority` only orders reading, and the first duplicate wins.
- **Regional variant detection.** Not found (see the table above).
- **Alternate feed as its own type.** Not found.
- **Merging programmes across different guides for one channel.** Not implemented. The merge key includes the guide source, so guides stay separate.
