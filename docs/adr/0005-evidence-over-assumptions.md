# ADR 0005: Evidence over assumptions

## Status

Accepted

## Context

ChannelForge handles provider playlists, EPG sources, channel identity, local rules, generated outputs, and production-adjacent workflows. Incorrect assumptions can leak secrets, corrupt lineups, hide provider drift, or make builds non-repeatable.

The project already values truth, trust, recoverability, determinism, and self-healing. Those values require a decision rule for uncertain situations.

## Decision

ChannelForge will prefer evidence over assumptions.

Important claims must be backed by at least one of:

- Repository source.
- User-approved fact.
- Test result.
- CI result.
- Reproducible command output.
- Documented architecture decision.
- Explicitly labeled inference from available evidence.

When evidence is missing, the project will say it is missing. It will not silently invent facts.

## Consequences

- Reviews must cite files, tests, or observed behavior.
- Ambiguous work should become a question or a GitHub Issue.
- AI collaborators must distinguish evidence from inference.
- Documentation and tests become project memory.
- Self-healing behavior must explain why a repair is safe.

## Related Principles

- Trust but continuously verify.
- Deterministic behavior.
- Security first.
- Documentation is part of the product.
- GitHub Issues as project memory.
