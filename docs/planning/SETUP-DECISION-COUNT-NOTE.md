# Setup decision count (slice 194-C)

Status: note only. No code, tests, or output bytes change.

Source: `gui/src/pages/GuidedSetupPage.tsx`, function `BrowserGuidedSetupPage` (the browser setup the user sees). Counted by reading the code. Nothing was run.

## Why this note

Issue #194 asks for "radically simple" setup. Owner decision D-194 re-scoped it to a readable, keyboard-friendly review UI. A fair goal needs a number first: how many things does setup ask, and which of them could the app work out by itself?

## The count

Smallest path (one playlist file, no guide): 4 user actions, 2 of them real decisions.

| #   | Action                                        | Kind     | Can it be inferred?                   |
| --- | --------------------------------------------- | -------- | ------------------------------------- |
| 1   | Pick the playlist (file, or public HTTPS URL) | Decision | No. See reason A.                     |
| 2   | Click "Analyze"                               | Trigger  | Not a question. It starts the review. |
| 3   | Tick "I reviewed these results..."            | Decision | No. See reason B.                     |
| 4   | Click "Accept reviewed proposal"              | Trigger  | Not a question. It saves the state.   |

The workspace card asks nothing. It only says the workspace is server-owned.

## Questions that appear only when the user adds more

| Question                           | When it shows            | Default today                             | Can it be inferred?                                |
| ---------------------------------- | ------------------------ | ----------------------------------------- | -------------------------------------------------- |
| File or URL, per source            | Every source row         | File                                      | No. Reason A.                                      |
| Source label                       | Every source row         | "Playlist 1", "Guide 1"                   | Yes. It is already defaulted. Editing is optional. |
| Add another playlist               | User choice              | None                                      | No. Reason A.                                      |
| Add a guide                        | User choice              | No guide (playlist-only)                  | No. Reason C.                                      |
| Which playlists a guide applies to | Each guide               | The only playlist, when there is just one | Only when there is one playlist. Reason D.         |
| "All playlists" box                | Each guide, 2+ playlists | Off                                       | No. Reason D.                                      |

## Totals

- Smallest path: 2 decisions (playlist source, acknowledgement) plus 2 clicks.
- One playlist and one guide: 4 decisions (playlist source, guide source, guide binding, acknowledgement) plus 2 clicks. The binding is pre-filled, so the user only confirms it.
- N playlists and M guides, worst case: N + M source choices, M binding choices, 1 acknowledgement.
- Optional edits (labels) are not counted as questions.

## Why each decision cannot be inferred

- **A. Which source files or links.** ChannelForge never scans the disk or the network on its own. The browser has no path authority (ADR-0016). Only the user knows which playlist is theirs.
- **B. Acknowledgement.** Acceptance writes the accepted local state. The app must not accept on the user's behalf. The review shows warnings (for example logo and guide checks) that a person has to see first.
- **C. Adding a guide.** A guide is optional. Whether the user has one, or wants playlist-only mode, is not visible in the playlist. Guessing could attach the wrong guide.
- **D. Guide to playlist binding.** Guide-id contract v1.0 is frozen and binding is explicit. With one playlist there is one sensible answer, so it is pre-filled. With two or more, matching by name or id could attach a guide to the wrong playlist. That risk is why the choice stays with the user.

## What could shrink (ideas, not decided)

1. Show the guide step as "Add a guide later" by default. It is already optional, so this only changes layout.
2. Pre-fill the guide binding to "All playlists" when there are several playlists. Risk: it breaks the explicit-binding rule. Not recommended without an owner decision.
3. Merge the "Analyze" click into the last source choice. Risk: users lose the moment to add a second source. Not recommended.

## What this note does not cover

- The older local-folder picker path (the non-browser flow lower in the same file). It is a different flow.
- Timing or observed first-use sessions. Those are owner-run (see the map, #194).
- Any change to the page, copy, or tests.

## Owner decisions

1. Accept "2 decisions plus 2 clicks" as the target for the smallest path? Recommended: yes. It cannot go lower without removing the acknowledgement.
2. Keep explicit guide binding as is? Recommended: yes. It protects frozen guide-id contract v1.0.
