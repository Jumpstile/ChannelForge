# What Is ChannelForge?

## What is ChannelForge?

ChannelForge is a PowerShell tool that turns provider playlists, guide data, and local rules into a clean, deterministic television channel lineup — originally built for IPTVBoss, Dispatcharr, and Plex users who were tired of messy, drifting, untrustworthy channel data.

It doesn't blindly trust playlist names or provider metadata. It validates input, explains what it did, and never silently overwrites your data.

## Is it ready for me?

**Honestly: only if you're comfortable with PowerShell and an early, unfinished tool.**

ChannelForge is **Early Alpha**. There is no complete GUI workflow yet. The repository includes a Tauri/React desktop shell with a safe native picker bridge that performs pre-parse availability checks, bounded structural checks, and a local exact comparison between one selected M3U playlist and one selected XMLTV guide. The GUI reports only safe status, reason codes, and aggregate match counts. It never opens or displays stream URLs, programme titles, or guide channel IDs. Guide checks support plain `.xml`/`.xmltv`, `.gz`, and single-guide `.zip` files with bounded local decompression only; lineup creation, persistence, export, and automatic updates remain outside this GUI slice.

## What does it do today?

- Parses real M3U provider playlists.
- Reads provider and EPG source configuration, importing enabled local or bounded remote XMLTV sources and configured provider M3U sources.
- Resolves channel name aliases and assigns channel numbers deterministically (same input always produces the same output).
- Merges multiple local or configured remote playlists into one clean, deduplicated `output/merged.m3u` file.
- Imports configured local XMLTV `.xml`, `.gz`, and single-entry `.zip` files or supported remote XMLTV streams and writes deterministic `output/merged.xml` after validation.
- Produces a human-readable build report and a machine-readable summary (with a checksum) for every build, so you can verify nothing silently changed.

## Event guides and AED

An **event guide** describes changing programming such as a UFC or other fight, PPV, temporary sports event, league schedule, single-team event, or a permitted ESPN+-style event group. It is more than a channel name: the guide must connect the event, time, timezone, status, and source evidence to a stable channel identity.

An **AED-derived** guide is XMLTV or M3U metadata exported by an external tool such as IPTVBoss. ChannelForge can consume a documented export as a migration or bootstrap input, but the export is evidence, not automatic truth. ChannelForge compares it with other permitted evidence, preserves freshness and provenance, and sends ambiguity to review.

Normal users should not write regular expressions. The native Stage B preview infers bounded, explainable semantic fields from representative examples. Expert regex/date/time controls are not part of this first native slice; low-confidence or contradictory timing is never silently accepted.

Guide evidence can be **confirmed**, a **safe candidate**, **needs review**, **unresolved**, **contradictory**, from a **stale source**, or from an **unavailable source**. These labels describe what ChannelForge knows; they do not publish or replace accepted state by themselves.

### Native event-pattern preview

Give ChannelForge a few representative event-channel names. It returns a read-only candidate rule and an extraction preview; it does not publish a guide or change a lineup:

```powershell
$result = Invoke-ChannelForgeGuidePatternInference `
  -Examples @(
    'UFC 01: Pereira vs Hill // UK Sat 13 Apr 10:00pm // ET Sat 13 Apr 5:00pm',
    'UFC 02: Fight Night // UK Sat 20 Apr 10:00pm // ET Sat 20 Apr 5:00pm'
  ) `
  -TimezoneMap ([ordered]@{ UK = '+00:00'; ET = '-05:00' }) `
  -ReferenceInstantUtc '2024-04-15T00:00:00Z'

$result.ExtractionPreview
```

The preview explains the channel identifier and ordinal, title, date, local time, source timezone labels, canonical `StartUtc`, participants, and event family when those facts are present. `Confirmed` and `SafeCandidate` mean the candidate is useful for review; they do not make it accepted. `NeedsReview`, `Unresolved`, `Contradiction`, `StaleSource`, and `SourceUnavailable` remain visible and cannot replace accepted output.

Yearless dates use the supplied reference instant rather than the machine clock. Abbreviations such as `ET` require an explicit mapping; duplicate timezone representations are compared before confidence can rise. A Stage A evidence input also preserves source relationship, freshness, confidence, and safe provenance fingerprints. Mirrors are not counted as independent agreement.

## What doesn't it do yet?

- **No complete graphical interface workflow.** Guided Setup can select local inputs, structurally check M3U playlists and local XMLTV guides, and report exact aggregate playlist/guide matching. It does not create lineups, persist selections, mutate accepted state, export, or refresh targets. Ambiguous relationships are reported for review and are never accepted automatically.
- **No broad remote integration.** Supported remote provider M3U/XMLTV acquisition is limited to bounded HTTPS on port 443; there is no authentication, credentials, redirect, proxy, retry, remote ZIP, stale/offline success, or live-network CI.
- **No automatic target-specific guide assignment.** ChannelForge can generate validated deterministic M3U/XMLTV outputs and report exact identity bindings, but downstream guide configuration and automatic Plex refresh remain separate.
- **No automatic Plex refresh.** You re-run the build and refresh Plex's channel list yourself.
- **Native event inference is a preview boundary, not a complete event-guide workflow.** Schedule adapters, persistent learned knowledge, AED-definition JSON import, expert overrides, automatic relearning/adoption, and guide publication are not included yet.

See [Current Limitations](CURRENT_LIMITATIONS.md) for the full, task-oriented breakdown of implemented vs. planned, or the [repository README](../../README.md#current-status) and [ROADMAP](../../ROADMAP.md) for the exact engineering-level state — this page only summarizes for a first-time reader.

## What remote acquisition does not do

ChannelForge has a hard rule: it does not fabricate data it cannot verify (see [ADR 0005, evidence over assumptions](../adr/0005-evidence-over-assumptions.md)). Remote sources are published only after the v5 pinned HTTPS transport, bounds, content policy, parser, and deterministic merge/export checks succeed. A stale or corrupt disposable cache is repaired or reported as failure; it is never silently published as current data.

## Where to go next

- Ready to try it? → [Build Your First Lineup](Build-Your-First-Lineup.md)
- Want the engineering detail behind any of this (architecture, ADRs, test suite)? Start at the [repository README](../../README.md).
