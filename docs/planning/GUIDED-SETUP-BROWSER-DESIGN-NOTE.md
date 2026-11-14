# Design note: browser Guided Setup controls for source sets (issue #175 step 7, slices 1 to 3)

Contract: guided-setup/proposal/v2 (existing) plus one additive field, `Checks`, named guided-setup/checks/v1.

This is a design note. It adds no product code and no tests. It comes from reading this tree on Nov 14, 2026, plus the text of issue #175. Nothing was run. Anything not confirmed is under "Not verified".

## The problem

A beginner who owns more than one playlist and guide must be able to enroll them, tie each guide to its playlist, and see the build warnings (missing logos, wrong categories, disagreeing guides) before accepting. Today the browser lets the beginner enroll and bind. It does not show the category or guide-comparison checks at all, and the logo check is a single sentence that tells the beginner to run a PowerShell command.

## What the browser does today (verified in code)

| Piece                       | File                                                                                           | Facts                                                                                                                                                                                                                                                                                                                                                                      |
| --------------------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Page (browser mode)         | `gui\src\pages\GuidedSetupPage.tsx`, function `BrowserGuidedSetupPage`                         | Several playlists ("Add another playlist"). Several guides ("Add guide", "Remove"). Each source is a local file or a public HTTPS URL. A friendly name per source. Per guide a "Apply this guide to" checkbox list: each playlist, or "All playlists" when there is more than one playlist. One playlist means the new guide is bound to it. Explicit unbind is supported. |
| Request and response shapes | `gui\src\app\guidedSetupProposal.ts`                                                           | `submitGuidedSetupSourceSetProposal` posts `schemaVersion: 2` to `/api/guided-setup/proposal`. `acceptGuidedSetupSourceSetProposal` posts `schemaVersion: 2` to `/api/guided-setup/accept`. Response `guided-setup/proposal/v2` has counts and a `Warnings` list of `{Code, Message}`. Error codes map to plain messages.                                                  |
| Server proposal             | `src\ChannelForge\Private\Get-ChannelForgeGuidedSetupProposal.ps1`                             | Schema 2 stages the sources, then calls `New-ChannelForgeCandidateProposalFromSourceSet` (the same command the headless path uses), counts bindings, writes a review session, returns the projection. URL policy and transport are the existing bounded machinery.                                                                                                         |
| Warnings the beginner sees  | same file, lines about 195 to 199                                                              | Five warning codes: `ambiguous-guide-match`, `unmatched-playlist-entry`, `guide-only-record`, `guide-unbound-actionable`, `logo-check`. `logo-check` is the raw text of `LogoReport.Warning` and ends with "Pin one with Set-ChannelForgeLogoPin."                                                                                                                         |
| Refresh                     | `src\ChannelForge\Private\Invoke-ChannelForgeWebSourceRefresh.ps1`, `gui\src\app\webStatus.ts` | `POST /api/sources/refresh` refreshes all saved sources and takes no body. The status page shows `canRefreshSources`. There is no per-source refresh call and no per-source state in any browser response.                                                                                                                                                                 |
| Tests                       | `gui\src\test\guided-setup-browser.test.tsx` (6 tests by `it(` count)                          | Multi-source submit, acknowledgement gate, ambiguity blocker, empty-source guard, failure focus, single-guide default and explicit unbind, multi-playlist binding.                                                                                                                                                                                                         |

## What the reports show headless, and where they stop

| Report                               | Command                                                                                      | Reachable from the proposal path today?                                                                                                                                                                                                                                                                   |
| ------------------------------------ | -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Logo (logo-identity)                 | `Get-ChannelForgeLogoReport`                                                                 | Yes. `$candidate.LogoReport` is returned by the source-set candidate command. Only its `Warning` string reaches the browser.                                                                                                                                                                              |
| Category (category-quality/v1)       | `Get-ChannelForgeCategoryReport -CandidateDirectory`, `Get-ChannelForgeCategorySummaryLines` | Yes. `$candidate.CandidateDirectory` is a sealed candidate with `merged.m3u`. The report command also saves `output\category-reports\<hash>.json`. Programme-title mismatch lines need programmes (see below) and are left out here.                                                                      |
| Guide comparison (xguide-compare/v1) | `Get-ChannelForgeXguideReport`, `Get-ChannelForgeXguideSummaryLines`                         | No. It needs the parsed `Programme` objects. In the source-set candidate command they are local variables (`$guideProgrammes`) and are not returned. The Build-Lineup script has them, the browser proposal path does not. Slice 3 changes only what the candidate command returns, never what it hashes. |

## Gap list

1. Category check is not shown before accepting. User loses: finds wrongly sorted channels after accepting.
2. Logo check is shown as one raw sentence with a PowerShell hint. User loses: cannot tell what to do.
3. Guide comparison is not shown. User loses: two guides disagree and nobody says so.
4. No "Details" control anywhere on the proposal summary. Owner rule: detail hidden by default, never removed.
5. Per-source refresh state and a per-source refresh button do not exist in the browser or the server route. Only refresh-all exists.
6. The page does not say that web links with a token or password in them are not supported. Today the server rejects them with a generic "unsupported source" message after analysis. Issue #175 requires the UI to state the limit.
7. Default for several playlists: the page leaves the guide unbound until the beginner ticks a box, and says so. It does not reuse a saved binding. The issue asks to "ask once" and reuse a saved unambiguous binding. [INFERENCE] The saved-binding lookup needs `Get-ChannelForgeSourceSet`, which this note did not trace into the browser path.

Already fine, no work: add playlist, add guide, file or HTTPS choice, guide to playlist assignment, explicit unbind, acknowledgement before accept.

## Contract: guided-setup/checks/v1 (additive, report only)

`Checks` is a new array on the existing `guided-setup/proposal/v2` response. Old clients ignore it. The proposal version string does not change.

```json
{
  "Kind": "logos | categories | guides",
  "Status": "ok | attention | unavailable",
  "Headline": "plain sentence for the beginner",
  "Details": ["lines from the module summary functions, unchanged"]
}
```

Rules:

- `Headline` and `Details` come from the existing module functions (`Get-ChannelForgeLogoReport`, `Get-ChannelForgeCategorySummaryLines`, `Get-ChannelForgeXguideSummaryLines`). One new private function builds the array. No rule is re-implemented in TypeScript.
- Checks never block acceptance and are never hashed. `CanAccept` and `BlockingReasons` are unchanged.
- The `logo-check` entry in `Warnings` stays for old clients. The page hides it when `Checks` has a `logos` entry, so nothing shows twice.
- `Details` lines may name commands (`Set-ChannelForgeLogoPin`). They stay under Details. The headline never does.

## Where each piece lives

| Piece                                                        | Place                                                                                                                  | Size                      |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Build `Checks` (logos, categories)                           | new private function `Get-ChannelForgeGuidedSetupChecks` in a new file next to the proposal                            | about 50 lines PowerShell |
| One call in the schema 2 branch, one field in the projection | `Get-ChannelForgeGuidedSetupProposal.ps1`                                                                              | about 4 lines             |
| Type, parse and show with a Details control                  | `guidedSetupProposal.ts`, `GuidedSetupPage.tsx` (reuse the existing summary block and `setup-proposal-summary` styles) | about 60 lines TypeScript |

## Failure semantics (what the beginner sees)

| Situation                                         | What the beginner sees                                                                                                                                                    | State left behind                |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| A source cannot be read or fetched                | Existing plain message from `guidedSetupProposalErrorMessages` (for example "A public HTTPS source could not be retrieved ..."). Selections stay. No proposal. No checks. | Nothing accepted, no session.    |
| The category report fails                         | The proposal still shows. The categories row says "Category check could not run. You can still accept." Details name no path.                                             | Candidate unchanged, no failure. |
| The log of a check would reveal a path, URL or id | Not allowed. Check lines come from channel names and group names only. Test for it in slice 1.                                                                            | None.                            |
| A web link with a token                           | Slice 3 shows a short note before analysis: "Links with a password or token in them are not supported yet. Use a file instead."                                           | None.                            |

## What the beginner sees before accepting

Under the counts, a "Checks before you accept" list. One row per check, each with a status badge, a one-sentence headline and a "Details" button that opens the module lines. The next step is on the row: "Looks fine." or "You can accept, or fix this first (see Details)." The existing acknowledgement checkbox and accept button stay as they are.

## Slice list (at most 3)

1. Slice 1, logos and categories in the proposal (the contract above). Real step forward: the beginner sees category and logo health in plain words before accepting. Under about 150 lines.
2. Slice 2, small page notes: say that tokenized links are unsupported, and for several playlists show "Choose a playlist for this guide" with the existing status text (no new rule). Per-source refresh is NOT in this slice, see owner question 2. Under about 60 lines.
3. Slice 3, guide comparison in the proposal. Needs the candidate command to return the parsed programmes (not hashed, not written). Adds a `guides` check. Under about 120 lines. Do it only after the owner answers question 3.

## Owner questions

1. Is slice 1 (logos and categories only) the right first step? Recommendation: yes. Both reports are reachable now and the change is read only.
2. Per-source refresh: build a new route, or leave refresh-all for Alpha.1? Recommendation: leave refresh-all. A new route is a second refresh path, and issue #175 says no second refresh engine. Show the last refresh result of refresh-all instead if the owner wants status.
3. Guide comparison needs the candidate command to return programmes. That touches a Public return shape, not a hashed input. Accept it? Recommendation: yes, but only as an extra property, with a test that the candidate hash is unchanged.
4. Should the category report file be saved in `output\category-reports\` for every browser proposal, or should the browser path not write it? Recommendation: accept the write for slice 1 (same as headless) and say so in the docs.

## Frozen items touched

None. Guide-id v1.0, raw digest projections, M3U entry byte format, BuildIdentityInput, blocker-2-contract/v7, accepted-state code, transport and trust code are not changed by any slice. If slice 3 turns out to need a hashed value, stop and report.

## Not verified

- Nothing was run: no GUI build, no GUI tests, no Pester.
- Whether `Get-ChannelForgeCategoryReport` is safe to call from the web request path (it writes a file and takes the module's root path).
- Whether the saved-binding lookup is usable in the browser path (gap 7).
- The exact response of `/api/sources/refresh` (only its route was read).
- Test counts for `guided-setup-browser.test.tsx` are an `it(` text count, not a run.
- Screenshots: none taken. Screenshots and user docs are due only when a slice ships UI.
