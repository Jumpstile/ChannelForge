# Current Limitations

This page answers: **what can I actually rely on ChannelForge for today, and what should I not expect yet?**

ChannelForge is **Early Alpha**. Treat everything below as the honest, current state — not a roadmap promise. For what's planned and when, see [ROADMAP.md](../../ROADMAP.md).

## Implemented today

- Parsing real M3U provider playlists.
- Reading provider and EPG *source configuration* (validated against a schema and a URL trust-boundary check).
- Deterministic alias resolution and channel numbering — the same input always produces the same output.
- Merging multiple local playlists into one deduplicated `output/merged.m3u`.
- A safe, local-only provider configuration workflow that never requires editing a tracked file (see [Safe Local Configuration](SAFE_LOCAL_CONFIGURATION.md)).
- A build report (`output/reports/build-summary.json`, `lineup-plan.md`) for every run, with a checksum, so you can verify what happened without trusting it blindly.

## Not implemented yet

- **No graphical interface.** Everything is PowerShell scripts run from a cloned repository. A GUI is planned (see Milestone 3 in [ROADMAP.md](../../ROADMAP.md)) but hasn't started.
- **No live provider or EPG fetch over HTTP.** You must already have your playlist file saved locally; ChannelForge doesn't reach out to your provider or an EPG source itself yet. Every source URL is still validated as if it would be fetched, so a malformed URL fails the build early even though nothing calls it today.
- **No XMLTV (program guide) generation.** ChannelForge will not fabricate guide data it doesn't have — see [ADR 0005, evidence over assumptions](../adr/0005-evidence-over-assumptions.md). Every build honestly reports `XMLTVGenerated: false` with the specific reason, rather than producing an empty or fake guide file.
- **No Plex EPG/guide binding**, as a direct consequence of no XMLTV — Plex will show your channels with no schedule information until that exists.
- **No automatic Plex refresh.** Re-running the build regenerates `output/merged.m3u`; pointing Plex at the new file or refreshing its channel list is a manual step.
- **No confidence/evidence scoring or alias conflict review UI yet** — alias resolution exists, but the broader "confidence engine" described in the project's five pillars (see the [repository README](../../README.md#five-pillars)) is still ahead (Milestones 1–2 in [ROADMAP.md](../../ROADMAP.md)).

## Why these are deferred, not abandoned

ChannelForge's evidence-over-assumptions rule (ADR 0005) means a feature that would require guessing or fabricating data is deliberately not built until the real data source exists, rather than shipped half-working. The build report's `XMLTVDeferredReason` field is a direct, visible example of this in practice — you always get an honest answer for why something isn't there, not silence or a fake result.

## Where to go next

- Want the engineering-level milestone breakdown? → [ROADMAP.md](../../ROADMAP.md)
- Ready to try what *is* implemented? → [Build Your First Lineup](Build-Your-First-Lineup.md)
- Hit a problem? → [Troubleshooting](TROUBLESHOOTING.md)
