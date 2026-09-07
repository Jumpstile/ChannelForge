BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Wrapper = Join-Path $script:Root 'scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1'
    $script:PolicyExample = Join-Path $script:Root 'config/scheduled-refresh.example.json'
    $script:PlanScript = Join-Path $script:Root 'scripts/Get-ChannelForgeScheduledRefreshPlan.ps1'
    $script:PlanSchema = Join-Path $script:Root 'schemas/scheduled-refresh-plan.schema.json'
    $script:ResultSchema = Join-Path $script:Root 'schemas/source-refresh-result.schema.json'
$script:PolicySchema = Join-Path $script:Root 'schemas/scheduled-refresh-policy.schema.json'
    $script:RunSchema = Join-Path $script:Root 'schemas/scheduled-refresh-run.schema.json'
    $script:LockSchema = Join-Path $script:Root 'schemas/scheduled-refresh-lock.schema.json'
    $script:RegistrationSchema = Join-Path $script:Root 'schemas/scheduled-refresh-registration.schema.json'
    $script:HistorySchema = Join-Path $script:Root 'schemas/scheduled-refresh-history.schema.json'
    $script:LockInitializer = Join-Path $script:Root 'src/ChannelForge/Private/Initialize-ChannelForgeGenerationStore.ps1'
    $script:ProcessJobInitializer = Join-Path $script:Root 'src/ChannelForge/Private/Initialize-ChannelForgeProcessJob.ps1'
    $script:ScheduledOperationHelper = Join-Path $script:Root 'src/ChannelForge/Private/Initialize-ChannelForgeScheduledOperation.ps1'
    . $script:ScheduledOperationHelper
    function Write-TestJson {
        param([Parameter(Mandatory)][object]$Value, [Parameter(Mandatory)][string]$Path)
        [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    }

    function New-TestSourceResult {
        param([object[]]$Rows = @())
        [ordered]@{
            SchemaVersion = 'source-refresh-result/v2'
            EvaluationTimeUtc = '2026-01-01T03:00:00.0000000+00:00'
            ReviewNeeded = @($Rows | Where-Object Classification -eq 'ReviewNeeded').Count -gt 0
            ReviewNeededCount = @($Rows | Where-Object Classification -eq 'ReviewNeeded').Count
            Sources = @($Rows)
        }
    }

    function New-TestSourceRow {
        param([Parameter(Mandatory)][ValidateSet('AutoHandled', 'Degraded', 'ReviewNeeded', 'NoAction')][string]$Classification)
        $result = switch ($Classification) {
            'AutoHandled' { 'REUSED_VALID_CACHE' }
            'Degraded' { 'REFRESH_FAILED' }
            'ReviewNeeded' { 'REVIEW_REQUIRED' }
            default { 'NOT_APPLICABLE' }
        }
        [ordered]@{
            SourceId = 'fixture-source'
            Name = 'Fixture Source'
            Kind = 'remote'
            PlannedAction = 'USE_VALID_CACHE'
            Attempted = $Classification -ne 'NoAction'
            Result = $result
            Classification = $Classification
            ReasonCode = switch ($Classification) {
                'AutoHandled' { 'ReusedValidCache' }
                'Degraded' { 'RefreshFailedLkgPreserved' }
                'ReviewNeeded' { 'RefreshFailedNoLkg' }
                default { 'DisabledSource' }
            }
            CacheChanged = $false
            LastKnownGoodPreserved = $Classification -eq 'Degraded'
            ValidatorOutcome = 'NONE'
            SafeReason = 'Fixture result contains no private source details.'
        }
    }

    function New-TestProject {
        param([ValidateSet('success', 'degraded', 'review', 'failed', 'timeout')][string]$Mode = 'success')
        $projectRoot = Join-Path $TestDrive ('scheduled-run-' + [guid]::NewGuid().ToString('N'))
        $directories = @(
            'config', 'data/providers', 'data/epg', 'output/reports', 'output/cache',
            'scripts', 'schemas', 'src/ChannelForge/Private'
        ) | ForEach-Object { Join-Path $projectRoot $_ }
        New-Item -ItemType Directory -Force -Path $directories | Out-Null
        Copy-Item -LiteralPath $script:PolicyExample -Destination (Join-Path $projectRoot 'config/scheduled-refresh.example.json')
        Copy-Item -LiteralPath $script:PlanScript -Destination (Join-Path $projectRoot 'scripts/Get-ChannelForgeScheduledRefreshPlan.ps1')
        Copy-Item -LiteralPath $script:PlanSchema -Destination (Join-Path $projectRoot 'schemas/scheduled-refresh-plan.schema.json')
        Copy-Item -LiteralPath $script:ResultSchema -Destination (Join-Path $projectRoot 'schemas/source-refresh-result.schema.json')
        Copy-Item -LiteralPath $script:PolicySchema -Destination (Join-Path $projectRoot 'schemas/scheduled-refresh-policy.schema.json')
        Copy-Item -LiteralPath $script:RunSchema -Destination (Join-Path $projectRoot 'schemas/scheduled-refresh-run.schema.json')
        Copy-Item -LiteralPath $script:LockSchema -Destination (Join-Path $projectRoot 'schemas/scheduled-refresh-lock.schema.json')
        Copy-Item -LiteralPath $script:LockInitializer -Destination (Join-Path $projectRoot 'src/ChannelForge/Private/Initialize-ChannelForgeGenerationStore.ps1')
        Copy-Item -LiteralPath $script:RegistrationSchema -Destination (Join-Path $projectRoot 'schemas/scheduled-refresh-registration.schema.json')
        Copy-Item -LiteralPath $script:HistorySchema -Destination (Join-Path $projectRoot 'schemas/scheduled-refresh-history.schema.json')
        Copy-Item -LiteralPath $script:ScheduledOperationHelper -Destination (Join-Path $projectRoot 'src/ChannelForge/Private/Initialize-ChannelForgeScheduledOperation.ps1')
        Copy-Item -LiteralPath $script:ProcessJobInitializer -Destination (Join-Path $projectRoot 'src/ChannelForge/Private/Initialize-ChannelForgeProcessJob.ps1')
        Set-Content -LiteralPath (Join-Path $projectRoot 'data/providers/provider.example.json') -Value '{"provider":"fixture","sources":[]}' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $projectRoot 'data/epg/epg_sources.example.json') -Value '{"epg_sources":[]}' -Encoding utf8
        Write-TestJson -Value (New-TestSourceResult) -Path (Join-Path $projectRoot 'output/reports/source-refresh-result.json')

        $fakeExecutor = @"
[CmdletBinding()]
param(
    [string]`$Root,
    [string]`$ProviderConfigPath,
    [string]`$EpgConfigPath,
    [string]`$CacheRoot,
    [datetimeoffset]`$EvaluationTimeUtc,
    [string]`$OutputRoot
)
`$ErrorActionPreference = 'Stop'
Add-Content -LiteralPath (Join-Path `$Root 'executor.calls') -Value 'called'
if ('$Mode' -eq 'timeout') { Start-Sleep -Seconds 60; exit 0 }
if ('$Mode' -eq 'failed') { exit 7 }
`$classification = switch ('$Mode') {
    'degraded' { 'Degraded' }
    'review' { 'ReviewNeeded' }
    default { 'AutoHandled' }
}
`$row = [ordered]@{
    SourceId = 'fixture-source'
    Name = 'Fixture Source'
    Kind = 'remote'
    PlannedAction = 'USE_VALID_CACHE'
    Attempted = `$false
    Result = if (`$classification -eq 'AutoHandled') { 'REUSED_VALID_CACHE' } elseif (`$classification -eq 'Degraded') { 'REFRESH_FAILED' } else { 'REVIEW_REQUIRED' }
    Classification = `$classification
    ReasonCode = if (`$classification -eq 'AutoHandled') { 'ReusedValidCache' } elseif (`$classification -eq 'Degraded') { 'RefreshFailedLkgPreserved' } else { 'RefreshFailedNoLkg' }
    CacheChanged = `$false
    LastKnownGoodPreserved = `$classification -eq 'Degraded'
    ValidatorOutcome = 'NONE'
    SafeReason = 'Fixture result contains no private source details.'
}
`$report = [ordered]@{
    SchemaVersion = 'source-refresh-result/v2'
    EvaluationTimeUtc = `$EvaluationTimeUtc.ToUniversalTime().ToString('o')
    ReviewNeeded = `$classification -eq 'ReviewNeeded'
    ReviewNeededCount = if (`$classification -eq 'ReviewNeeded') { 1 } else { 0 }
    Sources = @(`$row)
}
New-Item -ItemType Directory -Force -Path `$OutputRoot | Out-Null
[IO.File]::WriteAllText((Join-Path `$OutputRoot 'source-refresh-result.json'), ((`$report | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new(`$false))
[IO.File]::WriteAllText((Join-Path `$OutputRoot 'source-refresh-result.md'), '# Fixture source result' + [Environment]::NewLine, [Text.UTF8Encoding]::new(`$false))
"@
        [IO.File]::WriteAllText((Join-Path $projectRoot 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'), $fakeExecutor, [Text.UTF8Encoding]::new($false))
        [pscustomobject]@{ Root = $projectRoot; Calls = Join-Path $projectRoot 'executor.calls'; Lock = Join-Path $projectRoot 'output/operations/scheduled-refresh.lock' }
    }

    function Invoke-TestWrapper {
        param([Parameter(Mandatory)][psobject]$Project, [int]$TimeoutSeconds = 10)
        $result = @(& $script:Wrapper -Root $Project.Root -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T03:00:00Z') -TimeoutSeconds $TimeoutSeconds)
        $result
    }

    function Read-TestReport {
        param([Parameter(Mandatory)][psobject]$Project)
        Get-Content -LiteralPath (Join-Path $Project.Root 'output/reports/scheduled-refresh-run.json') -Raw | ConvertFrom-Json
    }
    function Invoke-TestScheduledWrapper {
        param([Parameter(Mandatory)][psobject]$Project)
        $policy = Get-Content -LiteralPath (Join-Path $Project.Root 'config/scheduled-refresh.example.json') -Raw | ConvertFrom-Json
        $policy.Enabled = $true
        $policy.JitterMinutes = 0
        Write-TestJson -Value $policy -Path (Join-Path $Project.Root 'config/scheduled-refresh.local.json')
        $rootInfo = Resolve-ChannelForgeScheduledOperationRoot -Root $Project.Root
        $policyInfo = Get-ChannelForgeScheduledOperationPolicyInfo -Path (Join-Path $Project.Root 'config/scheduled-refresh.local.json') -SchemaPath (Join-Path $Project.Root 'schemas/scheduled-refresh-policy.schema.json')
        $identity = Get-ChannelForgeScheduledOperationTaskIdentity -RootInfo $rootInfo
        $registration = [ordered]@{
            SchemaVersion = 'scheduled-refresh-registration/v1'
            Owner = 'ChannelForge'
            TaskPath = '\ChannelForge\'
            TaskName = $identity.TaskName
            RootDigest = $identity.RootDigest
            PolicyDigest = $policyInfo.Digest
            TaskDefinitionDigest = ('0' * 64)
            RegisteredAtUtc = '2026-01-01T00:00:00.0000000Z'
            TriggerKind = 'Scheduled'
            CadenceMode = 'Daily'
            CadenceAtUtc = '03:00'
            StartBoundaryUtc = '2026-01-01T03:00:00.0000000Z'
            ExecutionTimeLimitMinutes = 31
            RuntimeVersion = $PSVersionTable.PSVersion.ToString()
            RuntimeContract = 'PowerShell Core 7.6 or newer'
            WrapperContract = 'scheduled-refresh-wrapper/v1'
            ReadyForFirstRun = $true
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $Project.Root 'output/operations') | Out-Null
        Write-TestJson -Value $registration -Path (Join-Path $Project.Root 'output/operations/scheduled-refresh-registration.json')
        @(& $script:Wrapper -Root $Project.Root -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T03:00:00Z') -ScheduledInvocation)
    }
}

Describe 'manual scheduled refresh run wrapper' {
    It 'calls the existing source executor exactly once for an eligible manual plan' {
        $project = New-TestProject -Mode success
        $result = Invoke-TestWrapper -Project $project
        $result.Status | Should -Be 'SUCCEEDED'
        (Get-Content -LiteralPath $project.Calls).Count | Should -Be 1
        $result.ExecutorInvocationCount | Should -Be 1
        $result.TriggerKind | Should -Be 'Manual'
        $result.PlanDecision | Should -Be 'READY_MANUAL'
        $result.LockEvidence.Path | Should -Be 'output/operations/scheduled-refresh.lock'
        Test-Path -LiteralPath (Join-Path $project.Root 'state/lineup-operation.lock') | Should -BeFalse
        Test-Json -Path (Join-Path $project.Root 'output/reports/scheduled-refresh-run.json') -SchemaFile $script:RunSchema | Should -BeTrue
    }

    It 'does not call the executor for an ineligible plan' {
        $project = New-TestProject -Mode success
        $policyPath = Join-Path $project.Root 'config/scheduled-refresh.example.json'
        $policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
        $policy.ManualOverride.Allowed = $false
        Write-TestJson -Value $policy -Path $policyPath
        $result = Invoke-TestWrapper -Project $project
        $result.Status | Should -Be 'BLOCKED'
        $result.FailureCode | Should -Be 'PlanNotEligible'
        Test-Path -LiteralPath $project.Calls | Should -BeFalse
    }

    It 'does not call the executor for invalid plan input' {
        $project = New-TestProject -Mode success
        Set-Content -LiteralPath (Join-Path $project.Root 'output/reports/source-refresh-result.json') -Value '{}' -Encoding utf8
        $result = Invoke-TestWrapper -Project $project
        $result.Status | Should -Be 'BLOCKED'
        $result.FailureCode | Should -Be 'PlanInputInvalid'
        Test-Path -LiteralPath $project.Calls | Should -BeFalse
    }

    It 'fails closed on lock contention without deleting the marker or calling the executor' {
        $project = New-TestProject -Mode success
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $project.Lock) | Out-Null
        . $script:LockInitializer
        $null = Initialize-ChannelForgeGenerationStore
        $heldLease = [ChannelForge.GenerationStore]::AcquireLock($project.Lock)
        try {
            $marker = [ordered]@{
                SchemaVersion = 'scheduled-refresh-lock/v1'
                RunId = '0123456789abcdef0123456789abcdef'
                ScheduleSlotId = 'manual-fixture'
                TriggerKind = 'Manual'
                State = 'Running'
                OwnerTokenHash = ('a' * 64)
                ProcessId = 1
                ProcessStartUtc = '2026-01-01T00:00:00.0000000+00:00'
                StartedAtUtc = '2026-01-01T00:00:00.0000000+00:00'
                HeartbeatAtUtc = '2026-01-01T00:00:00.0000000+00:00'
                PlanDigest = $null
                ExecutorStarted = $false
                ExecutorInvocationCount = 0
            }
            $heldLease.WriteMetadata(([Text.Encoding]::UTF8.GetBytes((($marker | ConvertTo-Json -Depth 10) + [Environment]::NewLine))))
            $before = [Text.Encoding]::UTF8.GetString($heldLease.ReadMetadata())
            $result = Invoke-TestWrapper -Project $project
            $result.Status | Should -Be 'BLOCKED'
            $result.FailureCode | Should -Be 'LockBusy'
            Test-Path -LiteralPath $project.Calls | Should -BeFalse
            $after = [Text.Encoding]::UTF8.GetString($heldLease.ReadMetadata())
            $after | Should -Be $before
        }
        finally {
            $heldLease.Dispose()
        }
    }

    It 'records a prior running marker as abandoned only after acquiring the real lock' {
        $project = New-TestProject -Mode success
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $project.Lock) | Out-Null
        $marker = [ordered]@{
            SchemaVersion = 'scheduled-refresh-lock/v1'
            RunId = 'fedcba9876543210fedcba9876543210'
            ScheduleSlotId = 'manual-prior'
            TriggerKind = 'Manual'
            State = 'Running'
            OwnerTokenHash = ('b' * 64)
            ProcessId = 999999
            ProcessStartUtc = '2026-01-01T00:00:00.0000000+00:00'
            StartedAtUtc = '2026-01-01T00:00:00.0000000+00:00'
            HeartbeatAtUtc = '2026-01-01T00:00:00.0000000+00:00'
            PlanDigest = $null
            ExecutorStarted = $true
            ExecutorInvocationCount = 1
        }
        Write-TestJson -Value $marker -Path $project.Lock
        $result = Invoke-TestWrapper -Project $project
        $result.Status | Should -Be 'SUCCEEDED'
        $result.LockEvidence.PriorRunStatus | Should -Be 'Abandoned'
        $result.Evidence.PriorRunAbandoned | Should -BeTrue
        (Get-Content -LiteralPath $project.Calls).Count | Should -Be 1
    }

    It 'maps degraded source rows to DEGRADED without a separate review status' {
        $project = New-TestProject -Mode degraded
        $result = Invoke-TestWrapper -Project $project
        $result.Status | Should -Be 'DEGRADED'
        $result.NotificationDecision.Level | Should -Be 'Warning'
        $result.Status | Should -Not -Be 'ReviewNeeded'
    }

    It 'maps review-needed source rows to DEGRADED and raises attention' {
        $project = New-TestProject -Mode review
        $result = Invoke-TestWrapper -Project $project
        $result.Status | Should -Be 'DEGRADED'
        $result.NotificationDecision.Level | Should -Be 'Interrupt'
        $result.Counts.ReviewNeeded | Should -Be 1
    }

    It 'maps only auto-handled or no-action rows to SUCCEEDED' {
        $project = New-TestProject -Mode success
        $result = Invoke-TestWrapper -Project $project
        $result.Status | Should -Be 'SUCCEEDED'
        $result.Counts.AutoHandled | Should -Be 1
    }

    It 'maps executor failure to FAILED without retry' {
        $project = New-TestProject -Mode failed
        $result = Invoke-TestWrapper -Project $project
        $result.Status | Should -Be 'FAILED'
        $result.FailureCode | Should -Be 'ExecutorFailed'
        $result.ExecutorInvocationCount | Should -Be 1
        (Get-Content -LiteralPath $project.Calls).Count | Should -Be 1
    }

    It 'maps a bounded executor timeout to TIMED_OUT' {
        $project = New-TestProject -Mode timeout
        $result = Invoke-TestWrapper -Project $project -TimeoutSeconds 1
        $result.Status | Should -Be 'TIMED_OUT'
        $result.FailureCode | Should -Be 'ExecutorTimedOut'
        $result.ExecutorInvocationCount | Should -Be 1
        $result.ExecutorTermination | Should -Be 'Killed'
    }

    It 'writes deterministic safe reports and preserves mutation boundaries' {
        $project = New-TestProject -Mode success
        $result = Invoke-TestWrapper -Project $project
        $jsonPath = Join-Path $project.Root 'output/reports/scheduled-refresh-run.json'
        $markdownPath = Join-Path $project.Root 'output/reports/scheduled-refresh-run.md'
        Test-Json -Path $jsonPath -SchemaFile $script:RunSchema | Should -BeTrue
        $json = Get-Content -LiteralPath $jsonPath -Raw
        $markdown = Get-Content -LiteralPath $markdownPath -Raw
        "$json`n$markdown" | Should -Not -Match 'https?://|ftp://|ACCOUNT_ID|API_TOKEN|PASSWORD|SECRET|ETag|Last-Modified|[A-Za-z]:\\|\\\\'
        $result.Safety.AcceptedStateMutation | Should -Be 'None'
        $result.Safety.GenerationMutation | Should -Be 'None'
        $result.Safety.PointerMutation | Should -Be 'None'
        $result.Safety.PublishedOutputMutation | Should -Be 'None'
        $result.Safety.ProviderStateMutation | Should -Be 'None'
        $result.Safety.IdentityEvidenceMutation | Should -Be 'None'
        $result.Safety.WrapperNetworkCalls | Should -Be 0
        Test-Path -LiteralPath (Join-Path $project.Root 'output/accepted') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $project.Root 'output/generations') | Should -BeFalse
        $json.TrimStart() | Should -Match '^\{\r?\n  "SchemaVersion"'
    }
}

Describe 'scheduler-owned scheduled refresh run mode' {
    It 'passes Scheduled trigger ownership to the planner and writes bounded history' {
        $project = New-TestProject -Mode success
        $result = Invoke-TestScheduledWrapper -Project $project
        $result.TriggerKind | Should -Be 'Scheduled'
        $result.PlanDecision | Should -Be 'READY_SCHEDULED'
        $result.ExecutorInvocationCount | Should -Be 1
        $result.Evidence.HistoryWritten | Should -BeTrue
        $historyPath = Join-Path $project.Root 'output/operations/scheduled-refresh-history.json'
        Test-Json -Path $historyPath -SchemaFile $script:HistorySchema | Should -BeTrue
        $history = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json
        $history.Runs.Count | Should -Be 1
        $history.Runs[0].TriggerKind | Should -Be 'Scheduled'
        (Get-Content -LiteralPath $historyPath -Raw) | Should -Not -Match 'https?://|[A-Za-z]:\\|\\\\|PASSWORD|TOKEN|ETag|Last-Modified'
    }

    It 'blocks scheduled invocation when registration policy evidence is stale' {
        $project = New-TestProject -Mode success
        $null = Invoke-TestScheduledWrapper -Project $project
        $registrationPath = Join-Path $project.Root 'output/operations/scheduled-refresh-registration.json'
        $registration = Get-Content -LiteralPath $registrationPath -Raw | ConvertFrom-Json
        $registration.PolicyDigest = ('f' * 64)
        Write-TestJson -Value $registration -Path $registrationPath
        $result = @(& $script:Wrapper -Root $project.Root -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T03:00:00Z') -ScheduledInvocation)
        $result[-1].Status | Should -Be 'BLOCKED'
        $result[-1].FailureCode | Should -Be 'ScheduledRegistrationMismatch'
        Test-Path -LiteralPath $project.Calls | Should -BeTrue
        (Get-Content -LiteralPath $project.Calls).Count | Should -Be 1
    }
}
