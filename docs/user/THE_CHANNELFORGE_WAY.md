# The ChannelForge Way

> Status: Living document

## Purpose

Explain the culture and mindset behind ChannelForge.

## Audience

Everyone — users, contributors, and AI collaborators.

## Truth before output

ChannelForge does not treat a provider's channel name as fact. A name is evidence. Channel identity — call sign, network, market, guide ID, confidence score — is what ChannelForge actually trusts (see [Channel Identity Model](../architecture/CHANNEL_IDENTITY_MODEL.md)). When evidence is missing, ChannelForge says so instead of guessing (see [ADR 0005](../adr/0005-evidence-over-assumptions.md)).

## Trust through explanation

Every automated decision should be explainable. If ChannelForge resolves an alias, scores confidence, or flags a duplicate, it should be possible to point at the evidence that led to that outcome. A decision nobody can explain is a decision nobody should trust.

## Recoverability over speed

Production lineups, generated playlists, and guide data are valuable. Before anything touches production, ChannelForge backs it up, verifies the change, and backs it up again. A repair that can't be undone is not a safe repair.

## Determinism

The same provider data, the same EPG sources, and the same rules should produce the same lineup every time. Non-determinism is allowed only when it's intentional, documented, and isolated — never as an accident of implementation.

## Self-healing, never silent

ChannelForge may repair high-confidence, reversible problems automatically. Anything ambiguous, risky, or security-sensitive stops and asks for review instead of guessing (see [ADR 0004](../adr/0004-self-healing-with-guardrails.md)).

## Why this matters

Television metadata drifts constantly: providers rename channels, EPG IDs change, logos break, duplicates appear. A tool that blindly trusts that drift produces broken lineups. ChannelForge exists so that drift gets detected, explained, and fixed safely instead of silently corrupting someone's television setup.

## Where to go next

- [Channel Identity Model](../architecture/CHANNEL_IDENTITY_MODEL.md) — what ChannelForge actually trusts.
- [Manifesto](../architecture/MANIFESTO.md) — the short version of these values.
- [Engineering Principles](../engineering/ENGINEERING_PRINCIPLES.md) — how these values become day-to-day practice.
