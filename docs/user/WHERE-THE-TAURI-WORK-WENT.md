# Where the Tauri work went

This page answers: **the old desktop app (Tauri) was the first UI. Where did that work go?**

Short answer: the screens moved to the browser UI that the ChannelForge engine serves. The Tauri wrapper is still in the repository as optional packaging. [ADR 0016](../adr/0016-web-first-local-ui.md) records the decision.

## What the browser UI reused

The React/TypeScript code in `gui/src` is shared. The browser UI and the optional Tauri wrapper load the same pages.

| Tauri-era work                 | Where it lives now                                                                                                                      |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Layout, side navigation, shell | `gui/src/components` (`SideNav`, `TopBar`, `PageHeader`) and `gui/src/app/AppShell.tsx`                                                 |
| Colors, fonts, spacing         | `gui/src/styles/tokens.css`                                                                                                             |
| Status badges and banners      | `gui/src/components` (`StatusBadge`, `StatusBanner`, `StatusDashboard`)                                                                 |
| Guided Setup steps             | `gui/src/pages/GuidedSetupPage.tsx`, which sends files to the engine routes `/api/guided-setup/proposal` and `/api/guided-setup/accept` |
| Lineup review                  | `gui/src/pages/LineupReviewPage.tsx`                                                                                                    |
| Saved lineup                   | `gui/src/pages/SavedLineupPage.tsx`                                                                                                     |
| Beginner wording and term help | `gui/src/components/TermCoach.tsx`                                                                                                      |

## What did not move

These parts are native-only. They stay in `gui/src-tauri`, and the browser UI does not copy them.

- The native file picker. A browser cannot hand over a file path, so it sends the bytes you select. See [ADR 0016](../adr/0016-web-first-local-ui.md).
- Direct disk reads and the native checks of playlist and guide files.
- Running local PowerShell from the app.

The wrapper calls four native commands (`choose_setup_item`, `check_playlist_guide_match`, `prepare_saved_lineup_plan`, `accept_saved_lineup`) through `gui/src/app/setupPicker.ts`. The browser path does not call them.

## Rules that stay in force

- The engine's HTTP/API boundary is the only place that changes state. A wrapper must not hold a second copy of product logic.
- Accepting a lineup always goes through the engine's accepted-state step.
- Logins and secrets never appear in either UI. Sources show a host name only.

## What to expect

- Day-to-day use is the browser UI. See [Install on Windows](INSTALL-WINDOWS.md).
- The Tauri wrapper is optional and still a prototype. You do not need it.
- Docker and a Windows service are not built. See [Current Limitations](CURRENT_LIMITATIONS.md).
