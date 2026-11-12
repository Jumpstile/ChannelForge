# Durable monitor recording architecture

Status: Accepted for implementation

Date: 2026-08-29

## Problem

An external scheduled automation can lose GitHub operation routing while it is
trying to record a meaningful ecosystem finding. A successful-looking comment
request can also lose its response. Retrying without a stable marker can
duplicate evidence; advancing source state without durable queueing can lose
evidence altogether.

ChannelForge monitoring is development-side intelligence. It must not modify
provider systems of record, user installations, runtime configuration, merges,
tags, or releases.

## Contract

The repository-native runner is
`scripts/monitoring/Invoke-ChannelForgeDevelopmentMonitor.ps1`, with the
shared queue and publisher in `scripts/monitoring/MonitorOutbox.psm1`.
Every run:

1. Restores the newest validated spool artifact if the local spool is empty.
2. Replays due pending findings.
3. Takes commit and latest-release snapshots for the approved source manifest.
4. Queues source changes or source-fetch failures before advancing source state.
5. Replays again and writes a run receipt.

The queue provides the following guarantees:

- The idempotency key is SHA-256 over canonical finding content. Observation
  time is excluded, so repeat observations have one identity.
- A pending item stores the finding hash, status, attempts, next-attempt time,
  a redacted error, and recorded comment identity. A conflicting payload with
  the same key is rejected.
- JSON is written to a same-directory temporary file and flushed before an
  atomic replace. A spool write error stops the run and is not turned into a
  misleading source finding.
- The publisher searches bounded issue-comment pages for
  `<!-- monitor-idempotency:<KEY> -->`, posts only if absent, rereads after
  POST, and marks the item recorded only after the marker is visible. An
  uncertain POST is therefore safe to retry.
- Failures remain in `pending/` and use 60, 120, 240, ... 3600 second
  backoff. The recorded copy is written before pending cleanup.
- Source state is advanced only after a usable snapshot and any related
  finding have been durably queued.

## Hosted and persistent operation

The GitHub Actions workflow uses `contents: read`, `actions: read`, and
`issues: write`, non-overlapping concurrency, pinned action revisions, and a
90-day spool artifact. It restores through the Actions API and refuses to
replace the artifact if restoration or validation failed.

The artifact bridges hosted-runner replacement. For outages that may exceed
artifact retention, a self-hosted or local runner sets `MONITOR_SPOOL_ROOT` to
a protected local volume and invokes the same runner. The durable guarantee
begins after the atomic queue write on that volume. Disk loss or deletion is an
infrastructure incident and is never reported as successful recording.

Example local replay:

```powershell
$env:MONITOR_SPOOL_ROOT = 'D:\DevelopmentMonitor\channelforge'
$env:GITHUB_TOKEN = '<short-lived-token>'
pwsh -File .\scripts\monitoring\Invoke-ChannelForgeDevelopmentMonitor.ps1
```

Tokens are environment inputs only and are not written to queue files,
receipts, or repository artifacts. The runner records findings as comments on
existing issue #35; it does not create issues. Compatibility classification
and implementation remain human-reviewed follow-up work.

## Validation and recovery

`tests/unit/MonitorOutbox.Tests.ps1` covers canonical identity, atomic queue
creation, collision rejection, retry/backoff preservation, marker-verified
publishing, and source-state round trips. Parser, PSScriptAnalyzer, config,
Markdown, and Pester gates validate the runner before normal scheduling.

When a run exits with status 2, the queue is still authoritative: inspect the
pending JSON, restore the persistent volume if needed, and rerun the monitor.
An item is removed only after a verified target marker and a durable recorded
copy exist.
