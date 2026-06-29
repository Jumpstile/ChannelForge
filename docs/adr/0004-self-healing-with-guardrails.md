# ADR 0004: Self-healing with guardrails

## Status

Accepted

## Context

Provider playlists, channel names, guide IDs, logos, and EPG sources may change over time. ChannelForge should detect drift and repair safe changes automatically where possible.

## Decision

ChannelForge will support self-healing behavior with strict guardrails.

Repairs are divided into three levels:

1. Auto-fix

   - High confidence

   - Safe

   - Reversible

   - Fully documented in build reports

2. Suggest fix

   - Medium confidence

   - Requires user approval

   - Included in review reports

3. Block build

   - Low confidence

   - Ambiguous

   - Security-sensitive

   - Could corrupt lineup or production output

## Consequences

- No risky repair happens silently.

- Every automatic repair must explain why it was made.

- Every repair must be logged in the flight recorder.

- Self-healing must preserve backups and rollback.

- User trust is more important than automation speed.
