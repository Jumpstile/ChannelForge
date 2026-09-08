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

## Not implemented yet

- **GUI Guided Setup is validation-preview-only.** The Tauri/React desktop shell includes the Workbench and a three-step Guided Setup layout for choosing a workspace, adding a playlist, and adding a guide. Its Rust-owned native picker bridge opens one item at a time in the order workspace → playlist → guide, then returns only safe selection/status values; React never receives paths, filenames, URLs, credentials, tokens, or file contents. Selection is not validation: the bridge does not read, parse, import, persist, or use the selected items for lineup work, and the browser preview keeps picker controls disabled.
- **Remote acquisition is deliberately narrow.** Provider M3U and XMLTV remote sources require HTTPS on port 443 and bounded streaming; redirects, proxies, credentials, authentication, retries, remote ZIP, stale/offline success, and live-network CI are not supported. Report-only scheduled planning is available without fetching sources.
- **Scheduled refresh is opt-in and Windows-only.** The planner remains report-only, while the manual foreground wrapper remains available and defaults to manual mode. Explicit installation creates one owned daily Task Scheduler task per local root; scheduler-owned mode invokes the bounded source-refresh executor once, with deterministic jitter handled by one bounded foreground wait. There is no always-on worker, daemon, service, cron/systemd registration, autonomous retry loop, or cross-platform scheduler backend.
- **No fuzzy or target-specific guide assignment.** The build reports exact, unambiguous M3U `tvg-id` to XMLTV channel-id bindings, plus unbound, ambiguous, and XMLTV-only identities. It does not guess, perform fuzzy matching, or rewrite the separate canonical M3U/XMLTV outputs for a downstream target.
- **No automatic Plex target configuration or refresh.** The generated XMLTV file and exact identity-binding report are separate outputs that downstream Plex configuration must consume explicitly.
- **No automatic Plex refresh.** Re-running the build regenerates `output/merged.m3u`; pointing Plex at the new file or refreshing its channel list is a manual step.
- **No confidence/evidence scoring or alias conflict review UI yet** — alias resolution exists, but the broader "confidence engine" described in the project's five pillars (see the [repository README](../../README.md#five-pillars)) is still ahead (Milestones 1–2 in [ROADMAP.md](../../ROADMAP.md)).

### GUI status

| Area                           | Status                  |
| ------------------------------ | ----------------------- |
| Workbench shell and navigation | Works now               |
| Guided Setup layout            | Preview only            |
| Native file-picker bridge      | Works now               |
| Display-safe selection status  | Works now               |
| Lineup review and saved lineup | Planned / not built yet |
| Automatic updates              | Planned / not built yet |
| File selection and validation  | Blocked / needs review  |

## Why these are deferred, not abandoned

ChannelForge's evidence-over-assumptions rule (ADR 0005) keeps the supported remote path bounded and fail-closed. Stale, corrupt, or unvalidated disposable cache data never becomes a successful build. Local and remote XMLTV failures are visible in the build status, the public `merged.xml` path is absent after a non-successful run, and any prior artifact is retained only in the non-published rollback area.

## Where to go next

- Want the engineering-level milestone breakdown? → [ROADMAP.md](../../ROADMAP.md)
- Ready to try what _is_ implemented? → [Build Your First Lineup](Build-Your-First-Lineup.md)
- Hit a problem? → [Troubleshooting](TROUBLESHOOTING.md)
