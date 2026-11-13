# Phase 1 design note: guide logos must be public https links (issue #191)

Design only. No product code or test was changed. Nothing was run.

## Why

Plex on Apple TV refuses guide icons from private (LAN) addresses. Plex Web shows them. On the real 479-channel lineup, 156 channels had no logo and many pointed at a private address. Rule: every published channel carries a public https logo when one exists; placeholder channels get a group-level default; a private-address logo is reported, never published as good.

## What exists today

| File                                            | What it does with the logo                                                                                                                                               |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Classes\Channel.ps1                             | `[string]$Logo`, default `''`. No validation.                                                                                                                            |
| Public\New-ChannelForgeChannel.ps1              | Copies `-Logo` (default `''`) into the channel. No validation.                                                                                                           |
| Private\Read-ChannelForgeM3UReader.ps1          | Reads `tvg-logo="..."` with a regex. Keeps any text as-is (empty, http, private, https). Also stores it as `RawLogo`.                                                    |
| Private\ConvertTo-ChannelForgeM3UEntryBytes.ps1 | Writes `tvg-logo` after safe-text cleaning. An empty logo means the attribute is left out. Used by Export-ChannelForgeM3UPlaylist and New-ChannelForgeCandidateManifest. |
| Private\Get-ChannelForgeRawM3UProjection.ps1    | Copies `RawLogo` (or `Logo`) into the frozen ten-field digest projection. No check.                                                                                      |
| Private\Get-ChannelForgeRawXmltvProjection.ps1  | Carries `IconNodes` (channel and programme icons) into the raw digest. No check. Reader (Read-ChannelForgeXmltvDocument.ps1) sets `IconNodes = @()` in one path.         |
| Private\New-ChannelForgeCandidateManifest.ps1   | Logo is part of the presentation fingerprint and of the manifest entry. No check.                                                                                        |
| Private\Add-ChannelForgePlaceholderGuide.ps1    | Builds name-only guide channels (`<channel>` with display-name only). No `<icon>`.                                                                                       |

Today an empty, http, private-address and https logo are all treated the same: passed through unchanged. Nothing is reported.

## Smallest change that meets the rule

Put ONE check in the publish step, not in the readers. Readers and raw projections must keep the exact source text (digests are frozen).

- New helper `Get-ChannelForgeLogoStatus` (Private, one job): input one string, output `Public`, `Empty`, `NotHttps` or `PrivateAddress`.
  - Reuse `Test-ChannelForgeSourceUrl` for "absolute https URL" and `Test-ChannelForgeSafeHostAddress` (which calls `Test-ChannelForgeDisallowedIpAddress`) for literal private/loopback/link-local IPs.
  - Limit: a DNS name that resolves to a private address is not caught (no network lookup). Also treat `localhost` and single-label or `.local`/`.lan` host names as private. This is a string check only.
- Call it once where the output channel is finalised, just before `ConvertTo-ChannelForgeM3UEntryBytes` runs: a small function that returns the logo to publish and a status. Two callers today: Export-ChannelForgeM3UPlaylist and New-ChannelForgeCandidateManifest.
- Rules in that step:
  1. `Public` -> publish as is.
  2. `Empty` -> use the group default logo if the group has one; else leave empty and report `NoLogo`.
  3. `NotHttps` / `PrivateAddress` -> never publish as good. Use the group default if present; else leave empty. Always report the channel and the status.
- Group default logo: one optional setting, group name -> https URL, checked with the same helper. Placeholder channels (from Add-ChannelForgePlaceholderGuide) fall under rule 2 because they have no source logo.
- Report: counts and channel names per status, in the build result and warnings. Never drop a channel.

Files that would change: new `Private\Get-ChannelForgeLogoStatus.ps1`; `Public\Export-ChannelForgeM3UPlaylist.ps1`; `Private\New-ChannelForgeCandidateManifest.ps1` (or the shared place both call); the build result/report; the config reader for the group default. Plus tests and docs.

## What must NOT change

- Guide-id contract v1.0 (frozen). A colliding or missing guide id never drops a channel. The `guide: null` marker stays.
- Never drop a channel because of its logo.
- Raw M3U digest projection (ten fields, `raw-m3u-occurrence/v2`) and raw XMLTV projection (`IconNodes`, `raw-xmltv-occurrence/v2`): they keep the source logo text exactly.
- M3U byte format from ConvertTo-ChannelForgeM3UEntryBytes: attribute order (tvg-id, tvg-name, tvg-logo, tvg-chno, group-title), no tvg-logo attribute when empty, UTF-8 without BOM, `\n` line ends. Existing tests pin this. A replaced logo changes only the logo value.
- Reader behaviour (Read-ChannelForgeM3UReader): keep the raw value.
- Presentation fingerprint: a policy change that rewrites logos will change it. Decide this on purpose (see questions).

## User-visible behaviours to test

1. A channel with a public https logo is published with that logo, unchanged.
2. A channel with a private-address logo (10.x, 192.168.x, 172.16-31.x, 127.x, localhost) is not published with it, and is listed in the report.
3. An http logo is treated as not public and reported.
4. A channel with no logo and a group default gets the default; with no default it ships without `tvg-logo` and is reported.
5. A placeholder channel gets its group default logo.
6. No channel is dropped; the channel count in equals the count out.
7. The report shows how many channels were Public, replaced, or missing.
8. A byte-for-byte M3U for an all-public lineup is identical to today.

## Size and order

Estimate: about 220 changed lines in total (code about 110, tests about 110). Under the 300 budget.

1. PR 1: `Get-ChannelForgeLogoStatus` helper plus its tests (about 70 lines). No behaviour change.
2. PR 2: apply in the M3U publish step with report only (no rewriting), so owners see counts first (about 70 lines).
3. PR 3: group default logo setting and replacement, including placeholder channels (about 80 lines).

## Open questions for the owner

1. Should a private or http logo be replaced by the group default, or left empty? Recommend: replace with the group default when one exists, else leave empty and report. Never publish a private link.
2. Should a build fail or only warn when channels have no public logo? Recommend: warn only; never block a build or drop a channel.
3. Where does the group default live? Recommend: one optional group-to-URL map in the existing config.
4. Should the XMLTV `<icon>` (guide icon) follow the same rule? Plex reads guide icons from there too. Recommend: yes, in a later PR after the M3U step proves out; keep raw projection untouched.
5. Is a DNS name that resolves to a private address in scope? Recommend: no for now (needs network); catch literal IPs and `localhost`/`.local`/`.lan` only.
6. Can the presentation fingerprint change when a logo is replaced? Recommend: fingerprint the published logo, and note it in the changelog.
7. Dispatcharr refresh can reset logos on auto-created channels. Recommend: report only for now; ChannelForge does not write to Dispatcharr in this phase.

## Decisions (provisional, Nov 13, 2026)

The recommendations above are adopted as defaults so work can start. The owner can override any of them before the matching pull request merges. Not verified: where Add-ChannelForgePlaceholderGuide is called from (no caller found under src), so the placeholder rule needs a real check in pull request 3.
