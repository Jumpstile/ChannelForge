# Deterministic Lineup Generation

This page answers: **what does ChannelForge mean by "deterministic," and why does it matter?**

## The idea

**Same input, same output — every time.** If you run a build twice without changing your provider config, playlist files, aliases, or numbering rules, you get byte-for-byte the same `output/merged.m3u`. Nothing about the process depends on randomness, system clock, or the order files happen to be processed in.

This matters because it makes a build **verifiable**: `output/reports/build-summary.json` includes a SHA-256 checksum of the merged file, so you (or an automated check) can confirm a rebuild produced exactly what you expect, not "probably the same thing."

## How this is achieved (a summary, not a spec)

1. **Sorted processing order.** Playlists are parsed in sorted file-path order, never in whatever order they happened to be discovered — so "earlier" in deduplication always means the same thing across runs.
2. **Exact-match alias resolution.** A channel's name is resolved to its canonical form via exact lookup, not fuzzy matching that could behave differently between runs (see [Channel IDs](Channel-IDs.md)).
3. **Exact-match channel numbering.** A channel is numbered only when its group exactly (case-insensitively) matches a configured numbering block — no inference, no guessing.
4. **Fixed, deterministic output rendering.** The merged M3U file is written with a fixed encoding and line ending, so identical channel data always produces identical bytes.

## What this means for you

- You can safely re-run a build any time without worrying it'll silently change something you didn't touch.
- If `merged.m3u`'s checksum _does_ change, something in your inputs changed — that's a feature, not a bug, for catching unexpected drift.
- A channel with no matching alias or numbering-block entry isn't silently guessed at — it passes through unresolved (with a warning, for numbering) rather than ChannelForge inventing an answer. See [ADR 0005, evidence over assumptions](../../adr/0005-evidence-over-assumptions.md).

## Where to go next

- See this in practice → [Build Your First Lineup](../Build-Your-First-Lineup.md)
- Full pipeline detail (for developers) → [Architecture](../../architecture/ARCHITECTURE.md#data-flow-current)
