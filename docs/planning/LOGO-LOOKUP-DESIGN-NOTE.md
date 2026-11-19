# Design note: find a public https logo for channels that have none (logo-lookup/v1)

Design only. No product code or test was changed. Nothing was run. Nothing was fetched from the network. Facts about this tree come from reading it on Nov 19, 2026. Facts about the public collections come from my own knowledge and are labeled UNVERIFIED.

## The problem

Plex only shows guide logos served over public https. Many channels have no logo, or a private or http one. Today the publish step uses a pin, then the provider logo, then the group default (`Get-ChannelForgePublishLogo`). A channel with none of those ships without `tvg-logo`. The owner wants a real logo found for it, without the build touching the network.

## Owner decisions already made (not reopened)

- Plex ignores http. Public https only.
- Link only. No download, copy, cache or hosting of images.
- No paid service or feed. Real logos, not placeholders.
- A channel is never dropped. The build needs no network.
- A pinned logo always wins. The provider's own public https logo is used first.

## What exists today (read in this tree)

| Piece | Job |
| --- | --- |
| `Get-ChannelForgeLogoStatus` | One URL in: `Public`, `Empty`, `NotHttps`, `PrivateAddress`. String check only. |
| `Get-ChannelForgePublishLogo` | Per channel: pin (by `TvgId`) wins; else a `Public` source logo is kept; else group default; else empty. Returns `DisplayName`, `Logo`, `Replaced`, `TvgId`, `Pinned`. |
| `Get-ChannelForgeGroupDefaultLogo` | Optional group name to URL map from provider config. |
| `Get-ChannelForgeLogoPinMap` | One read per build of `state\logo-pins.json`. Corrupt file gives no pins and a warning. |
| `Set-ChannelForgeLogoPin` | Owner command. Pin must be public https, no user info. |
| `Normalize-ChannelForgeName` | Trims, strips quality tags (HD, 4K...) and backup markers, collapses spaces. It does NOT change case, punctuation or accents. |

The lookup goes between "source logo is Public" and "group default". It adds one more source and changes no existing rule.

## 1. Where candidate logos come from

All four are UNVERIFIED in detail. Link shapes below are from memory and must be checked by the owner before the first refresh.

| Collection | Keyed by | Link shape (UNVERIFIED) | Not confirmed |
| --- | --- | --- | --- |
| iptv-org channel logos (the iptv-org database, `logos` list) | Channel ID, for example `ESPN.us`, plus a feed ID | A full `https://...` URL per logo entry, hosted on a third-party image host | License of the images (they are trademarks of the channels; the list itself is a data project). Link stability: entries point to many hosts and can break. |
| tv-logo/tv-logos (GitHub) | Folder by country, file name from the channel name (for example `countries/united-states/espn-us.png`) | `https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/...` or the GitHub Pages form | File names are names, not IDs, so matching is by name. License unclear (trademarked artwork). A file can be renamed or moved on `main`. |
| Picons | Mostly by satellite service reference or channel name (for Enigma2 boxes) | Usually a GitHub raw or release path, many variants | Keys are satellite service IDs, not our IDs. Poor fit for IPTV channel IDs. Link and license unknown. |
| xmltv-se channel-logos | Channel name or XMLTV channel ID, mainly Swedish channels | A raw GitHub or site path | Coverage is regional. Keys and license unknown. |

Recommendation: trust iptv-org first. Reason: it is keyed by channel ID, which is the key our lineup already carries, so a match needs no guessing. tv-logos second, by exact normalized name, for channels iptv-org lacks. Picons and xmltv-se: skip for now (wrong key or regional).

First slice: the refresh command (section 2) reads only iptv-org and writes the data file. Nothing else.

Rights: every link is to a trademarked logo. Link-only keeps ChannelForge from copying anything, but the owner should know a host can remove an image at any time. The data file records the source collection per entry so one source can be dropped cleanly.

## 2. How the build stays offline

### Data file

`data\logo-lookup.json`, tracked in git, reviewed before merge. One job: map a key to an https link.

```json
{
  "Version": "logo-lookup/v1",
  "Source": "iptv-org",
  "RefreshedUtc": "2026-11-19T12:00:00Z",
  "ById":   { "ESPN.us": "https://example.com/espn.png" },
  "ByName": { "ESPN": "https://example.com/espn.png" }
}
```

- `ById` keys are exact, case-sensitive (same as pins and guide ids).
- `ByName` keys are the output of `Normalize-ChannelForgeName`, then lower-cased with invariant culture. See rule 4 in section 3 for why the extra lower-casing is needed.
- Every link must pass `Get-ChannelForgeLogoStatus` as `Public`. The build re-checks at read time (same as the group default does), so a hand-edited bad link is ignored with a warning, never published.

### Build side

New private reader `Get-ChannelForgeLogoLookupMap` in the style of `Get-ChannelForgeLogoPinMap`: one read per build, missing file gives empty maps, corrupt file gives empty maps and a loud warning, never throws, never writes, no network. Passed to the publish step like `LogoPin`.

### Refresh command (separate, owner-run)

`Update-ChannelForgeLogoLookup`. Never called by a build, a test or a candidate run. It would:

1. Download the iptv-org logo list from its public https address (the only network use in the whole feature).
2. Keep one link per channel ID: skip entries that fail the rules below; if one ID has several links, keep none and list the ID (no silent choice).
3. Build `ByName` from the channel names in the same list, only where one name maps to exactly one link. Ambiguous names are left out and listed.
4. Write the file atomically (temp then move), reusing `Write-ChannelForgeSourceEnrollmentAtomicJson`'s pattern. Print counts added, changed, removed since last time, so the owner can review the diff.
5. Not verify that an image still loads. Link-only; a dead link is a known limit (see open decisions).

It must refuse:

- any link that is not `https` (use `Get-ChannelForgeLogoStatus`);
- private, loopback, link-local or local-name hosts (same helper);
- any host not on an allow-list kept in the command (start with the hosts the owner approves after reading the first dry run);
- a link with user info;
- a list that is empty or shrinks by more than half (a bad download must not wipe good data; the old file stays).

It has a `-WhatIf` dry run that writes nothing. A failure leaves the old file as it was. It never deletes a file it did not write.

First slice: the data file shape plus the build-side reader and a hand-written sample file. No refresh command yet, so the owner can see the build effect before any download code exists.

## 3. Matching rules, in order

Applied per channel inside the publish step, first match wins:

1. Pinned logo (by `TvgId`). Existing.
2. Provider logo, if `Public`. Existing.
3. Exact channel ID: the channel `TvgId` is a key in `ById`. New.
4. Exact normalized-name match: `Normalize-ChannelForgeName` on the channel display name, lower-cased invariant, is a key in `ByName`. New. The normalizer keeps case, so the lower-casing is a small extra step; case alone must not stop a match.
5. Otherwise none. Group default applies, then empty. Existing.

Rules for matching:

- No fuzzy guesses. No partial, prefix, edit-distance or "contains" match.
- Name matching (rule 4) applies only when the channel has a non-empty name after normalizing.
- Ambiguous name: if two or more channels in this build normalize to the same name but carry different guide IDs, or the lookup file has no single link for that name, no link is chosen. The channel is listed in the existing logo report as `LookupAmbiguous` with its name. It then falls to the group default.
- A looked-up logo never overrides rules 1 or 2. It only fills a gap.
- A channel with no `TvgId` can still match by name.
- Never drops a channel. Never edits `TvgId`, name or group.

Out of scope: sports. League and team logos (NFL, NBA, team marks, event channels) are a separate source with their own naming and rights, and the existing team alias code is a separate concern. One line only: they come later, from their own source.

First slice: rule 3 (ID match) only. It needs no name logic and no ambiguity handling. Rule 4 is the second slice.

## 4. Report and fingerprint

Report (extends `Get-ChannelForgeLogoReport`, same style as pins):

| Added field | Meaning |
| --- | --- |
| `LookedUp` | Channels published with a looked-up logo. Counted apart from `Replaced` (group default) and `Pinned`. |
| `LookupStatus` | `None` (no file), `Ok`, or `Corrupt`. |
| `LookupIgnored` | Entries not used, each with a plain reason (not public https, bad key). |
| `LookupAmbiguous` | Channel names that matched more than one candidate, listed (up to 20, like the other lists). |

Warning text gets one line only when there is something to say, for example `Logo lookup: 41 channels got a looked-up logo, 3 ambiguous (NAME1, NAME2, NAME3).` The `Pinned` and `Replaced` wording stays as is. The publish result gets one more property, `LookedUp` (bool), next to `Pinned`.

Presentation fingerprint: the fingerprint already uses the published logo, so a looked-up logo enters it automatically, like a group default or a pin. Nothing new is added to `BuildIdentityInput`. The lookup file is not an input; its effect shows only through the published logo.

- Loud: a lookup changes the published `tvg-logo` and so the fingerprint and candidate manifest hash for each changed channel. Intended.
- With no lookup file, or no match, every byte and hash equals today's. The slice that wires the lookup must prove this with a golden test.
- `tvg-id` is never changed. Lookup reads `TvgId` as a key and never writes it. Guide-id contract v1.0 is not touched. The raw M3U and XMLTV digest projections keep the source logo text.

First slice for the report: the `LookedUp` count and `LookupStatus` only.

## 5. Owner decisions still open

| # | Question | Recommendation |
| --- | --- | --- |
| 1 | Which collection first? | iptv-org (keyed by ID). tv-logos second by name. Skip picons and xmltv-se. |
| 2 | License comfort: logos are trademarks, the lists' own licenses are UNVERIFIED. Is link-only enough for the owner? | Yes for a private home lineup, after the owner reads each collection's license page once and records the result in the data file's `Source` note. Do not ship the data file publicly until that is done. |
| 3 | How often to refresh? | Manual only, about monthly, or when a channel looks wrong. Never scheduled in v1. |
| 4 | Who reviews the data file? | The owner, from the refresh diff counts and a sample, before merging. One reviewer; no extra process. |
| 5 | Allow-listed hosts | Decide from the first dry-run list. Start with the smallest list that covers most entries. |
| 6 | Dead links (a host removes an image) | Report only; no build-time check (needs network). The owner re-runs the refresh. Optional later: a separate `Test-ChannelForgeLogoLookup` command that checks links on demand. |
| 7 | Data file in git (reviewed, shared) or in `state\` (local)? | In git under `data\`, as the task says. Records only public links, no private data. |
| 8 | Should the XMLTV `<icon>` follow the same lookup? | Later, after the M3U step proves out (same answer as the Phase 1 note). |
| 9 | Name matching needs case folding on top of `Normalize-ChannelForgeName`. OK? | Yes. Without it, "ESPN" and "Espn" would miss. Fold only case, nothing else. |

## Slices (smallest first)

1. Data file shape, `Get-ChannelForgeLogoLookupMap` reader, hand-written sample, and rule 3 (ID match) in the publish step, plus `LookedUp` and `LookupStatus` in the report. Prove no-file gives today's bytes.
2. Rule 4 (exact name) and `LookupAmbiguous`.
3. `Update-ChannelForgeLogoLookup` refresh command with the refusals above and `-WhatIf`.

Each slice stays under the 300-line budget. Slice 1 first so the owner sees the effect with a hand-written file before any download code exists.

## Reuse

`Get-ChannelForgeLogoStatus`, `Get-ChannelForgePublishLogo` (add one parameter, like `LogoPin`), `Get-ChannelForgeLogoPinMap` (pattern for the reader), `Get-ChannelForgeLogoReport`, `Normalize-ChannelForgeName`, `Write-ChannelForgeSourceEnrollmentAtomicJson` (atomic write; accepts other file names is UNVERIFIED), `Get-ChannelForgeWebRepositoryRoot`.

## Not verified

- Everything about the four public collections (keys, link shapes, licenses, stability).
- That `Write-ChannelForgeSourceEnrollmentAtomicJson` can write under `data\` (its allowed root is `state\` in the pin code).
- That `Get-ChannelForgeLogoReport` can take new fields without a test or hash change (not read in this task).
- No code or test was run.
