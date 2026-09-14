# CLI Reference

The Tauri/React shell includes a native picker bridge, but all supported lineup commands and workflows still run from PowerShell (see [Current Limitations](../CURRENT_LIMITATIONS.md)). This page lists the commands a user runs; for the full module API (functions used internally, like `Read-ChannelForgeProvider`), see the [Developer Guide](../../developer/DEVELOPER_GUIDE.md).

## `scripts/Build-Lineup.ps1`

The main build command. Run from the repository root:

```powershell
pwsh -File scripts/Build-Lineup.ps1
```

| Parameter       | Required | Default                            | Notes                                                                                                                                                                                        |
| --------------- | -------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Root`         | No       | Repository root                    | Where `data/` and `output/` are resolved from. You won't normally need to set this.                                                                                                          |
| `-ProviderPath` | No       | _(none — triggers auto-discovery)_ | Explicit override for which provider config file to use, relative to `data/providers/`. See [Safe Local Configuration](../SAFE_LOCAL_CONFIGURATION.md#advanced-pointing-at-a-specific-file). |

**Output:** `output/merged.m3u` (if at least one source has `enabled: true` and a `local_playlist`), `output/reports/build-summary.json`, `output/reports/lineup-plan.md`. See [Build Your First Lineup](../Build-Your-First-Lineup.md) for what these mean.

## `scripts/Build-My-Lineup.ps1`

The ChannelForge Guided Setup / Beginner Workflow entry point. It asks for an IPTV playlist (M3U), optionally asks for a TV guide (XMLTV), analyzes exact and ambiguous identities, and shows a proposal before publishing anything.

```powershell
pwsh -File scripts/Build-My-Lineup.ps1
```

A material ambiguous guide identity pauses for a choice: keep the channels but publish no guide, or cancel. The no-guide path is valid and never invents EPG data.

| Parameter                          | Required | Notes                                                                                                                                                          |
| ---------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Root`                            | No       | Repository root.                                                                                                                                               |
| `-M3UPath`                         | No       | Playlist path. Omit it to be prompted.                                                                                                                         |
| `-XMLTVPath`                       | No       | Optional guide path. Omit it, or answer blank at the prompt, for no guide.                                                                                     |
| `-Accept`                          | No       | Publishes the reviewed lineup. Without it, only the proposal and result reports are written.                                                                   |
| `-AmbiguousAction`                 | No       | `KeepWithoutGuide` or `Cancel`; omission prompts when ambiguity exists.                                                                                        |
| `-EventPatternPreview`             | No       | Runs the report-only beginner event-pattern preview. It cannot be combined with `-Accept`.                                                                     |
| `-EventPatternExamples`            | No       | Representative event-channel names. Omit to enter pipe-separated examples interactively.                                                                       |
| `-EventPatternType`                | No       | `Fight`, `PPV`, `TemporaryEvent`, `League`, `SingleTeam`, `StreamingEvent`, `Sports`, `Other`, or `Unknown`.                                                   |
| `-EventPatternGroup`               | No       | Optional event group label.                                                                                                                                    |
| `-EventPatternTimezoneMap`         | No       | Optional abbreviation-to-offset mapping, for example `[ordered]@{ ET = '-05:00'; UTC = '+00:00' }`.                                                            |
| `-EventPatternDefaultTimezone`     | No       | Optional numeric offset used when an example has no timezone.                                                                                                  |
| `-EventPatternReferenceInstantUtc` | No       | UTC reference used to resolve yearless dates.                                                                                                                  |
| `-EventPatternDateOrder`           | No       | `MonthFirst` (default) or `DayFirst`.                                                                                                                          |
| `-EventPatternMinimumExamples`     | No       | Minimum examples required before inference; default `3`, range `2..50`.                                                                                        |
| `-EventPatternEvidence`            | No       | Optional Stage A `GuideEvidenceRecord` objects from provider display text, M3U metadata, XMLTV, AED-derived exports, schedule evidence, or accepted knowledge. |
| `-EventPatternInputField`          | No       | Evidence/name field to inspect: `DisplayName`, `TvgName`, or `OriginalName`; default `DisplayName`.                                                            |
| `-EventPatternExistingRule`        | No       | Optional existing native rule/candidate used for deterministic drift comparison; adoption remains `NotApplied`.                                                |

**Normal output:** proposal and result reports under `output/reports/`; after explicit acceptance, use `output/guided-setup/accepted/lineup.m3u` and, when selected, `output/guided-setup/accepted/guide.xml`.

**Event-pattern preview output:** `output/reports/guided-event-pattern-preview.json`, `.md`, and `.txt`. The reports are deterministic and redacted. They show the inferred semantic pattern, confidence, provenance, freshness/drift, review state, and safe next action. `CandidateOnly` is always true, `CanPublish` is always false, and `AcceptedStateMutation` is always `None`; no guide, provider, downstream, or accepted state changes. `Confirmed` and `SafeCandidate` remain provisional; `NeedsReview`, `Unresolved`, `Contradiction`, `StaleSource`, and `SourceUnavailable` are blocked.

**Example — preview event-channel naming intelligence without accepting it:**

```powershell
pwsh -File scripts/Build-My-Lineup.ps1 `
  -M3UPath C:\private\playlist.m3u `
  -EventPatternPreview `
  -EventPatternExamples 'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm' 'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm' 'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm' `
  -EventPatternType Fight `
  -EventPatternReferenceInstantUtc '2024-04-15T00:00:00Z'
```

The preview never accepts an inferred rule and never publishes XMLTV. Use the existing `-Accept` flow separately only after a person has reviewed the ordinary lineup proposal; `-EventPatternPreview -Accept` fails closed.

**Example — using an explicit provider file instead of auto-discovery:**

```powershell
pwsh -File scripts/Build-Lineup.ps1 -ProviderPath provider.local.json
```

## `scripts/Get-ChannelForgeSourceRefreshPlan.ps1`

Read-only planning evidence for configured provider and EPG sources. It reads configuration and validated disposable cache metadata without contacting any source.

```powershell
pwsh -File scripts/Get-ChannelForgeSourceRefreshPlan.ps1
```

For deterministic evaluation or a separate report location:

```powershell
pwsh -File scripts/Get-ChannelForgeSourceRefreshPlan.ps1 `
  -EvaluationTimeUtc 2026-01-01T00:00:00Z `
  -OutputRoot C:\private\reports
```

The plan reports `USE_VALID_CACHE`, `CONDITIONAL_REFRESH`, `FULL_REFRESH`, or `REVIEW`. It never creates a generation, publishes output, replaces the accepted pointer, or changes provider/downstream state.

**Output:** `output/reports/source-refresh-plan.json` and `output/reports/source-refresh-plan.md`.

## `scripts/Invoke-ChannelForgeSourceRefresh.ps1`

Run one bounded refresh of disposable source cache evidence:

```powershell
pwsh -File scripts/Invoke-ChannelForgeSourceRefresh.ps1
```

Fresh validated caches are reused without a request. Expired caches use a **conditional refresh** when ETag or Last-Modified evidence exists; this asks whether previously downloaded content changed. Otherwise, ChannelForge performs a full refresh and validates the response before promotion. The **last-known-good** cache is the most recent validated source copy retained when a new refresh cannot be trusted. Failed, malformed, empty, unsafe, or invalid responses never replace it.

Disabled and local sources are not fetched. The executor does not publish a lineup, create a generation, replace the accepted pointer, or modify downstream state.

The result JSON uses `source-refresh-result/v2`. `Result` remains the operation outcome; `Classification` is the attention layer with `AutoHandled`, `Degraded`, `ReviewNeeded`, or `NoAction`. Only `Classification=ReviewNeeded` contributes to top-level `ReviewNeeded` and `ReviewNeededCount`. The operational cache is disposable; accepted lineup authority still comes only from immutable generation promotion.

**Output:** `output/reports/source-refresh-result.json` and `output/reports/source-refresh-result.md`.

## `scripts/Get-ChannelForgeScheduledRefreshPlan.ps1`

Generate report-only scheduled refresh evidence from the existing `source-refresh-result/v2` report:

```powershell
pwsh -File scripts/Get-ChannelForgeScheduledRefreshPlan.ps1
```

The planner resolves policy in this order:

1. `config/scheduled-refresh.local.json`
2. `config/scheduled-refresh.example.json`

It calculates the daily UTC cadence, start-inclusive/end-exclusive window, deterministic jitter, notification level, and safety boundary. It never acquires a lock, starts a worker, fetches a source, mutates a cache, creates accepted state or a generation, replaces a pointer, or publishes M3U/XMLTV output.

For an explicit manual plan:

```powershell
pwsh -File scripts/Get-ChannelForgeScheduledRefreshPlan.ps1 `
  -TriggerKind Manual
```

Manual planning is permitted while scheduling is disabled and outside the scheduled window. It does not count toward scheduled failure counters or shift the next scheduled cadence by default.

Optional deterministic inputs:

```powershell
pwsh -File scripts/Get-ChannelForgeScheduledRefreshPlan.ps1 `
  -EvaluationTimeUtc 2026-01-01T03:00:00Z `
  -ObservedLockState Busy `
  -OutputRoot C:\private\reports
```

`-ObservedLockState` is report-only input. This slice never attempts lock acquisition.

**Output:** `output/reports/scheduled-refresh-plan.json` and `output/reports/scheduled-refresh-plan.md`.

## `scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1`

Run one bounded refresh in the foreground. Manual invocation is the default:

```powershell
pwsh -File scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1
```

Windows Task Scheduler invokes the same wrapper with the scheduler-owned switch:

```powershell
pwsh -File scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1 -ScheduledInvocation
```

Manual mode invokes the report-only planner with `TriggerKind=Manual`; scheduler-owned mode uses `TriggerKind=Scheduled`. Both modes acquire the separate operational lock at `output/operations/scheduled-refresh.lock` and call the existing source-refresh executor at most once. Scheduled mode accepts only a fresh `READY_SCHEDULED` plan and may perform one bounded foreground wait for deterministic jitter.

The command fails closed when the generated plan is invalid or not eligible, the scheduled registration evidence is missing or stale, the operational lock is busy, or the source-refresh result cannot be validated. `Degraded` and `ReviewNeeded` source rows map to a `DEGRADED` run with an appropriate notification decision; there is no separate `ReviewNeeded` run status.

The command never creates a generation, changes accepted state, replaces a pointer, publishes active M3U/XMLTV output, or mutates provider/downstream state. The existing executor may update disposable source cache according to its own bounded contract.

**Outputs:**

- `output/reports/scheduled-refresh-run.json`
- `output/reports/scheduled-refresh-run.md`
- `output/operations/scheduled-refresh-history.json` for scheduler-owned runs
- the existing scheduled plan and source-refresh result reports

## Windows scheduled refresh registration

Scheduling is an explicit, local Windows Task Scheduler integration. It requires an enabled `config/scheduled-refresh.local.json`, PowerShell Core 7.6 or newer, and an interactive user session. The tracked example remains disabled.

Preview and approve installation or update by typing the exact phrase `ENABLE` when prompted:

```powershell
pwsh -File scripts/Install-ChannelForgeScheduledRefresh.ps1
```

For non-interactive automation, pass the explicit approval switch:

```powershell
pwsh -File scripts/Install-ChannelForgeScheduledRefresh.ps1 -Approve
```

The installer owns exactly one daily task at `\ChannelForge\ScheduledRefresh-<root-digest-prefix>`. It stores an explicit UTC `StartBoundary`, resolves an absolute `pwsh.exe`, runs with least privilege and `MultipleInstancesPolicy=IgnoreNew`, and writes redacted registration evidence under `output/operations/`.

List only ChannelForge-owned tasks and inspect one repository root without changing anything:

```powershell
pwsh -File scripts/Get-ChannelForgeScheduledRefreshTask.ps1
pwsh -File scripts/Get-ChannelForgeScheduledRefreshStatus.ps1
```

Uninstall requires typing `REMOVE` or passing `-Approve`:

```powershell
pwsh -File scripts/Uninstall-ChannelForgeScheduledRefresh.ps1 -Approve
```

Foreign or mismatched tasks are never replaced or removed. Disabling the policy blocks future scheduled runs but does not silently unregister the task; use the explicit uninstall command when removal is intended. There is no daemon, service, worker, retry loop, or cross-platform scheduler backend.

This is a manual one-shot command plus an opt-in Windows registration, not a scheduler implementation inside ChannelForge.

## Reviewing an event pattern

After running `Invoke-ChannelForgeGuidePatternInference`, use the Stage C review surface for beginner-readable output:

```powershell
Get-ChannelForgeGuidePatternReview -InferenceResult $result -OutputFormat Markdown
Get-ChannelForgeGuidePatternReview -InferenceResult $result -OutputFormat Json
```

This command is read-only. It returns `CandidateOnly`, keeps publication disabled, preserves accepted state, and omits sensitive source values from JSON and Markdown.

## `Get-ChannelForgeGuidePatternAcceptancePlan`

Create a deterministic, beginner-readable explanation of what accepting an
event pattern would require later:

```powershell
Get-ChannelForgeGuidePatternAcceptancePlan `
  -InputObject $review `
  -OutputFormat Json
Get-ChannelForgeGuidePatternAcceptancePlan `
  -InputObject $review `
  -OutputFormat Markdown
```

The command accepts a Stage B inference result or Stage C/D review object and
returns an object, compact JSON, or Markdown/text plan. Confirmed and
SafeCandidate states are eligible for future acceptance only. Review,
contradiction, stale, unavailable, insufficient-example, and drift states are
blocked or review-only with an explicit reason. The plan always reports
`PlanOnly`, `CandidateOnly`, `CanPublish = false`, `CanAcceptNow = false`,
`AcceptedStateMutation = None`, `ProviderMutation = false`,
`DownstreamMutation = false`, `GuidePublication = false`, and
`Adoption = NotApplied`. It does not write a file or accept a rule.
For Stage C/D-only input, `ProposedFutureRule.Status` is
`NotAvailableFromReview` because those formats intentionally omit candidate
hashes. Pass the Stage B inference result directly when a safe opaque proposed
rule identity is required.

The plan keeps stable pattern identity separate from volatile enrichment.
Statistics, game summaries, standings, and roster/player facts are marked
eligible only when freshness TTL, fetched/data timestamps, season or competition
context, subject identity, provenance, confidence, and contradiction checks pass.
Otherwise the volatile fact is omitted or marked for review. `Markdown` uses
headings/emphasis/lists; `Text` is a plain-text rendering without Markdown
markers.
Stage E evaluates optional safe volatile metadata supplied by evidence; it does not synthesize sports statistics, roster facts, standings, or schedule descriptions.

## Verifying your environment

```powershell
Invoke-Pester ./tests/unit
```

Runs the full test suite. A clean run (`0` failures) confirms your environment matches what ChannelForge expects — see [INSTALL.md](../../reference/INSTALL.md).

```powershell
Import-Module ./src/ChannelForge/ChannelForge.psd1 -Force
```

Loads the ChannelForge module directly, useful if you want to call individual functions (like `Import-ChannelForgeM3UPlaylist`) yourself rather than running the full build.

## Other scripts

The repository has additional scripts (`Backup-IPTVBoss.ps1`, `Validate-Config.ps1`, `Validate-ConfigSchemas.ps1`, and other `Validate-*.ps1` quality-gate scripts) that are primarily developer/CI tooling rather than part of the everyday user workflow. See the [Developer Guide](../../developer/DEVELOPER_GUIDE.md#ci-quality-gates) if you need them.

## Where to go next

- Haven't run a build yet? → [Build Your First Lineup](../Build-Your-First-Lineup.md)
- Command failing? → [Troubleshooting](../TROUBLESHOOTING.md)
