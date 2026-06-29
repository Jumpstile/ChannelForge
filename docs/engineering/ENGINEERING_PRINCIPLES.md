# Engineering Principles

> Status: Living document

## Purpose

Define the engineering standards ChannelForge follows day to day. This page operationalizes the values in [PRINCIPLES.md](../../PRINCIPLES.md) and the rules in [CONSTITUTION.md](../../CONSTITUTION.md).

## Audience

Developers and maintainers.

## Safety

- Back up before any operation that modifies production data, verify the backup, make the change, verify again, and create a post-operation backup (see [ADR 0004](../adr/0004-self-healing-with-guardrails.md)).
- Production writes require explicit approval; nothing should be overwritten silently.
- Self-healing repairs follow the three-level model in ADR 0004: auto-fix (safe, reversible), suggest-fix (needs approval), or block build (ambiguous or security-sensitive).

## Testing

- Every public function gets a Pester test covering its happy path and at least one failure case.
- Every bug fix gets a regression test (see [LESSONS_LEARNED.md](../../LESSONS_LEARNED.md) for examples of bugs that became tests).
- Parser and ingestion tests must include malformed and edge-case fixtures, not only valid input.
- The full suite (`Invoke-Pester ./tests/unit`) must pass locally before a commit, and CI must be green before merge.

## Documentation

- A feature is incomplete until a careful beginner can understand what it does, why it matters, how to use it, what success looks like, and how to recover from failure.
- Repository docs are the engineering source of truth; the GitHub Wiki is the user-facing knowledge base (see [DOCS_AND_WIKI.md](../reference/DOCS_AND_WIKI.md)).
- Documentation changes land in the same change as the behavior they describe.

## Security

- Treat provider URLs, account IDs, tokens, generated playlists, XMLTV data, logs, backups, and production paths as sensitive at every stage of design, implementation, and review — not as a final pass (see [SECURITY.md](../reference/SECURITY.md)).
- Validate external input at the boundary where it enters the system (provider/EPG ingestion, playlist parsing, alias files).
- Never print secrets or full provider URLs in errors, logs, or reports.

## Backup rules

- Required backup points: before starting any production-changing operation, and after it completes successfully.
- Backups must be clearly named, timestamped, and stored outside the working output folder.
- Recovery must always be possible; never remove a backup as part of normal operation.

## Release gates

Before release, complete the [Go/No-Go Checklist](../../engineering/GoNoGoChecklist.md): full test suite passing, CI green, security and vulnerability sweeps complete, backup/restore tested, documentation current.

## Checklist discipline

Day-to-day changes follow the lifecycle in the [Flight Manual](../../engineering/FlightManual.md): preflight, taxi, takeoff, cruise, descent, landing, postflight. Use it to catch preventable mistakes, not as a substitute for engineering judgment.

## Evidence over assumptions

Every important engineering claim must be grounded in repository evidence — source, tests, logs, documentation, or reproducible behavior (see [ADR 0005](../adr/0005-evidence-over-assumptions.md)). If evidence is missing, say so; do not invent it.
