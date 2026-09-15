# Current Limitations

This page answers: **what can I actually rely on ChannelForge for today, and what should I not expect yet?**

ChannelForge is **Early Alpha**. Treat everything below as the honest, current state — not a roadmap promise. For what's planned and when, see [ROADMAP.md](../../ROADMAP.md).

## Implemented today

- Parsing real M3U provider playlists.
- Reading provider and EPG source configuration, including local and bounded remote XMLTV acquisition plus remote provider-M3U URL trust-boundary validation.
- Deterministic alias resolution and channel numbering — the same input always produces the same output.
- Merging multiple local or configured remote playlists into one deduplicated `output/merged.m3u`.
- Importing configured local XMLTV `.xml`, `.gz`, and single-entry `.zip` files, plus bounded remote XMLTV plain XML and supported HTTP codings.
- Deterministically merging and exporting validated local or remote XMLTV data to `output/merged.xml`; a failed run leaves that public path absent and quarantines any prior artifact for rollback/inspection only.
- A safe, local-only provider configuration workflow that never requires editing a tracked file (see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md)).
- A build report (`output/reports/build-summary.json`, `lineup-plan.md`) for every run, with a checksum, so you can verify what happened without trusting it blindly.
- A ChannelForge Guided Setup / Beginner Workflow (`scripts/Build-My-Lineup.ps1`) that stages a candidate, reports exact/ambiguous guide identity, supports no-guide builds, requires explicit acceptance, and promotes through the immutable accepted-generation boundary.
- A Stage A/B/C/D read-only guide-intelligence contract for provider display text, M3U metadata, XMLTV, documented AED-derived evidence, schedule evidence, accepted knowledge, native event-pattern candidates, and beginner review reports. Stage D wires the report-only event-pattern preview into `scripts/Build-My-Lineup.ps1`; it writes deterministic redacted JSON/Markdown/text reports and never publishes a guide or mutates provider, downstream, or accepted state.
- Existing GUI work is preserved as a reusable React/TypeScript layout, design-token, Guided Setup, validation/review, and saved-lineup reference. Its Tauri wrapper is optional packaging work, not the primary product UI.
- The optional Tauri saved-lineup flow prepares a read-only candidate plan, permits saving only for a native **Checked** match, requires accessible explicit acknowledgement, and navigates to a redacted accepted-state view after native success.

The primary UI architecture is a browser-based local web UI served by the
ChannelForge engine. The existing React/Vite application can be built and
served locally, but this slice does not make it a complete API-backed product
UI.

Build and serve it from the repository root:

```powershell
Push-Location .\gui
npm ci
npm run build
Pop-Location
pwsh -File .\scripts\Start-ChannelForgeWebServer.ps1
```

Open `http://127.0.0.1:8765/`. If `gui/dist/index.html` exists, the server
serves that built UI and its allowlisted static assets. Otherwise it serves
the safe placeholder shell. Static requests are read-only, loopback-only,
confined to `gui/dist`, and do not provide directory listings or SPA fallback.
`/health` and `/api/status` remain stable read-only JSON endpoints.

The beginner path is explicit: open the local URL, see either the built UI or
the safe placeholder, and treat setup/review as future until API-backed Guided
Setup is implemented. Accepted-generation metadata remains read only and is
used only to derive lineup status.

Docker container and Windows server/service installation remain intended primary
deployment modes but are not implemented yet. The existing Tauri prototype
still depends on local native picker and PowerShell bridge behavior. Those
assumptions must be re-evaluated before web UI implementation; browser
state-changing behavior must use engine HTTP/API commands and the immutable
acceptance boundary.

The GUI saved-lineup flow does not provide export, scheduling, target publishing, release packaging, or tester distribution. It also cannot save needs-attention, review-needed, blocked, checking, not-checked, stale, or unavailable states.

### GUI status

The following describes preserved prototype/reference work, not a primary deployment surface:

| Area                                      | Status                                                                 |
| ----------------------------------------- | ---------------------------------------------------------------------- |
| Browser web UI served by engine           | Foundation shell and read-only local status available; full UI pending |
| Docker deployment                         | Architecture recorded; implementation pending                          |
| Windows server/service install            | Architecture recorded; implementation pending                          |
| Optional Tauri Workbench shell/navigation | Works now (prototype)                                                  |
| Guided Setup layout                       | Preview only (prototype)                                               |
| Native file-picker bridge                 | Works now (prototype)                                                  |
| Display-safe selection state              | Works now (prototype)                                                  |
| Pre-parse selection checks                | Works now (prototype)                                                  |
| Playlist structural validation            | Works now — structural only (prototype)                                |
| Guide structural validation               | Works now — structural only (prototype)                                |
| Playlist/guide exact matching             | Implemented — local checks passed (prototype)                          |
| Lineup review                             | Implemented — local checks passed (prototype)                          |
| Saved lineup                              | Implemented — native acceptance + local checks                         |
| Automatic updates                         | Planned / not built yet                                                |

## Not implemented yet

- **Export, scheduling, release, and tester distribution remain unavailable.** The GUI saved-lineup view reflects native accepted state only; it does not create downstream packages, schedule refreshes, publish to Plex or another target, create releases, or distribute artifacts.
- **Native GUI runtime prerequisites remain local.** The GUI acceptance boundary requires the repository PowerShell workflow and `pwsh`; unavailable or stale native results fail closed without changing accepted state.
- **Remote acquisition is deliberately narrow.** Provider M3U and XMLTV remote sources require HTTPS on port 443 and bounded streaming; redirects, proxies, credentials, authentication, retries, remote ZIP, stale/offline success, and live-network CI are not supported. Report-only scheduled planning is available without fetching sources.
- **Scheduled refresh is opt-in and Windows-only.** The planner remains report-only, while the manual foreground wrapper remains available and defaults to manual mode. Explicit installation creates one owned daily Task Scheduler task per local root; scheduler-owned mode invokes the bounded source-refresh executor once, with deterministic jitter handled by one bounded foreground wait. There is no always-on worker, daemon, service, cron/systemd registration, autonomous retry loop, or cross-platform scheduler backend.
- **No fuzzy or target-specific guide assignment.** The build reports exact, unambiguous M3U `tvg-id` to XMLTV channel-id bindings, plus unbound, ambiguous, and XMLTV-only identities. It does not guess, perform fuzzy matching, or rewrite the separate canonical M3U/XMLTV outputs for a downstream target.
- **No automatic Plex target configuration or refresh.** The generated XMLTV file and exact identity-binding report are separate outputs that downstream Plex configuration must consume explicitly.
- **No automatic Plex refresh.** Re-running the build regenerates `output/merged.m3u`; pointing Plex at the new file or refreshing its channel list is a manual step.
- **The complete event-guide workflow is not implemented yet.** Stage D provides the beginner workflow's report-only event-pattern preview, and Stage E provides a read-only future-acceptance plan. Stable title/time/pattern identity is separated from volatile statistics, game summaries, standings, and roster/player facts; those details are omitted or marked for review unless freshness, season context, provenance, and contradiction checks prove them current. The current Stage A/B path does not synthesize those volatile facts; Stage E only evaluates optional safe metadata when a producer supplies it. Neither stage accepts or adopts rules, publishes guides, mutates provider/downstream/accepted state, or creates a learned-rule store. Schedule-source adapters, documented AED-definition JSON import, expert regex/date/time overrides, unattended event refresh, automatic relearning/adoption, beginner GUI integration, and guide publication remain future work.

## Why these are deferred, not abandoned

ChannelForge's evidence-over-assumptions rule (ADR 0005) keeps the supported remote path bounded and fail-closed. Stale, corrupt, or unvalidated disposable cache data never becomes a successful build. Local and remote XMLTV failures are visible in the build status, the public `merged.xml` path is absent after a non-successful run, and any prior artifact is retained only in the non-published rollback area.

## Where to go next

- Want the engineering-level milestone breakdown? → [ROADMAP.md](../../ROADMAP.md)
- Ready to try what _is_ implemented? → [Build Your First Lineup](Build-Your-First-Lineup.md)
- Hit a problem? → [Troubleshooting](TROUBLESHOOTING.md)
