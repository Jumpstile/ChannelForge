# ADR 0011: Security boundaries, adapter isolation, secret handling, and update integrity

## Status

Accepted

## Context

ChannelForge handles provider URLs, external source data, generated artifacts, operational state, and future adapters. These inputs may contain secrets, malformed data, untrusted content, or changed trust characteristics. Automation and publication also require backup, verification, and rollback boundaries.

## Decision

ChannelForge will define explicit trust boundaries for:

- Provider URLs and secret references
- External source and adapter inputs
- Provider and target integrations
- Durable state
- File paths and writes
- Published artifacts
- Backups and rollback points
- External endpoint and source changes
- Update artifacts
- Security and audit evidence

Sensitive values must be redacted from logs, errors, reports, and fixtures.

Incomplete, conflicting, stale, or unverified security evidence must fail closed, remain quarantined, or require review.

No updater implementation or merge of `pr-23-auto-update` is authorized by this ADR.

## Consequences

- External inputs cannot silently inherit trust.
- Provider secrets and tokenized URLs have a defined handling boundary.
- Publication and automation require explicit safety evidence.
- Security decisions remain explainable and reviewable.

## Verification

- Trust boundaries are documented for inputs, adapters, storage, outputs, and automation.
- Redaction requirements are explicit.
- Path, write, backup, verification, and rollback requirements are explicit.
- Update integrity requirements are defined without implementing the updater.

## Related Issues

- #61
- #78
