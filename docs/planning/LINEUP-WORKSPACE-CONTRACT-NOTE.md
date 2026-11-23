# Design note: lineup workspace contract, view and explain only (issue #56, slice 56-A)

Contract names proposed here: lineup-workspace/query/v1, lineup-workspace/channel/v1, lineup-workspace/explain/v1.

This is a contract note. It adds no product code and no tests. It comes from reading this tree on Nov 23, 2026, plus the text of issue #56. Nothing was run. Anything not confirmed is under "Not verified".

## The problem

A beginner who has accepted a lineup cannot see it in the browser. No route lists channels. When a channel has no logo, no guide, or an unclear match, the beginner has to read files or run PowerShell. Issue #56 asks for a full visual editor. That editor needs #25, #26 and an ADR for pending changes and rollback, none of which exist. This note defines only the small part that can be built now: look at the lineup and understand why each channel is the way it is.

## Scope decision

Owner decision (Nov 23): ChannelForge is a complete set-top-box type system (guide, browse, start playback) on a client/server design, and editing is planned as well as viewing. The set-top-box part is optional: ChannelForge must also work on its own as a builder of guides and playlists for Plex and other IPTV viewers. The first slices are view and explain only. The workspace is a review page for the person who builds the lineup. A view-only page passes the issue's guardrail ("does it reduce effort, without a second system of record"). An editor needs a design note and an ADR for pending changes and rollback before any code.

## What the browser may ask for

The browser asks the engine over the existing loopback server (ADR-0016). It never reads files, never sends a path, and never holds accepted state.

| Request                                 | Meaning                                                              | Slice |
| --------------------------------------- | -------------------------------------------------------------------- | ----- |
| `GET /api/lineup/channels`              | A page of channels from the accepted generation.                     | 56-B  |
| `GET /api/lineup/channels/<id>/explain` | The reasons for one channel, from evidence the engine already holds. | 56-D  |

Both are GET only. The server already answers any other method on read-only routes with 405 and `Allow: GET, HEAD`; these routes use the same rule.

### Query: lineup-workspace/query/v1

Same style as the One Guide routes (`Get-ChannelForgeWebOneGuidePaging`): decimal integers only, unknown names rejected with `invalid-query`.

- `limit`: 1 to 100, default matches One Guide. Bounded so a large lineup cannot become one huge response.
- `offset`: pages after the first must carry the `generation` cursor. The cursor is the accepted generation token, so a page never mixes two lineups. If the accepted lineup changed, the answer is a plain "lineup changed, reload" error, not a mixed page.
- `group`: one group name from the lineup, matched exactly.
- `attention`: `all` (default) or `needs-review`. Needs-review means: no guide, no logo, ambiguous, or unmatched.
- `search`: text, bounded length, matched against name only. Case-insensitive.

Filtering and paging happen on the server. The browser never receives the whole lineup to filter itself. This keeps large lineups fast and keeps the answer size bounded.

### Answer: lineup-workspace/channel/v1

Each row carries only these fields:

| Field        | Meaning                                                                              |
| ------------ | ------------------------------------------------------------------------------------ |
| `id`         | Opaque stable channel id from the accepted state. Not a file path. Not a stream URL. |
| `number`     | Channel number. Presentation only.                                                   |
| `name`       | Channel name.                                                                        |
| `group`      | Group name.                                                                          |
| `logoStatus` | One of `present`, `missing`, `pinned`.                                               |
| `guideState` | One of `bound`, `none`. `none` is the existing `guide: null` marker, shown as is.    |
| `attention`  | A short list of plain reason codes, empty when nothing needs a look.                 |

The page envelope adds `generation` (the cursor), `total`, `offset`, `limit`, and `count`.

## What is never in an answer

- Stream URLs, playlist URLs, guide URLs, tokens, passwords, query strings, cookies, local file paths, or repository paths.
- Where a source must be named, only the host is shown (for example `provider.example`). Nothing after the host.
- Real logo image data. The answer says whether a logo exists, not what it is.
- Anything that lets the browser rebuild a stream address.

The redaction runs in the engine before the JSON is written, so a UI bug cannot leak what the server did not send. The slice that builds the route must carry a test that puts a URL with a token into the fixture and proves the response has no token.

## Explain: lineup-workspace/explain/v1

Explain reuses reasons the engine already produces. It does not invent a new scoring system and it does not re-run matching.

| Reason code (existing)     | Plain meaning for the beginner                                    |
| -------------------------- | ----------------------------------------------------------------- |
| `ambiguous-guide-match`    | More than one guide entry fits this channel. Nothing was guessed. |
| `unmatched-playlist-entry` | No guide entry fits this channel.                                 |
| `guide-only-record`        | The guide lists this channel but no playlist entry matches it.    |
| `guide-unbound-actionable` | A guide is present but not tied to this playlist.                 |
| `logo-check`               | The logo check has a finding. Shown without the PowerShell hint.  |

Each explanation gives: the code, one plain sentence, and what the user can do today (an existing documented engine command, named, not run by the browser). Detail such as candidate names and evidence is hidden by default and opens under "Details". Simple view shows the code and sentence only. Nothing is removed from the engine; only the default view is short.

Where the accepted state does not keep a reason, the answer says "no reason recorded". It never invents one.

## What is NOT editable, and why

| Action                             | Editable in Milestone 3? | Why not                                                                                                                   |
| ---------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Rename, renumber, reorder, regroup | No                       | Changes the lineup. Needs #26 and a pending-change design. Numbers must not feed guide ids.                               |
| Merge, split, add, remove channel  | No                       | Same. Also can drop a channel. Dropping a channel is never allowed.                                                       |
| Pin or quarantine                  | No (view `pinned` only)  | Writes state. The engine command `Set-ChannelForgeLogoPin` exists; a browser route for it needs its own review.           |
| Change a guide binding             | No                       | Guide-id contract v1.0 is frozen. A binding change belongs to Guided Setup, which already has review and acknowledgement. |
| Bulk edit                          | No                       | Needs an exact-scope preview and all-or-nothing apply. Not designed yet.                                                  |
| Accept, publish, or approve        | No                       | Only Guided Setup accept does this. Looking at a lineup never counts as approval.                                         |
| Undo after apply                   | No                       | See the undo section.                                                                                                     |

The page never shows a button that looks like an edit. Where the user needs a fix, the page links to the existing Guided Setup page or names the existing engine command in plain words.

## Pending change, undo and preference contracts (stated, not designed)

- **Pending change set:** not defined here. When it is defined it must: show exact before and after for every item, apply all or nothing, never count as publication, and call only documented engine commands (ADR-0016). It needs its own ADR because it touches accepted-state.
- **Undo:** the generation store is immutable and a pointer selects the current one. The "undo through snapshots" idea in the issue overlaps that model. It must be designed as "point back at an older generation" or "build a new generation that restores values", not as editing a generation. That choice is for a later design note. This note makes no promise.
- **Preferences:** filters, density and column layout are local to the browser. They go in browser local storage under a name for this page. They never go into engine state, never change the lineup, and never appear in output files. The appearance setting from issue #149 follows its own contract.

## Frozen contracts and bytes

- Guide-id contract v1.0 is not changed. The `guide: null` marker stays. A channel with no guide is shown, never hidden, never dropped.
- A channel number is presentation only. It is never used to build or rewrite a guide id.
- The routes read the accepted generation and write nothing. M3U, XMLTV and accepted state bytes do not change.
- Opening the page or calling a route must not create a generation, a report, a log entry that changes output, or a candidate.

## Reuse (no new framework)

- Paging, snapshot cursor and `invalid-query` handling: copy the pattern in `Get-ChannelForgeWebOneGuidePaging` and `Get-ChannelForgeWebOneGuideResponse`; share the helper if it can be shared without a rewrite.
- Reading the accepted generation: the same generation snapshot reader the One Guide route uses. No second reader.
- Route table: `Get-ChannelForgeWebResponse.ps1`.
- Reason codes and wording: the Guided Setup proposal warnings and `gui/src/app/setupSelection.ts`.
- Page parts: `StatusBadge`, `StatusBanner`, `TermCoach`, design tokens in `gui/src/styles/tokens.css`.

## Later slices this note enables

| Slice | What                        | Depends on |
| ----- | --------------------------- | ---------- |
| 56-B  | Read-only lineup list route | this note  |
| 56-C  | Single-pane lineup page     | 56-B       |
| 56-D  | "Why this match" panel      | 56-B       |

Dual pane with candidates, edit commands, bulk edit, pending change sets and undo are outside Milestone 3. They wait for the owner and for #25 and #26.

## Owner decisions

1. View and explain only for Milestone 3. Recommendation: yes. An editor writes state and needs #26 plus an ADR.
2. Show `search` on name only, or also on group. Recommendation: name only for now; the group filter covers groups.
3. Whether `attention=needs-review` should include "no logo". Recommendation: yes, it is the most common beginner finding; a pinned logo clears it.

## Not verified

- No code was run and no test was run.
- Whether the accepted state keeps a per-channel reason for ambiguity or unmatched status. [INFERENCE] The proposal keeps `Warnings` as a list, not per channel. If the accepted state lacks per-channel reasons, 56-D can show only what the review session holds, and the answer will say "no reason recorded".
- The exact accepted-state field names for logo status and guide state. 56-B must read them from the accepted generation and may adjust the field list; the redaction rule above does not change.
- The exact location of guide-id contract v1.0. It was not found under `docs/adr`; it is described in planning notes and `docs/architecture/AGGREGATION_POLICIES_AND_CHANNEL_NUMBERS.md`. This note does not change it.
