# Current Limitations

This page answers: **what can I actually rely on ChannelForge for today, and what should I not expect yet?**

ChannelForge is **Early Alpha**. Treat everything below as the honest, current state — not a roadmap promise. For what's planned and when, see [ROADMAP.md](../../ROADMAP.md).

## Implemented today

- Parsing real M3U provider playlists.
- Reading provider and EPG source configuration, including local XMLTV paths and remote URL trust-boundary validation.
- Deterministic alias resolution and channel numbering — the same input always produces the same output.
- Merging multiple local playlists into one deduplicated `output/merged.m3u`.
- Importing configured local XMLTV `.xml`, `.gz`, and single-entry `.zip` files.
- Deterministically merging and exporting validated local XMLTV data to `output/merged.xml`; a failed or deferred XMLTV run leaves that public path absent and quarantines any prior artifact for rollback/inspection only.
- A safe, local-only provider configuration workflow that never requires editing a tracked file (see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md)).
- A build report (`output/reports/build-summary.json`, `lineup-plan.md`) for every run, with a checksum, so you can verify what happened without trusting it blindly.

## Not implemented yet

- **No graphical interface.** Everything is PowerShell scripts run from a cloned repository. A GUI is planned (see Milestone 3 in [ROADMAP.md](../../ROADMAP.md)) but hasn't started.
- **No live provider or remote EPG fetch over HTTP.** Provider playlists and XMLTV inputs must be local files in this slice. Remote EPG URLs remain structurally valid and are validated without network access; they are reported as deferred.
- **No remote XMLTV acquisition or automatic guide binding.** Configured local XMLTV files can produce deterministic `output/merged.xml`; remote acquisition, M3U channel binding, and downstream guide integration remain deferred.
- **No automatic Plex EPG/guide binding.** The generated XMLTV file is a separate output that downstream Plex configuration must consume explicitly.
- **No automatic Plex refresh.** Re-running the build regenerates `output/merged.m3u`; pointing Plex at the new file or refreshing its channel list is a manual step.
- **No confidence/evidence scoring or alias conflict review UI yet** — alias resolution exists, but the broader "confidence engine" described in the project's five pillars (see the [repository README](../../README.md#five-pillars)) is still ahead (Milestones 1–2 in [ROADMAP.md](../../ROADMAP.md)).

## Why these are deferred, not abandoned

ChannelForge's evidence-over-assumptions rule (ADR 0005) means remote acquisition and any degraded/offline success path remain deferred until their transport and freshness policies are accepted. Local XMLTV failures are visible in the build status, the public `merged.xml` path is absent after a non-successful XMLTV run, and any prior artifact is retained only in the non-published rollback area.

## Where to go next

- Want the engineering-level milestone breakdown? → [ROADMAP.md](../../ROADMAP.md)
- Ready to try what *is* implemented? → [Build Your First Lineup](Build-Your-First-Lineup.md)
- Hit a problem? → [Troubleshooting](TROUBLESHOOTING.md)
