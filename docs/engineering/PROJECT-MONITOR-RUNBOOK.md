# ChannelForge Development Monitor Runbook

## Purpose and boundary

This runbook operates the ChannelForge development monitor. The monitor watches approved ecosystem repositories and records review-needed evidence on ChannelForge issue #35.

This is development intelligence only. It does not modify production services, alter provider data, repair a lineup automatically, merge code, create releases, or run as a scheduled task on user machines.

The monitor is implemented by:

- Workflow: `.github/workflows/development-monitor.yml`
- Runner: `scripts/monitoring/Invoke-ChannelForgeDevelopmentMonitor.ps1`
- Source manifest: `scripts/monitoring/channelforge-monitor-sources.json`
- Outbox and recording module: `scripts/monitoring/MonitorOutbox.psm1`
- Artifact restore: `scripts/monitoring/Restore-MonitorArtifact.ps1`
- Target issue: `Jumpstile/ChannelForge#35`

## Schedule and permissions

The GitHub Actions workflow runs at 04:37 UTC every Monday and supports manual dispatch with a `dry_run` input.

The workflow requires these permissions:

- `contents: read`
- `actions: read`
- `issues: write`

A concurrency group prevents overlapping monitor runs. The workflow checks out the repository, restores the durable spool, runs the monitor, and uploads the spool with 90-day retention.

## Approved sources

The manifest currently monitors:

| Source ID | Repository |
|---|---|
| `dispatcharr` | `Dispatcharr/Dispatcharr` |
| `threadfin` | `Threadfin/Threadfin` |
| `tvheadend` | `tvheadend/tvheadend` |
| `teamarr` | `Pharaoh-Labs/teamarr` |
| `stationarr` | `rroy676/Stationarr` |
| `m3u-editor` | `m3ue/m3u-editor` |
| `cabernet` | `cabernetwork/cabernet` |
| `tunarr` | `chrisbenincasa/tunarr` |
| `iptvnator` | `4gray/iptvnator` |

For each source, the collector reads the latest commit and latest release when available. Source changes and source-fetch failures are distinct evidence types.

## Adding or removing a ChannelForge source

Edit `scripts/monitoring/channelforge-monitor-sources.json`. Each source entry must contain:

- a unique `sourceId` matching the monitor identity rules
- a human-readable `name`
- an owner/name `repository`

To add a source:

1. Confirm the repository is an approved ecosystem source and that its public commit/release data is relevant to ChannelForge review.
2. Add one object to the `sources` array. Keep `monitorId`, `targetRepository`, and `targetIssueNumber` unchanged for a normal source addition.
3. Validate the JSON and inspect the diff.
4. Run `tests/unit/MonitorOutbox.Tests.ps1` and the repository validation scripts.
5. Run the workflow manually with `dry_run: true` and confirm the new source is collected without creating issue comments.
6. Review the first scheduled or intentionally approved publishing run.

Example:

```json
{
  "sourceId": "example-project",
  "name": "Example Project",
  "repository": "example-owner/example-project"
}
```

To remove a source:

1. Remove only that source object from the `sources` array.
2. Do not delete issue comments, `pending/` items, `recorded/` items, or `source-state.json` by hand.
3. Run the focused tests and a workflow `dry_run`.
4. Confirm the removed repository is no longer collected and that existing evidence remains available for review.

If a removed source is later re-added and must establish a fresh baseline, give it a new `sourceId`. Reusing the old identity can cause retained source state to suppress the expected first change finding. Changing `targetIssueNumber` is a separate routing migration and requires explicit review; it is not normal source maintenance.

Use `dry_run` and local test fixtures to validate additions and removals. Do not use a real non-dry run merely to test configuration syntax.


## Normal run

The workflow performs these steps:

1. Restore the latest non-expired `channelforge-development-monitor-spool` artifact when no local state exists.
2. Replay pending outbox items from the previous run.
3. Collect current source snapshots.
4. Compare snapshots with durable source state.
5. Queue source changes or fetch failures as outbox items.
6. Advance source state only after a usable snapshot is collected.
7. Replay the outbox again.
8. Read issue #35 back after each POST and verify the exact idempotency marker.
9. Write a JSON run receipt under the spool `runs` directory.
10. Upload the durable spool for the next scheduled run.

The runner reports `PASS` when no outbox items remain pending and no replay errors occurred. A non-dry run exits with code `2` when pending items or errors remain.

## Manual execution

Use a disposable local spool. Do not point the monitor at application data or a release staging directory.

Dry-run collection and validation without publishing comments:

```powershell
$env:GITHUB_TOKEN = (gh auth token)
$env:MONITOR_SPOOL_ROOT = Join-Path $env:TEMP 'channelforge-development-monitor-manual'

pwsh -NoProfile -File .\scripts\monitoring\Invoke-ChannelForgeDevelopmentMonitor.ps1 -DryRun
```

The receipt should include:

- `repository: Jumpstile/ChannelForge`
- `targetIssueNumber: 35`
- `githubIssue: "#35"`
- `dryRun: true`
- `failedSources: 0` when collection succeeded
- `pendingCount: 0`
- `status: PASS`

A non-dry manual run publishes to issue #35 and is an intentional production-side evidence mutation. Use the focused tests and fake API fixtures for development. Do not use a real non-dry run to experiment with collector behavior.

## Spool layout

The spool root contains:

- `pending/` - outbox items awaiting publication or retry.
- `recorded/` - successfully verified items.
- `runs/` - JSON receipts for individual runs.
- `source-state.json` - last usable snapshot for each source.

Outbox item filenames use the canonical idempotency key. State is durable workflow data, not application data, release input, or a replacement for source control.

## Recording and deduplication

Each finding receives a canonical SHA-256 identity that excludes observation time. Before posting, the module searches issue #35 for:

```text
<!-- monitor-idempotency:<KEY> -->
```

If the marker already exists, the item is recorded locally without another POST. Otherwise the module posts the comment, reads the issue back, verifies the marker, and moves the item atomically from `pending/` to `recorded/`.

If a POST response is ambiguous, the module performs a follow-up marker lookup before treating the operation as failed. This prevents a retry from creating a duplicate comment.

## Failure handling

### Source fetch failure

The source state is not advanced. A `source-fetch-failure` finding is queued for later reconciliation. The finding does not authorize a data repair, configuration change, merge, or release action.

Inspect the receipt and source state:

```powershell
$spool = $env:MONITOR_SPOOL_ROOT
Get-ChildItem -LiteralPath (Join-Path $spool 'runs') -File | Sort-Object Name
Get-Content -LiteralPath (Join-Path $spool 'source-state.json') -Raw
Get-ChildItem -LiteralPath (Join-Path $spool 'pending') -File
```

Correct the upstream access or API problem and allow the next scheduled run to reconcile the finding. Do not delete the pending item or advance source-state.json manually.

### Publish or read-back failure

The pending item remains on disk. Its attempt count, last error, and next-attempt time are updated using bounded exponential backoff. The next run replays due items before collecting new findings.

Do not manually repost an item. Search issue #35 for its idempotency marker first.

### Artifact restore failure

The restore script validates:

- repository and monitor identity
- ZIP traversal safety
- a single unambiguous payload root
- allowed pending, recorded, run, and source-state paths
- destination containment
- deserialized outbox and source-state integrity

Preserve the workflow failure and investigate the artifact. If no artifact exists, the monitor starts with an empty outbox and source state.

## Operator checks

For a failed workflow run:

1. Confirm the workflow run ID and commit SHA.
2. Download the `channelforge-development-monitor-spool` artifact if it exists.
3. Read the newest file under `runs/`.
4. Check `errors`, `pendingCount`, `replayBefore`, and `replayAfter`.
5. Inspect pending items and their `lastError` values.
6. Check issue #35 for the exact idempotency marker before taking manual action.
7. Confirm the receipt reports target issue `#35`.
8. Rerun only after the failure cause is understood.

A healthy non-dry run has `status: PASS`, `failedSources: 0`, `pendingCount: 0`, and no replay errors.

## Validation and tests

Run the focused monitor tests from the repository root:

```powershell
Import-Module Pester -RequiredVersion 5.7.1
Invoke-Pester -Path .\tests\unit\MonitorOutbox.Tests.ps1
```

The tests cover stable identity, HTTPS/API endpoint allowlisting, atomic queueing, duplicate evidence, collision rejection, bounded retry, marker read-back, source-state round trips, source changes, and source-fetch failures.

For documentation or monitor code changes, also run the repository validation scripts as applicable:

```powershell
pwsh -NoProfile -File .\scripts\Validate-ScriptAnalyzer.ps1
pwsh -NoProfile -File .\scripts\Validate-MarkdownLinks.ps1
pwsh -NoProfile -File .\scripts\Validate-MarkdownHygiene.ps1
```

## Security and scope rules

- Supply tokens through `GITHUB_TOKEN`; never place tokens in source, manifests, receipts, or comments.
- API requests are restricted to HTTPS `api.github.com`.
- Do not disable read-back verification or idempotency checks.
- Do not delete pending or recorded evidence to make a run appear healthy.
- Do not treat an upstream change as authorization for automatic repair, merge, or release.
- Keep monitor state and workflow artifacts outside release packages and application data.
