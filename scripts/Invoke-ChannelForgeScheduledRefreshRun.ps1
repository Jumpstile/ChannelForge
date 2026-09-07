[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$PolicyPath,
    [string]$SourceRefreshResultPath,
    [string]$ProviderConfigPath,
    [string]$EpgConfigPath,
    [string]$CacheRoot,
    [string]$NotificationHistoryPath,
    [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]::UtcNow),
    [ValidateRange(0, 7200)]
    [int]$TimeoutSeconds = 0
)

$ErrorActionPreference = 'Stop'

function Get-UtcText {
    param([AllowNull()][datetimeoffset]$Value)
    if ($null -eq $Value) { return $null }
    $Value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function ConvertTo-JsonBytes {
    param([Parameter(Mandatory)][object]$Value)
    [Text.Encoding]::UTF8.GetBytes((($Value | ConvertTo-Json -Depth 20) + [Environment]::NewLine))
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($fullPath) -and [IO.Path]::IsPathFullyQualified($fullPath) -and
        -not ([IO.Path]::IsPathRooted($fullPath) -and $fullPath.StartsWith('\\', [StringComparison]::OrdinalIgnoreCase))) {
        return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($fullRoot + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    }
    return $false
}

function Assert-SafePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot
    )
    if (-not (Test-PathWithinRoot -Path $Path -AllowedRoot $AllowedRoot)) {
        throw 'Unsafe path.'
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Unsafe reparse-point path.'
    }
    $fullPath
}

function Resolve-DefaultPath {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory)][string]$FirstChoice,
        [Parameter(Mandatory)][string]$FallbackChoice
    )
    if (-not [string]::IsNullOrWhiteSpace($Value)) { return [IO.Path]::GetFullPath($Value) }
    if (Test-Path -LiteralPath $FirstChoice -PathType Leaf) { return [IO.Path]::GetFullPath($FirstChoice) }
    [IO.Path]::GetFullPath($FallbackChoice)
}

function New-Counts {
    [ordered]@{
        SourceCount = 0
        AttemptedCount = 0
        CacheChangedCount = 0
        LastKnownGoodPreservedCount = 0
        AutoHandled = 0
        Degraded = 0
        ReviewNeeded = 0
        NoAction = 0
    }
}

function New-ReportsProjection {
    [ordered]@{
        RunJson = 'output/reports/scheduled-refresh-run.json'
        RunMarkdown = 'output/reports/scheduled-refresh-run.md'
        PlanJson = 'output/reports/scheduled-refresh-plan.json'
        PlanMarkdown = 'output/reports/scheduled-refresh-plan.md'
        SourceResultJson = 'output/reports/source-refresh-result.json'
        SourceResultMarkdown = 'output/reports/source-refresh-result.md'
    }
}

function New-RunReport {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$RequestedAtUtc
    )
    [ordered]@{
        SchemaVersion = 'scheduled-refresh-run/v1'
        RunId = $RunId
        ScheduleSlotId = 'manual-pending'
        TriggerKind = 'Manual'
        Status = 'BLOCKED'
        RequestedAtUtc = $RequestedAtUtc
        StartedAtUtc = $null
        LastHeartbeatUtc = $null
        FinishedAtUtc = $null
        PolicyDigest = $null
        InputResultSchemaVersion = $null
        InputResultDigest = $null
        Counts = New-Counts
        NotificationDecision = [ordered]@{
            Level = 'Quiet'
            Action = 'NoNotification'
            SummaryCode = 'NoNotification'
        }
        LockEvidence = [ordered]@{
            Path = 'output/operations/scheduled-refresh.lock'
            Acquisition = 'NotAttempted'
            PriorRunId = $null
            PriorRunStatus = 'None'
            PriorHeartbeatUtc = $null
            PriorOwnerTokenHash = $null
            OwnerTokenHash = $null
            MarkerState = 'None'
            ReleaseResult = 'NotAttempted'
        }
        MutationScope = 'ReportOnly'
        FailureCode = 'None'
        Safety = [ordered]@{
            AcceptedStateMutation = 'None'
            GenerationMutation = 'None'
            PointerMutation = 'None'
            PublishedOutputMutation = 'None'
            ProviderStateMutation = 'None'
            IdentityEvidenceMutation = 'None'
            LockMutation = 'None'
            SourceCacheMutation = 'None'
            WrapperNetworkCalls = 0
            RetryCount = 0
        }
        PlanDecision = $null
        PlanReasonCode = $null
        PlanDigest = $null
        ExecutorStatus = 'NotAttempted'
        ExecutorInvocationCount = 0
        ExecutorExitCode = $null
        ExecutorTermination = 'NotAttempted'
        Reports = New-ReportsProjection
        Evidence = [ordered]@{
            PlanInvoked = $false
            PlanValidated = $false
            LockAcquired = $false
            PriorRunAbandoned = $false
            ExecutorInvoked = $false
            ExecutorResultValidated = $false
            TerminationConfirmed = $false
            ReportsWritten = $false
        }
    }
}

function Get-NotificationDecision {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][int]$ReviewNeededCount,
        [Parameter(Mandatory)][int]$DegradedCount
    )
    if ($Status -eq 'TIMED_OUT') {
        return [ordered]@{ Level = 'EscalatedInterrupt'; Action = 'EscalateInterrupt'; SummaryCode = 'RunTimedOut' }
    }
    if ($Status -in @('FAILED', 'BLOCKED')) {
        return [ordered]@{ Level = 'Interrupt'; Action = 'NotifyInterrupt'; SummaryCode = if ($Status -eq 'FAILED') { 'RunFailed' } else { 'RunBlocked' } }
    }
    if ($ReviewNeededCount -gt 0) {
        return [ordered]@{ Level = 'Interrupt'; Action = 'NotifyInterrupt'; SummaryCode = 'ReviewNeededInterrupt' }
    }
    if ($DegradedCount -gt 0) {
        return [ordered]@{ Level = 'Warning'; Action = 'NotifyWarning'; SummaryCode = 'DegradedWarning' }
    }
    [ordered]@{ Level = 'Quiet'; Action = 'NoNotification'; SummaryCode = 'NoNotification' }
}

function Get-PlanReasonCode {
    param([AllowNull()][object]$Plan)
    if ($null -eq $Plan -or $null -eq $Plan.Schedule) { return $null }
    [string]$Plan.Schedule.ReasonCode
}

function Get-SafeRunExplanation {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Report)
    switch ([string]$Report.Status) {
        'SUCCEEDED' { return 'The manual plan was eligible and the existing source-refresh executor completed with only automatically handled or no-action sources.' }
        'DEGRADED' { return 'The existing source-refresh executor completed, but one or more source results need attention or preserved last-known-good evidence.' }
        'TIMED_OUT' { return 'The source-refresh executor exceeded the bounded foreground deadline and was terminated or could not be confirmed stopped.' }
        'FAILED' { return 'The wrapper could not complete a validated source-refresh execution.' }
        'BLOCKED' { return 'The policy, generated plan, or operational lock did not authorize a source-refresh execution.' }
        default { return 'This report records the current operational state of one manual scheduled-refresh run.' }
    }
}

function Write-RunReports {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Report,
        [Parameter(Mandatory)][string]$ReportRoot,
        [Parameter(Mandatory)][string]$SchemaPath
    )
    $jsonPath = Join-Path $ReportRoot 'scheduled-refresh-run.json'
    $markdownPath = Join-Path $ReportRoot 'scheduled-refresh-run.md'
    New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
    [IO.File]::WriteAllText($jsonPath, (($Report | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    if (-not (Test-Json -Path $jsonPath -SchemaFile $SchemaPath -ErrorAction Stop)) {
        throw 'Run report schema validation failed.'
    }

    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add('# Scheduled refresh run')
    $md.Add('')
    $md.Add('## What happened')
    $md.Add('')
    $md.Add((Get-SafeRunExplanation -Report $Report))
    $md.Add('')
    $md.Add("- Status: $($Report.Status)")
    $md.Add("- Trigger: $($Report.TriggerKind)")
    $md.Add("- Requested at (UTC): $($Report.RequestedAtUtc)")
    $md.Add("- Schedule slot: $($Report.ScheduleSlotId)")
    $md.Add("- Failure code: $($Report.FailureCode)")
    $md.Add('')
    $md.Add('## Plan and executor')
    $md.Add('')
    $md.Add("- Plan decision: $($Report.PlanDecision)")
    $md.Add("- Plan reason: $($Report.PlanReasonCode)")
    $md.Add("- Executor status: $($Report.ExecutorStatus)")
    $md.Add("- Executor invocations: $($Report.ExecutorInvocationCount)")
    $md.Add("- Executor termination: $($Report.ExecutorTermination)")
    $md.Add('')
    $md.Add('## Counts')
    $md.Add('')
    $md.Add('| Classification | Count |')
    $md.Add('| --- | ---: |')
    $md.Add("| AutoHandled | $($Report.Counts.AutoHandled) |")
    $md.Add("| Degraded | $($Report.Counts.Degraded) |")
    $md.Add("| ReviewNeeded | $($Report.Counts.ReviewNeeded) |")
    $md.Add("| NoAction | $($Report.Counts.NoAction) |")
    $md.Add('')
    $md.Add('## Notification decision')
    $md.Add('')
    $md.Add("- Level: $($Report.NotificationDecision.Level)")
    $md.Add("- Action: $($Report.NotificationDecision.Action)")
    $md.Add("- Summary: $($Report.NotificationDecision.SummaryCode)")
    $md.Add('')
    $md.Add('## Operational lock')
    $md.Add('')
    $md.Add("- Path: $($Report.LockEvidence.Path)")
    $md.Add("- Acquisition: $($Report.LockEvidence.Acquisition)")
    $md.Add("- Prior run status: $($Report.LockEvidence.PriorRunStatus)")
    $md.Add("- Release: $($Report.LockEvidence.ReleaseResult)")
    $md.Add('Marker contents are diagnostic evidence only. The live operating-system exclusive handle is authoritative.')
    $md.Add('')
    $md.Add('## Safety boundary')
    $md.Add('')
    $md.Add("- Mutation scope: $($Report.MutationScope)")
    $md.Add("- Source cache mutation: $($Report.Safety.SourceCacheMutation)")
    $md.Add('- Accepted state mutation: None')
    $md.Add('- Generation mutation: None')
    $md.Add('- Pointer mutation: None')
    $md.Add('- Published output mutation: None')
    $md.Add('- Provider state mutation: None')
    $md.Add('- Identity evidence mutation: None')
    $md.Add('- Wrapper network calls: 0')
    $md.Add('')
    $md.Add('Detailed source evidence remains in the existing source-refresh-result/v2 report. This wrapper does not publish lineup output or change accepted authority.')
    [IO.File]::WriteAllText($markdownPath, (($md -join [Environment]::NewLine) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $Report.Evidence.ReportsWritten = $true
}

function Write-LockMetadata {
    param(
        [Parameter(Mandatory)][object]$Lease,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Metadata
    )
    $Lease.WriteMetadata((ConvertTo-JsonBytes -Value $Metadata))
}

function Read-LockMetadata {
    param(
        [Parameter(Mandatory)][object]$Lease,
        [Parameter(Mandatory)][string]$SchemaPath
    )
    $bytes = $Lease.ReadMetadata()
    if ($null -eq $bytes -or $bytes.Length -eq 0) { return $null }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if (-not (Test-Json -Json $text -SchemaFile $SchemaPath -ErrorAction Stop)) {
        throw 'Lock metadata schema validation failed.'
    }
    $text | ConvertFrom-Json -ErrorAction Stop
}

function New-LockMetadata {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ScheduleSlotId,
        [Parameter(Mandatory)][string]$OwnerTokenHash,
        [Parameter(Mandatory)][string]$ProcessStartUtc,
        [Parameter(Mandatory)][string]$StartedAtUtc,
        [AllowNull()][string]$PlanDigest
    )
    [ordered]@{
        SchemaVersion = 'scheduled-refresh-lock/v1'
        RunId = $RunId
        ScheduleSlotId = $ScheduleSlotId
        TriggerKind = 'Manual'
        State = 'Running'
        OwnerTokenHash = $OwnerTokenHash
        ProcessId = [int][Diagnostics.Process]::GetCurrentProcess().Id
        ProcessStartUtc = $ProcessStartUtc
        StartedAtUtc = $StartedAtUtc
        HeartbeatAtUtc = $StartedAtUtc
        PlanDigest = if ([string]::IsNullOrWhiteSpace($PlanDigest)) { $null } else { $PlanDigest }
        ExecutorStarted = $false
        ExecutorInvocationCount = 0
    }
}

function Get-CurrentProcessStartUtc {
    try {
        return Get-UtcText -Value ([datetimeoffset][Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime())
    }
    catch {
        Get-UtcText -Value ([datetimeoffset]::UtcNow)
    }
}

function Update-Heartbeat {
    param(
        [Parameter(Mandatory)][object]$Lease,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Metadata,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Report
    )
    $now = Get-UtcText -Value ([datetimeoffset]::UtcNow)
    $Metadata.HeartbeatAtUtc = $now
    $Report.LastHeartbeatUtc = $now
    Write-LockMetadata -Lease $Lease -Metadata $Metadata
}

function Get-ProcessExecutable {
    $candidate = Join-Path $PSHOME 'pwsh.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    (Get-Command pwsh -ErrorAction Stop).Source
}

function Invoke-BoundedSourceExecutor {
    param(
        [Parameter(Mandatory)][string]$ExecutorPath,
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$ProviderPath,
        [Parameter(Mandatory)][string]$EpgPath,
        [Parameter(Mandatory)][string]$CachePath,
        [Parameter(Mandatory)][string]$ReportsPath,
        [Parameter(Mandatory)][datetimeoffset]$Evaluation,
        [Parameter(Mandatory)][int]$Timeout,
        [Parameter(Mandatory)][int]$HeartbeatSeconds,
        [Parameter(Mandatory)][object]$Lease,
        [Parameter(Mandatory)][System.Collections.IDictionary]$LockMetadata,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Report
    )
    $process = $null
    $job = $null
    $startedAt = Get-UtcText -Value ([datetimeoffset]::UtcNow)
    $Report.ExecutorStatus = 'Started'
    $Report.ExecutorInvocationCount = 1
    $Report.Evidence.ExecutorInvoked = $true
    $LockMetadata.ExecutorStarted = $true
    $LockMetadata.ExecutorInvocationCount = 1
    Write-LockMetadata -Lease $Lease -Metadata $LockMetadata
    try {
        $job = Initialize-ChannelForgeProcessJob
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = Get-ProcessExecutable
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $ExecutorPath, '-Root', $RootPath, '-ProviderConfigPath', $ProviderPath, '-EpgConfigPath', $EpgPath, '-CacheRoot', $CachePath, '-OutputRoot', $ReportsPath, '-EvaluationTimeUtc', (Get-UtcText -Value $Evaluation))) {
            $null = $psi.ArgumentList.Add([string]$argument)
        }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $psi
        if (-not $process.Start()) {
            $Report.ExecutorStatus = 'Failed'
            $Report.FailureCode = 'ExecutorStartFailed'
            return [ordered]@{ FailureCode = 'ExecutorStartFailed'; TimedOut = $false; Termination = 'Unconfirmed'; ExitCode = $null; StartedAtUtc = $startedAt; FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow) }
        }
        try {
            $job.Assign($process.Handle)
        }
        catch {
            try { $process.Kill($true) } catch { }
            $Report.ExecutorStatus = 'Failed'
            $Report.FailureCode = 'ExecutorIsolationUnsupported'
            return [ordered]@{ FailureCode = 'ExecutorIsolationUnsupported'; TimedOut = $false; Termination = 'Unconfirmed'; ExitCode = $null; StartedAtUtc = $startedAt; FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow) }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $deadline = [datetimeoffset]::UtcNow.AddSeconds($Timeout)
        $lastHeartbeat = [datetimeoffset]::UtcNow
        $timedOut = $false
        while (-not $process.HasExited) {
            $now = [datetimeoffset]::UtcNow
            if (($now - $lastHeartbeat).TotalSeconds -ge $HeartbeatSeconds) {
                Update-Heartbeat -Lease $Lease -Metadata $LockMetadata -Report $Report
                $lastHeartbeat = $now
            }
            if ($now -ge $deadline) {
                $timedOut = $true
                try { $process.Kill($true) } catch { }
                break
            }
            Start-Sleep -Milliseconds 200
        }
        if ($timedOut) {
            $terminationDeadline = [datetimeoffset]::UtcNow.AddSeconds(30)
            while (-not $process.HasExited -and [datetimeoffset]::UtcNow -lt $terminationDeadline) {
                Start-Sleep -Milliseconds 100
            }
            if (-not $process.HasExited) {
                $Report.ExecutorStatus = 'TimedOut'
                $Report.ExecutorTermination = 'Unconfirmed'
                return [ordered]@{ FailureCode = 'ExecutorTerminationUnconfirmed'; TimedOut = $true; Termination = 'Unconfirmed'; ExitCode = $null; StartedAtUtc = $startedAt; FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow) }
            }
            $Report.ExecutorStatus = 'TimedOut'
            $Report.ExecutorTermination = 'Killed'
            $Report.FailureCode = 'ExecutorTimedOut'
            return [ordered]@{ FailureCode = 'ExecutorTimedOut'; TimedOut = $true; Termination = 'Killed'; ExitCode = $process.ExitCode; StartedAtUtc = $startedAt; FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow) }
        }
        $process.WaitForExit()
        try { $null = $stdoutTask.GetAwaiter().GetResult(); $null = $stderrTask.GetAwaiter().GetResult() } catch { }
        $exitCode = $process.ExitCode
        if ($exitCode -ne 0) {
            $Report.ExecutorStatus = 'Failed'
            $Report.ExecutorTermination = 'Exited'
            $Report.FailureCode = 'ExecutorFailed'
            return [ordered]@{ FailureCode = 'ExecutorFailed'; TimedOut = $false; Termination = 'Exited'; ExitCode = $exitCode; StartedAtUtc = $startedAt; FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow) }
        }
        $Report.ExecutorStatus = 'Succeeded'
        $Report.ExecutorTermination = 'Exited'
        [ordered]@{ FailureCode = 'None'; TimedOut = $false; Termination = 'Exited'; ExitCode = $exitCode; StartedAtUtc = $startedAt; FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow) }
    }
    finally {
        if ($null -ne $process) { $process.Dispose() }
        if ($null -ne $job) { $job.Dispose() }
    }
}

$rootFull = [IO.Path]::GetFullPath($Root)
$requestedAtUtc = Get-UtcText -Value $EvaluationTimeUtc
$runId = [guid]::NewGuid().ToString('N')
$reportsRoot = Join-Path $rootFull 'output/reports'
$operationsRoot = Join-Path $rootFull 'output/operations'
$lockPath = Join-Path $operationsRoot 'scheduled-refresh.lock'
$runSchemaPath = Join-Path $rootFull 'schemas/scheduled-refresh-run.schema.json'
$lockSchemaPath = Join-Path $rootFull 'schemas/scheduled-refresh-lock.schema.json'
$policySchemaPath = Join-Path $rootFull 'schemas/scheduled-refresh-policy.schema.json'
$planSchemaPath = Join-Path $rootFull 'schemas/scheduled-refresh-plan.schema.json'
$sourceResultSchemaPath = Join-Path $rootFull 'schemas/source-refresh-result.schema.json'
$plannerPath = Join-Path $rootFull 'scripts/Get-ChannelForgeScheduledRefreshPlan.ps1'
$executorPath = Join-Path $rootFull 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'
$lockInitializerPath = Join-Path $rootFull 'src/ChannelForge/Private/Initialize-ChannelForgeGenerationStore.ps1'
$processJobPath = Join-Path $rootFull 'src/ChannelForge/Private/Initialize-ChannelForgeProcessJob.ps1'
$report = New-RunReport -RunId $runId -RequestedAtUtc $requestedAtUtc
$lease = $null
$lockMetadata = $null

try {
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container) -or
        -not (Test-PathWithinRoot -Path $rootFull -AllowedRoot $rootFull)) {
        $report.FailureCode = 'RootPathUnsafe'
        Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath
        [pscustomobject]$report
        return
    }
    foreach ($requiredPath in @($plannerPath, $executorPath, $lockInitializerPath, $processJobPath, $policySchemaPath, $planSchemaPath, $sourceResultSchemaPath, $runSchemaPath, $lockSchemaPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw 'Required implementation file is missing.' }
    }
    $policyPath = Resolve-DefaultPath -Value $PolicyPath -FirstChoice (Join-Path $rootFull 'config/scheduled-refresh.local.json') -FallbackChoice (Join-Path $rootFull 'config/scheduled-refresh.example.json')
    $sourceResultPath = if ([string]::IsNullOrWhiteSpace($SourceRefreshResultPath)) { Join-Path $reportsRoot 'source-refresh-result.json' } else { [IO.Path]::GetFullPath($SourceRefreshResultPath) }
    $providerPath = Resolve-DefaultPath -Value $ProviderConfigPath -FirstChoice (Join-Path $rootFull 'data/providers/provider.local.json') -FallbackChoice (Join-Path $rootFull 'data/providers/provider.example.json')
    $epgPath = Resolve-DefaultPath -Value $EpgConfigPath -FirstChoice (Join-Path $rootFull 'data/epg/epg_sources.local.json') -FallbackChoice (Join-Path $rootFull 'data/epg/epg_sources.example.json')
    $cachePath = if ([string]::IsNullOrWhiteSpace($CacheRoot)) { Join-Path $rootFull 'output/cache' } else { [IO.Path]::GetFullPath($CacheRoot) }
    Assert-SafePath -Path $policyPath -AllowedRoot (Join-Path $rootFull 'config') | Out-Null
    Assert-SafePath -Path $sourceResultPath -AllowedRoot $reportsRoot | Out-Null
    Assert-SafePath -Path $providerPath -AllowedRoot (Join-Path $rootFull 'data/providers') | Out-Null
    Assert-SafePath -Path $epgPath -AllowedRoot (Join-Path $rootFull 'data/epg') | Out-Null
    Assert-SafePath -Path $cachePath -AllowedRoot (Join-Path $rootFull 'output') | Out-Null
    Assert-SafePath -Path $reportsRoot -AllowedRoot (Join-Path $rootFull 'output') | Out-Null
    Assert-SafePath -Path $operationsRoot -AllowedRoot (Join-Path $rootFull 'output') | Out-Null
    New-Item -ItemType Directory -Force -Path $reportsRoot, $operationsRoot, $cachePath | Out-Null
    Assert-SafePath -Path $operationsRoot -AllowedRoot (Join-Path $rootFull 'output') | Out-Null

    if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
        $report.FailureCode = 'PolicyMissing'
        $report.Status = 'BLOCKED'
        $report.NotificationDecision = Get-NotificationDecision -Status 'BLOCKED' -ReviewNeededCount 0 -DegradedCount 0
        Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath
        [pscustomobject]$report
        return
    }
    try {
        if (-not (Test-Json -Path $policyPath -SchemaFile $policySchemaPath -ErrorAction Stop)) { throw 'Policy schema invalid.' }
        $policyRaw = Get-Content -LiteralPath $policyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $report.FailureCode = if ($_.Exception.Message -match 'schema') { 'PolicySchemaInvalid' } else { 'PolicyUnreadable' }
        $report.Status = 'BLOCKED'
        $report.NotificationDecision = Get-NotificationDecision -Status 'BLOCKED' -ReviewNeededCount 0 -DegradedCount 0
        Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath
        [pscustomobject]$report
        return
    }
    $policyTimeout = [int]$policyRaw.MaxRunDurationMinutes * 60
    $effectiveTimeout = if ($TimeoutSeconds -gt 0) { [Math]::Min($TimeoutSeconds, $policyTimeout) } else { $policyTimeout }
    if ($TimeoutSeconds -gt $policyTimeout) { $report.FailureCode = 'PlanNotEligible'; $report.Status = 'BLOCKED'; $report.NotificationDecision = Get-NotificationDecision -Status 'BLOCKED' -ReviewNeededCount 0 -DegradedCount 0; Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath; [pscustomobject]$report; return }

    . $lockInitializerPath
    . $processJobPath
    $null = Initialize-ChannelForgeGenerationStore
    try {
        $lease = [ChannelForge.GenerationStore]::AcquireLock($lockPath)
    }
    catch {
        $report.Status = 'BLOCKED'
        $report.FailureCode = if ($_.Exception.Message -match 'reparse|hard link|multiple hard') { 'LockPathUnsafe' } else { 'LockBusy' }
        $report.LockEvidence.Acquisition = if ($report.FailureCode -eq 'LockBusy') { 'Busy' } else { 'Rejected' }
        $report.NotificationDecision = Get-NotificationDecision -Status 'BLOCKED' -ReviewNeededCount 0 -DegradedCount 0
        Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath
        [pscustomobject]$report
        return
    }

    $priorMarker = $null
    try { $priorMarker = Read-LockMetadata -Lease $lease -SchemaPath $lockSchemaPath } catch { $report.Status = 'BLOCKED'; $report.FailureCode = 'LockMetadataMalformed'; $report.LockEvidence.Acquisition = 'Acquired'; $report.Evidence.LockAcquired = $true; $lease.Dispose(); $lease = $null; $report.LockEvidence.ReleaseResult = 'Released'; $report.NotificationDecision = Get-NotificationDecision -Status 'BLOCKED' -ReviewNeededCount 0 -DegradedCount 0; Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath; [pscustomobject]$report; return }
    if ($null -ne $priorMarker -and [string]$priorMarker.State -eq 'TerminationUnconfirmed') {
        $report.Status = 'BLOCKED'
        $report.FailureCode = 'ExecutorTerminationUnconfirmed'
        $report.LockEvidence.Acquisition = 'Acquired'
        $report.LockEvidence.MarkerState = 'TerminationUnconfirmed'
        $report.Evidence.LockAcquired = $true
        $report.NotificationDecision = Get-NotificationDecision -Status 'BLOCKED' -ReviewNeededCount 0 -DegradedCount 0
        $lease.Dispose()
        $lease = $null
        $report.LockEvidence.ReleaseResult = 'Released'
        $report.FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow)
        Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath
        [pscustomobject]$report
        return
    }


    $ownerTokenHash = Get-Sha256Hex -Value ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
    $startedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow)
    $lockMetadata = New-LockMetadata -RunId $runId -ScheduleSlotId $report.ScheduleSlotId -OwnerTokenHash $ownerTokenHash -ProcessStartUtc (Get-CurrentProcessStartUtc) -StartedAtUtc $startedAtUtc -PlanDigest $null
    $report.Status = 'RUNNING'
    $report.StartedAtUtc = $startedAtUtc
    $report.LastHeartbeatUtc = $startedAtUtc
    $report.MutationScope = 'ReportOnly'
    $report.LockEvidence.Acquisition = 'Acquired'
    $report.LockEvidence.OwnerTokenHash = $ownerTokenHash
    $report.Evidence.LockAcquired = $true
    if ($null -ne $priorMarker) {
        $report.LockEvidence.PriorRunId = [string]$priorMarker.RunId
        $report.LockEvidence.PriorHeartbeatUtc = [string]$priorMarker.HeartbeatAtUtc
        $report.LockEvidence.PriorOwnerTokenHash = [string]$priorMarker.OwnerTokenHash
        $report.LockEvidence.MarkerState = [string]$priorMarker.State
        $report.LockEvidence.PriorRunStatus = switch ([string]$priorMarker.State) {
            'Running' { 'Abandoned' }
            'Stopping' { 'Abandoned' }
            'TerminationUnconfirmed' { 'Abandoned' }
            'TimedOut' { 'TimedOut' }
            'Completed' { 'Completed' }
            'Abandoned' { 'Abandoned' }
            default { 'Unknown' }
        }
        $report.Evidence.PriorRunAbandoned = $report.LockEvidence.PriorRunStatus -eq 'Abandoned'
    }
    Write-LockMetadata -Lease $lease -Metadata $lockMetadata
    Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath

    $plannerArguments = @{
        Root = $rootFull
        PolicyPath = $policyPath
        SourceRefreshResultPath = $sourceResultPath
        EvaluationTimeUtc = $EvaluationTimeUtc
        OutputRoot = $reportsRoot
        TriggerKind = 'Manual'
        ObservedLockState = 'NotAttempted'
    }
    if (-not [string]::IsNullOrWhiteSpace($NotificationHistoryPath)) { $plannerArguments.NotificationHistoryPath = [IO.Path]::GetFullPath($NotificationHistoryPath) }
    $report.Evidence.PlanInvoked = $true
    $plannerSucceeded = $true
    try { & $plannerPath @plannerArguments | Out-Null } catch { $plannerSucceeded = $false }
    $planPath = Join-Path $reportsRoot 'scheduled-refresh-plan.json'
    $plan = $null
    if (Test-Path -LiteralPath $planPath -PathType Leaf) {
        try {
            if (-not (Test-Json -Path $planPath -SchemaFile $planSchemaPath -ErrorAction Stop)) { throw 'Plan schema invalid.' }
            $plan = Get-Content -LiteralPath $planPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $report.PlanDigest = Get-FileSha256 -Path $planPath
            $report.PlanDecision = [string]$plan.Schedule.Decision
            $report.PlanReasonCode = Get-PlanReasonCode -Plan $plan
            $report.PolicyDigest = [string]$plan.PolicyDigest
            if ($null -ne $plan.InputResult) {
                $report.InputResultSchemaVersion = [string]$plan.InputResult.SchemaVersion
                $report.InputResultDigest = [string]$plan.InputResult.InputDigest
            }
            $report.Evidence.PlanValidated = $true
        }
        catch {
            $plan = $null
        }
    }
    $planValid = $plannerSucceeded -and $null -ne $plan -and
        [string]$plan.SchemaVersion -eq 'scheduled-refresh-plan/v1' -and
        [string]$plan.TriggerKind -eq 'Manual' -and
        [string]$plan.InputValidation.Status -eq 'Valid' -and
        [string]$plan.Schedule.Decision -eq 'READY_MANUAL' -and
        [string]$plan.LockObservation.Status -eq 'NotAttempted' -and
        ([datetimeoffset]$plan.EvaluatedAtUtc).ToUniversalTime() -eq $EvaluationTimeUtc.ToUniversalTime()
    if (-not $planValid) {
        $report.Status = 'BLOCKED'
        $report.FailureCode = if ($null -eq $plan) { if ($plannerSucceeded) { 'PlanMissing' } else { 'PlanGenerationFailed' } } elseif ([string]$plan.InputValidation.Status -ne 'Valid') { 'PlanInputInvalid' } elseif ([string]$plan.TriggerKind -ne 'Manual') { 'TriggerKindNotSupported' } elseif ([string]$plan.Schedule.Decision -ne 'READY_MANUAL') { 'PlanNotEligible' } elseif ([string]$plan.LockObservation.Status -ne 'NotAttempted') { 'PlanLockObservationBlocked' } else { 'PlanNotFresh' }
        $report.NotificationDecision = Get-NotificationDecision -Status 'BLOCKED' -ReviewNeededCount 0 -DegradedCount 0
        $lockMetadata.State = 'Completed'
        Write-LockMetadata -Lease $lease -Metadata $lockMetadata
        $lease.Dispose(); $lease = $null
        $report.LockEvidence.ReleaseResult = 'Released'
        $report.FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow)
        Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath
        [pscustomobject]$report
        return
    }
    $planDigestBefore = $report.PlanDigest
    $planDigestAfter = Get-FileSha256 -Path $planPath
    if ($planDigestBefore -ne $planDigestAfter) {
        $report.Status = 'BLOCKED'
        $report.FailureCode = 'PlanChangedAfterLock'
        $report.NotificationDecision = Get-NotificationDecision -Status 'BLOCKED' -ReviewNeededCount 0 -DegradedCount 0
        $lockMetadata.State = 'Completed'; Write-LockMetadata -Lease $lease -Metadata $lockMetadata; $lease.Dispose(); $lease = $null; $report.LockEvidence.ReleaseResult = 'Released'; $report.FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow); Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath; [pscustomobject]$report; return
    }
    $slotSeed = if ($null -ne $plan.Schedule.NominalDueUtc) { "scheduled|$($plan.PolicyDigest)|$($plan.Schedule.NominalDueUtc)" } else { "manual|$($plan.PolicyDigest)|$($plan.EvaluatedAtUtc)" }
    $report.ScheduleSlotId = ('manual-' + (Get-Sha256Hex -Value $slotSeed).Substring(0, 16))
    $lockMetadata.ScheduleSlotId = $report.ScheduleSlotId
    $lockMetadata.PlanDigest = $report.PlanDigest
    Update-Heartbeat -Lease $lease -Metadata $lockMetadata -Report $report
    Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath

    $heartbeatSeconds = [Math]::Max(1, [int]$policyRaw.HeartbeatIntervalSeconds)
    $executorResult = Invoke-BoundedSourceExecutor -ExecutorPath $executorPath -RootPath $rootFull -ProviderPath $providerPath -EpgPath $epgPath -CachePath $cachePath -ReportsPath $reportsRoot -Evaluation $EvaluationTimeUtc -Timeout $effectiveTimeout -HeartbeatSeconds $heartbeatSeconds -Lease $lease -LockMetadata $lockMetadata -Report $report
    $report.ExecutorExitCode = $executorResult.ExitCode
    if ($executorResult.FailureCode -ne 'None') {
        $report.FailureCode = $executorResult.FailureCode
        $report.Status = if ($executorResult.TimedOut) { 'TIMED_OUT' } else { 'FAILED' }
        $report.MutationScope = 'DisposableSourceCacheOnly'
        $report.Safety.LockMutation = if ($executorResult.FailureCode -eq 'ExecutorTerminationUnconfirmed') { 'Retained' } else { 'AcquireRelease' }
        $report.Safety.SourceCacheMutation = if ($executorResult.FailureCode -eq 'ExecutorTerminationUnconfirmed' -or $executorResult.TimedOut) { 'ExecutorMayHaveChanged' } else { 'ExecutorOnly' }
        $report.Evidence.TerminationConfirmed = $executorResult.Termination -ne 'Unconfirmed'
    }
    else {
        $sourceResultPath = Join-Path $reportsRoot 'source-refresh-result.json'
        try {
            if (-not (Test-Json -Path $sourceResultPath -SchemaFile $sourceResultSchemaPath -ErrorAction Stop)) { throw 'Source result schema invalid.' }
            $sourceResult = Get-Content -LiteralPath $sourceResultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (([datetimeoffset]$sourceResult.EvaluationTimeUtc).ToUniversalTime() -ne $EvaluationTimeUtc.ToUniversalTime()) { throw 'Source result evaluation mismatch.' }
            $report.InputResultSchemaVersion = [string]$sourceResult.SchemaVersion
            $report.InputResultDigest = Get-FileSha256 -Path $sourceResultPath
            $rows = @($sourceResult.Sources)
            $counts = New-Counts
            $counts.SourceCount = $rows.Count
            $counts.AttemptedCount = @($rows | Where-Object Attempted).Count
            $counts.CacheChangedCount = @($rows | Where-Object CacheChanged).Count
            $counts.LastKnownGoodPreservedCount = @($rows | Where-Object LastKnownGoodPreserved).Count
            foreach ($row in $rows) { $counts[[string]$row.Classification] = [int]$counts[[string]$row.Classification] + 1 }
            $report.Counts = $counts
            $report.Status = if ($counts.ReviewNeeded -gt 0 -or $counts.Degraded -gt 0) { 'DEGRADED' } else { 'SUCCEEDED' }
            $report.NotificationDecision = Get-NotificationDecision -Status $report.Status -ReviewNeededCount $counts.ReviewNeeded -DegradedCount $counts.Degraded
            $report.MutationScope = 'DisposableSourceCacheOnly'
            $report.Safety.LockMutation = 'AcquireRelease'
            $report.Safety.SourceCacheMutation = 'ExecutorOnly'
            $report.Evidence.ExecutorResultValidated = $true
            $report.Evidence.TerminationConfirmed = $true
        }
        catch {
            $report.Status = 'FAILED'
            $report.FailureCode = if (-not (Test-Path -LiteralPath $sourceResultPath -PathType Leaf)) { 'ExecutorResultMissing' } elseif ($_.Exception.Message -match 'evaluation') { 'ExecutorResultEvaluationMismatch' } elseif ($_.Exception.Message -match 'schema') { 'ExecutorResultSchemaInvalid' } else { 'ExecutorResultJsonInvalid' }
            $report.MutationScope = 'DisposableSourceCacheOnly'
            $report.Safety.LockMutation = 'AcquireRelease'
            $report.Safety.SourceCacheMutation = 'ExecutorMayHaveChanged'
            $report.NotificationDecision = Get-NotificationDecision -Status 'FAILED' -ReviewNeededCount 0 -DegradedCount 0
        }
    }
    if ($executorResult.FailureCode -eq 'ExecutorTerminationUnconfirmed') {
        $lockMetadata.State = 'TerminationUnconfirmed'
        Write-LockMetadata -Lease $lease -Metadata $lockMetadata
        $report.LockEvidence.ReleaseResult = 'Retained'
        $report.FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow)
        Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath
        [pscustomobject]$report
        return
    }

    $lockMetadata.State = if ($report.Status -eq 'TIMED_OUT') { 'TimedOut' } else { 'Completed' }
    Write-LockMetadata -Lease $lease -Metadata $lockMetadata
    $lease.Dispose(); $lease = $null
    $report.LockEvidence.ReleaseResult = 'Released'
    $report.FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow)
    Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath
    [pscustomobject]$report
}
catch {
    if ($null -ne $lease) {
        try { $lockMetadata.State = 'TerminationUnconfirmed'; Write-LockMetadata -Lease $lease -Metadata $lockMetadata } catch { }
        try { $lease.Dispose() } catch { }
    }
    $report.Status = 'FAILED'
    if ($report.FailureCode -eq 'None') { $report.FailureCode = 'InternalError' }
    $report.FinishedAtUtc = Get-UtcText -Value ([datetimeoffset]::UtcNow)
    $report.NotificationDecision = Get-NotificationDecision -Status 'FAILED' -ReviewNeededCount 0 -DegradedCount 0
    try { Write-RunReports -Report $report -ReportRoot $reportsRoot -SchemaPath $runSchemaPath } catch { }
    [pscustomobject]$report
}
