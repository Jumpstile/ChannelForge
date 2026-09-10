# Channel IDs

This page answers: **why doesn't ChannelForge just trust the channel name in my playlist?**

## The core idea

ChannelForge treats a channel's identity as more than a single string from a playlist. A provider's label for a channel can change, be inconsistent across providers, or simply be wrong — but the channel's real-world identity (which station it is, what network, what market) doesn't change just because a label did.

**Provider labels are evidence. They are not truth by themselves.**

## What makes up a channel's identity

A full channel identity can include its canonical name, station call sign, network, affiliate, market, country, language, virtual and RF channel numbers, every provider name it's known by, aliases, guide IDs, logo references, and a confidence score reflecting how sure ChannelForge is about all of the above.

For example, a single playlist entry isn't just a string — it might represent: an NBC affiliate, in the Scranton/Wilkes-Barre market, known by several different provider names and guide IDs, but with one stable real-world identity underneath all of that.

## What's implemented today vs. planned

- **Implemented today:** exact-match alias resolution (`data/rules/aliases.json`) maps known alternate provider names to one canonical name during a build. A channel with no matching alias entry passes through under its normalized name unchanged.
- **Implemented today for event-guide evidence:** Stage A/B contracts preserve source evidence and provide read-only confidence, provenance, and native event-pattern drift analysis. This does not rewrite stable channel identity or replace accepted mappings.
- **Planned:** the broader channel-identity Confidence Engine — evidence-based identity scoring, canonical mapping decisions, and review of ambiguous station matches — remains future work (see Milestone 2 in [ROADMAP.md](../../../ROADMAP.md)). Today's alias resolution is deterministic and exact-match only.

## Where to go next

- The full conceptual model → [Channel Identity Model](../../architecture/CHANNEL_IDENTITY_MODEL.md) (engineering doc; this page summarizes it)
- See alias resolution in action → [Build Your First Lineup](../Build-Your-First-Lineup.md)
