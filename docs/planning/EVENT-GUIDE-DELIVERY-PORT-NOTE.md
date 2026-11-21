# Port note: event guide delivery (issues #32, #30, #38)

Status: design only, based on the real old script. Slice 1 from the earlier lane (writer function) is not carried into this tree. Nothing here was run against old code.

## Correction

Earlier notes said no old code exists. That was wrong for the owner PC. Copies are in the owner's OneDrive (Repo-beta and the 2026-08-15 dashboard checkpoint). Not in GitHub. Read only; nothing was copied into this repo.

## The old script: New-ChannelForgeEventGuide.ps1 (251 lines)

Plain words: it reads a playlist and an event discovery report. For each auto-matched channel it writes one programme (start, stop, title "away at home", category "Sports - league") into a separate `event-guide.xml`, and a JSON decision report. Review items are listed, not published.

Details that matter:

- Stop time: provider stop if valid, else start plus a configured duration (default 180 min), optional padding. Every row records a timing mode and reason codes.
- Optional rows: "unverified fallback" window and "No scheduled event" idle state, both off by default.
- Optional templates with a fixed token list, a length limit, and a ban on URLs and secrets.
- Optional programme icon from a rendered artwork report, written as a relative path.
- Text scrubber replaces URLs and secret-looking text. Report says no stream URLs and no network.
- The refresh script (`Run-ChannelForgeRefresh.ps1`, `Invoke-EventGuideRefresh`) chains discovery, stream consolidation, this script, then an optional publish. Publish needs `-ConfirmEventGuidePublish PUBLISH` and merges the event guide into the candidate `guide.xml`.
- The dashboard-checkpoint copy differs only in wording and indentation (programme vs program, two lines). Same logic.

## What main already covers

Event detection, time agreement, doubleheaders, programme blocks, `Get-ChannelForgeEventGuidePlan`, overrides, saved answers. The build gives event channels their own guide entries. Main has no separate event file, no report of timing mode, no refresh switch.

## Port decisions

| Old part                                        | Decision                                    | Reason                                                                     |
| ----------------------------------------------- | ------------------------------------------- | -------------------------------------------------------------------------- |
| Separate `event-guide.xml`                      | Port (later slice)                          | No existing output changes                                                 |
| Timing rules: provider stop, else duration, pad | Port                                        | Small, clear, matches main's block times                                   |
| Decision report with reason codes               | Port                                        | Owner sees why each channel got its time                                   |
| Text scrubber                                   | Reuse `ConvertTo-ChannelForgeGuideSafeText` | Duplicate otherwise                                                        |
| Merge into candidate `guide.xml` on PUBLISH     | Reject                                      | Changes merged guide bytes and hashes (frozen). Also a manual confirm step |
| Idle "No scheduled event" row                   | Reject                                      | Main fills gaps already; second convention                                 |
| Unverified fallback window                      | Reject                                      | Invents a schedule. Report-only row is enough                              |
| Templates                                       | Later                                       | Needs its own schema; no user need yet                                     |
| Programme icon from rendered artwork            | Reject                                      | Rendering plus local files means hosting (see visual identity note)        |
| Discovery and schedule inputs                   | Intent only                                 | Source must be a free provider; no scraping adapter in the public product  |

## Frozen contracts

Guide-id v1.0, M3U entry bytes and others are untouched by the kept parts. Event ids stay plan ids, not guide ids. Never drop a channel; `guide: null` stays. Event file failure warns and never fails the build.

## Slices (each under about 300 lines)

1. Writer function plus decision report (pure, no files).
2. Write `event-guide.xml` beside the output, outside `accepted\`. Prove with before and after SHA-256 of every other output on a fixture build.
3. Refresh switch for only that file.

Owner decision: keep the file outside `accepted\`. Recommendation: yes, so a failed event write never rolls back the lineup.
