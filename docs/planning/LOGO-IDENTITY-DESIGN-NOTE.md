# Design note: channel logo pins and pre-accept logo report (issue #41, first slices)

Contract: logo-identity/v1

Design only. No product code or test was changed. Nothing was run. Facts below come from reading this tree on Nov 14, 2026. Issue #41 is a large epic (providers, matching, caching, transformation history, fallback art). This note builds only the part that protects the one owner today.

## The problem

1. A channel has no logo or a wrong one, and the owner finds out only after the guide is loaded in the player. He needs to see it before he accepts a build, with a plain reason.
2. He picks a logo for a channel. It must stay chosen across rebuilds (a pin) and never be silently replaced.
3. Rights: nothing is copied, bundled or hotlinked from a catalog without a recorded license. The first slices fetch nothing from the network.

## What exists today

Issue #191 shipped the "public https logo" rule. A fingerprint test lane and a report already exist. All of it is in this tree.

| File                                                                              | What it does                                                                                                                                                                                      |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Private\Get-ChannelForgeLogoStatus.ps1                                            | One URL in, one word out: `Public`, `Empty`, `NotHttps`, `PrivateAddress`. String check only, no DNS, no network. Reuses `Test-ChannelForgeSafeHostAddress`.                                      |
| Private\Get-ChannelForgePublishLogo.ps1                                           | The one publish step. A `Public` logo is kept. Any other logo is replaced by the group default, or published empty. Returns `DisplayName`, `Logo`, `Replaced` per channel. Never drops a channel. |
| Private\Get-ChannelForgeGroupDefaultLogo.ps1                                      | Reads the optional `group_default_logo` map (group name to URL) from provider config. Schema: schemas\provider.schema.json.                                                                       |
| Private\Get-ChannelForgeLogoReport.ps1                                            | Counts `Public`, `Replaced`, `Empty`, `NotHttps`, `PrivateAddress`. Lists up to 20 channel names per bad status. Builds the `Logo check:` and `Logo default:` warning text.                       |
| Public\Export-ChannelForgeM3UPlaylist.ps1                                         | Calls publish step, writes the published logo into the entry, calls the report, emits `Write-Warning`.                                                                                            |
| Private\New-ChannelForgeCandidateManifest.ps1                                     | Feeds the published logo into the presentation fingerprint. The raw `Logo` text stays in the entry.                                                                                               |
| Public\New-ChannelForgeCandidateProposal.ps1                                      | Reads the group default and passes it to export and manifest. No `LogoReport` in its result.                                                                                                      |
| Private\New-ChannelForgeCandidateProposalFromSourceSet.ps1 (line 288)             | Builds a `LogoReport` and returns it as `LogoReport` (line 333) on the candidate result.                                                                                                          |
| scripts\Build-Lineup.ps1 (line 387)                                               | Reads `group_default_logo` and passes it to export.                                                                                                                                               |
| tests\unit\LogoStatus.Tests.ps1, LogoDefault.Tests.ps1, LogoFingerprint.Tests.ps1 | Pin status words, group default replacement, and that a public logo keeps today's fingerprint.                                                                                                    |

What the owner sees today: a `Logo check: N of M channels have no public https logo (...)` warning with names, and a `Logo default:` line when defaults were used. Both are `Write-Warning` text at build time.

What does not exist:

- No per-channel choice. The only override is a whole group default.
- No record of why a logo is what it is.
- A public https logo that is the wrong picture is never detected. Nothing can detect it without a catalog or the owner.
- Not verified: whether `LogoReport` reaches the review report the owner reads before accepting. It is a result property; no reference to it was found in the review markdown code.
- Not verified: where Add-ChannelForgePlaceholderGuide is called from (carried over from the #191 note).

Readers keep the raw source text (`RawLogo`, `IconNodes`). That is frozen and stays so.

## Design

### The pin

A pin says: for this channel, publish this logo. Key is the channel `TvgId`, exact and case-sensitive, as the guide-id contract v1.0 already treats ids. A channel with an empty `TvgId` cannot be pinned (the report says so).

Precedence at the publish step, highest first:

1. Pin (must pass `Get-ChannelForgeLogoStatus` as `Public`).
2. The source logo, if `Public`.
3. Group default.
4. Empty (no `tvg-logo`).

The reader checks every entry when it loads the file. If any entry is bad, the whole file counts as Corrupt and no pin applies (all or nothing, decided in slice 1); the next rule applies to every channel. It never drops a channel.

### Stored file

- Path: `state\logo-pins.json` (the `state\` folder is already local and git-ignored). Root from `Get-ChannelForgeSourceEnrollmentPaths`.
- One JSON file, UTF-8, written atomic (temp then move).
- Shape:

```json
{
  "Version": "logo-identity/v1",
  "Pins": [
    {
      "TvgId": "ESPN.us",
      "Logo": "https://img.example.com/espn.png",
      "Source": "user",
      "PinnedAtUtc": "2026-11-14T12:00:00Z",
      "Note": ""
    }
  ]
}
```

| Field       | Rule                                                                                     | User it protects                                         |
| ----------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Version     | Exactly `logo-identity/v1`. Anything else is unsupported.                                | Owner after a future format change.                      |
| TvgId       | 1 to 256 chars, no control characters, unique in the file.                               | A pin that hits one channel only.                        |
| Logo        | `Public` per `Get-ChannelForgeLogoStatus`. No user info. Stored as typed, never fetched. | Plex Apple TV, which refuses private logo links (#191).  |
| Source      | Only `user` in v1. A catalog value is rejected.                                          | Rights: nothing enters from a catalog without a license. |
| PinnedAtUtc | Set by the command, UTC, ISO 8601.                                                       | Owner reading the file later.                            |
| Note        | Optional text up to 200 chars. Never printed with the URL in warnings.                   | Owner remembering why.                                   |

No license field in v1: a `user` pin means the owner supplied the link himself and takes responsibility. A license record is needed only when a catalog source exists (later slices).

### The report (also logo-identity/v1)

`Get-ChannelForgeLogoReport` keeps every field it has today and adds:

| Added field | Meaning                                                                                               |
| ----------- | ----------------------------------------------------------------------------------------------------- |
| Pinned      | Channels published with their pin.                                                                    |
| PinsStatus  | `None` (no file), `Ok`, or `Corrupt`.                                                                 |
| PinsIgnored | Entries not applied, each with a plain reason (invalid link, duplicate id, bad entry).                |
| PinsUnused  | Pins whose `TvgId` matches no channel in this build (a renamed provider id would otherwise go quiet). |

Warning text keeps the existing `Logo check:` wording and adds one line only when there is something to say, for example `Logo pins: 3 applied, 1 unused (ESPN2.us), 1 ignored (X.us: not a public https link).` A channel with no public logo and no pin also gets the hint `Pin one with Set-ChannelForgeLogoPin.`

### Failure semantics

| Event                                    | Build                                                                                                                                                | Command (Set)                                                |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| File missing                             | No pins, no warning, status `None`. Output equals today's.                                                                                           | Creates the file.                                            |
| File corrupt (bad JSON, wrong version)   | Build continues, no pins applied, loud warning `Logo pins unreadable: <reason>. No pin was applied.` Status `Corrupt`. Never deletes or rewrites it. | Refuses. File bytes unchanged.                               |
| One bad entry (bad link, duplicate id)   | The whole file counts as Corrupt (all or nothing): no pin applies and the warning names the problem. Only hand editing can cause this.               | Refuses the bad input with a plain reason.                   |
| File is read-only or folder not writable | Build only reads, so it works.                                                                                                                       | Fails with a plain reason. Old file untouched. Honest error. |
| Write stops half way                     | Atomic move keeps the old file.                                                                                                                      | Same.                                                        |

Always true: no channel is dropped, `guide: null` stays, no network call, no file is deleted by a failure path.

### Frozen contracts: what changes and what does not

LOUD: a pin changes the published logo, so it changes the presentation fingerprint of that channel (the fingerprint already uses the published logo; tests\unit\LogoFingerprint.Tests.ps1 pins this) and therefore the candidate manifest hash. The M3U bytes change for that channel's `tvg-logo` value only. This is the same effect a group default already has. It is intended: the owner changed what is published.

With no pin file, or no pin that matches, every hash and every M3U byte equals today's. Slice 2 must prove this with a golden test.

| Frozen item                               | Effect                                                                                                            |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| guide-id v1.0                             | Not touched. Pin lookup reads `TvgId`; it never resolves or rewrites ids.                                         |
| Raw M3U and XMLTV digest projections      | Not touched. Readers keep the raw logo text.                                                                      |
| M3U entry byte format                     | Not touched. Only the logo value can differ.                                                                      |
| BuildIdentityInput, blocker-2-contract/v7 | No new field. The pin file is not an input. Its effect enters only through the published logo in the fingerprint. |
| Accepted-state, transport, trust code     | Not touched. The pin file is not accepted state and is not read by them.                                          |

Not verified: that nothing hashes the `LogoReport` object. Slice 2 checks this before adding fields.

## Reuse

`Get-ChannelForgeLogoStatus`, `Get-ChannelForgePublishLogo`, `Get-ChannelForgeLogoReport`, `Get-ChannelForgeSourceEnrollmentPaths` (state root), `Assert-ChannelForgeSourceEnrollmentPath`, `Write-ChannelForgeSourceEnrollmentAtomicJson` (atomic write; name says enrollment but it takes any path under an allowed root; to confirm in slice 1), `ConvertTo-ChannelForgeCanonicalJson`, `Get-ChannelForgeWebRepositoryRoot`. The `GroupDefaultLogo` plumbing through export, manifest and both proposals is the model for passing the pin map.

## Slices

Each slice stays under about 150 changed lines of product code.

| #   | Slice                                                                                                                                                                                                                               | Files                                                                                                                  | Protects                                                           |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| 1   | The stored file and two commands: `Set-ChannelForgeLogoPin` (add, replace, `-Remove`) and `Get-ChannelForgeLogoPin` (list). Private reader with the failure rules above. No build effect yet.                                       | New Private\Read-ChannelForgeLogoPin.ps1, Public\Set-ChannelForgeLogoPin.ps1, Public\Get-ChannelForgeLogoPin.ps1, psd1 | The owner can record and review pins safely. Corrupt file safe.    |
| 2   | Apply pins at the publish step. Pass the pin map like `GroupDefaultLogo` through export, manifest, both proposals and Build-Lineup. Golden test: no pins gives today's bytes and hash.                                              | Get-ChannelForgePublishLogo.ps1, Export, manifest, two proposals, Build-Lineup.ps1                                     | A pin survives every rebuild and is never silently replaced.       |
| 3   | Report: `Pinned`, `PinsStatus`, `PinsIgnored`, `PinsUnused`, the hint line. Make sure the owner sees it in the candidate review before accepting (verify first where `LogoReport` surfaces; add the one line there if it does not). | Get-ChannelForgeLogoReport.ps1, review output of the source-set proposal, single-source proposal                       | Owner sees missing, wrong-by-status and unused pins before accept. |

Order: 1, 2, 3. Slice 2 depends on 1. Slice 3 depends on 2. After slice 3 the owner can stop; nothing else is needed for the three problems above.

### Later slices (one paragraph, not designed)

Provider interface (`LogoAssetProvider`), candidate matching and the evidence ladder, local logo files with hash and rights record, a cache, XMLTV `<icon>` and `tvg-logo` reconciliation, transformation history, rollback of superseded pins, and generated fallback artwork. Each needs a named user problem first. A local file also cannot satisfy Plex Apple TV by itself because it needs a public https address, so it waits for a place to serve it.

## Owner questions

1. **Pin key.** Key a pin by `TvgId`, exact match? Recommend yes. It is the id the lineup already carries. Channels with no `TvgId` stay unpinnable until the id is fixed.
2. **Pin location.** `state\logo-pins.json` (local, not in git) or a tracked file under `config\`? Recommend `state\`. Back it up with the rest of `state\`. A tracked file would put private logo links in the repo.
3. **Corrupt pin file during a build.** Warn loudly and build with no pins (recommended), or block the candidate? Recommend warn. The owner never loses a channel and the warning is not silent. Blocking would stop a rebuild over a logo.
4. **Hash change.** Accept that a pin changes the candidate hash for the changed channel, as a group default already does? Recommend yes.
5. **Pin beats a good public logo.** Yes by design (the owner chose it). Confirm? Recommend yes.
6. **Logo link query strings.** Allow `?` in a pin link? Recommend allow (many logo hosts need it); reject user info only. A token in a link would be printed by nothing: warnings print channel ids, not links.

## Not verified

- No code or test was run. Every statement about existing behavior is from reading.
- That `Write-ChannelForgeSourceEnrollmentAtomicJson` accepts a file name other than the enrollment file.
- That `Get-ChannelForgeWebRepositoryRoot` resolves the right root from a module command run outside the web server.
- Whether `LogoReport` reaches the review markdown.
