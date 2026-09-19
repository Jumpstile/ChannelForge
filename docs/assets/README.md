# Documentation screenshots

These images were captured afresh on September 19, 2026, from the built browser
UI and real local server at `main` commit
`b44b6bfdcc138c00676cdf94ae843b1830343df5`, after PR #167.
Every documentation image is a new capture. Existing test baselines remain
unchanged.

| Image | Screen |
| --- | --- |
| [Guided Setup](browser-guided-setup.png) | Initial browser screen before file selection |
| [Proposal result](browser-guided-setup-proposal.png) | Real candidate proposal from two synthetic channels and matching guide entries |

## Capture environment

- Windows, Node 22.23.2, npm 10, and locked GUI dependencies.
- Production UI built with `npm run build` in `gui/` and served by
  [Start-ChannelForgeWebServer.ps1](../../scripts/Start-ChannelForgeWebServer.ps1)
  on loopback port 18765.
- Playwright Chromium 153.0.8010.12, 1440-by-900 viewport, device scale factor 1,
  full-page PNG captures, animations disabled.
- Captured at `2026-09-19T17:11:58Z`; initial image 1440 by 1098 pixels,
  proposal image 1440 by 1406 pixels.
- No mocked API responses, native bridge, private playlists, or real provider data.

## Reproduce the screens

1. Follow the [browser startup instructions](../user/Build-Your-First-Lineup.md#browser-guided-setup-proposal)
   using the intended source revision and supported runtime.
2. Open the local server in Chromium and select **Open Guided Setup**. Capture
   the initial screen before choosing files.
3. For the result screen, choose synthetic files named `sample-playlist.m3u`
   and `sample-guide.xml`. Use two playlist entries with guide IDs `sample.one`
   and `sample.two`, display names `Sample One` and `Sample Two`, and stream
   placeholders `https://example.invalid/one` and `https://example.invalid/two`.
   Give the XMLTV guide matching channel IDs and display names, plus a sample
   programme for `sample.one` from `20260919120000 +0000` to
   `20260919130000 +0000` with title `Sample programme`.
4. Select **Analyze proposal** and wait for **Candidate proposal ready. Nothing
   was published.** Capture the full page, including the result summary.

The capture request returned HTTP 200, two channels, two exact guide matches,
zero ambiguous/unmatched/guide-only records, and no warnings. Its safety result
was `CandidateOnly`, `CanPublish=false`, with accepted-state, provider,
downstream, and guide-publication mutation all `none`. No browser page errors
were reported.

The demo workspace label is sample UI content; browser setup does not request
a workspace folder. These images show browser behavior, not native Tauri
validation, an accepted lineup, or release certification.

When the UI changes, take new screenshots from the intended revision and update
this capture record. Inspect images and captions together, then run the
repository Markdown hygiene and link checks and `git diff --check`. Keep these
stable image paths independent of test snapshot filenames. Documentation work
must not overwrite or weaken visual baselines or test assertions.
