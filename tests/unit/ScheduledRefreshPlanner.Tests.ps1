BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Planner = Join-Path $script:Root 'scripts/Get-ChannelForgeScheduledRefreshPlan.ps1'
    $script:PolicySchema = Join-Path $script:Root 'schemas/scheduled-refresh-policy.schema.json'
    $script:PlanSchema = Join-Path $script:Root 'schemas/scheduled-refresh-plan.schema.json'
    $script:ResultSchema = Join-Path $script:Root 'schemas/source-refresh-result.schema.json'

    function New-SourceRow {
        param(
            [string]$SourceId = 'm3u-source',
            [string]$Classification = 'AutoHandled',
            [string]$ReasonCode = 'ReusedValidCache',
            [string]$Name = 'Fixture Source'
        )
        [ordered]@{
            SourceId = $SourceId
            Name = $Name
            Kind = 'remote'
            PlannedAction = 'USE_VALID_CACHE'
            Attempted = $false
            Result = 'REUSED_VALID_CACHE'
            Classification = $Classification
            ReasonCode = $ReasonCode
            CacheChanged = $false
            LastKnownGoodPreserved = $false
            ValidatorOutcome = 'ETAG'
            SafeReason = 'Validated source evidence.'
        }
    }

    function New-SourceResult {
        param(
            [object[]]$Rows = @((New-SourceRow)),
            [object]$ReviewNeededOverride = $null,
            [object]$ReviewNeededCountOverride = $null,
            [string]$SchemaVersion = 'source-refresh-result/v2'
        )
        $reviewCount = @($Rows | Where-Object { $_.Classification -eq 'ReviewNeeded' }).Count
        [ordered]@{
            SchemaVersion = $SchemaVersion
            EvaluationTimeUtc = '2026-01-01T00:00:00.0000000Z'
            ReviewNeeded = if ($null -eq $ReviewNeededOverride) { $reviewCount -gt 0 } else { $ReviewNeededOverride }
            ReviewNeededCount = if ($null -eq $ReviewNeededCountOverride) { $reviewCount } else { $ReviewNeededCountOverride }
            Sources = @($Rows)
        }
    }

    function New-Policy {
        param(
            [bool]$Enabled = $false,
            [string]$At = '03:00',
            [string]$WindowStart = '02:00',
            [string]$WindowEnd = '05:00',
            [int]$JitterMinutes = 0
        )
        [ordered]@{
            SchemaVersion = 'scheduled-refresh-policy/v1'
            Enabled = $Enabled
            TimeZoneId = 'UTC'
            Cadence = [ordered]@{ Mode = 'Daily'; At = $At }
            AllowedWindow = [ordered]@{ Start = $WindowStart; End = $WindowEnd }
            JitterMinutes = $JitterMinutes
            MaxRunDurationMinutes = 30
            StaleRunThresholdMinutes = 10
            HeartbeatIntervalSeconds = 30
            Retry = [ordered]@{ MaxAttemptsPerScheduleSlot = 1 }
            ManualOverride = [ordered]@{
                Allowed = $true
                AllowedWhenDisabled = $true
                BypassAllowedWindow = $true
                CountsTowardScheduledCadence = $false
            }
            Notification = [ordered]@{
                DegradedWarningAfterConsecutiveRuns = 2
                RepeatedFailureEscalationAfterConsecutiveRuns = 3
                SuppressDuplicateIssueUntilFingerprintChanges = $true
            }
            Retention = [ordered]@{ MaxRunRecords = 30; MaxAgeDays = 90 }
        }
    }

    function Save-Json {
        param([Parameter(Mandatory)][object]$Value, [Parameter(Mandatory)][string]$Path)
        $parent = Split-Path -Parent $Path
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
    }

    function Save-Inputs {
        param(
            [object[]]$Rows = @((New-SourceRow)),
            [object]$ReviewNeededOverride = $null,
            [object]$ReviewNeededCountOverride = $null,
            [string]$SchemaVersion = 'source-refresh-result/v2'
        )
        Save-Json -Value $script:Policy -Path $script:PolicyPath
        Save-Json -Value (New-SourceResult -Rows $Rows -ReviewNeededOverride $ReviewNeededOverride -ReviewNeededCountOverride $ReviewNeededCountOverride -SchemaVersion $SchemaVersion) -Path $script:ResultPath
    }

    function Save-History {
        param([object[]]$Runs)
        Save-Json -Value ([ordered]@{ SchemaVersion = 'scheduled-refresh-history/v1'; Runs = @($Runs) }) -Path $script:HistoryPath
    }

    function Invoke-Planner {
        param(
            [ValidateSet('Scheduled', 'Manual')][string]$TriggerKind = 'Scheduled',
            [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]'2026-01-01T03:00:00Z'),
            [string]$ObservedLockState = 'NotAttempted',
            [switch]$UseHistory,
            [switch]$UseDefaultPaths
        )
        $parameters = @{
            Root = $script:Project
            EvaluationTimeUtc = $EvaluationTimeUtc
            TriggerKind = $TriggerKind
            ObservedLockState = $ObservedLockState
        }
        if (-not $UseDefaultPaths) {
            $parameters.PolicyPath = $script:PolicyPath
            $parameters.SourceRefreshResultPath = $script:ResultPath
            $parameters.OutputRoot = $script:OutputRoot
        }
        if ($UseHistory) { $parameters.NotificationHistoryPath = $script:HistoryPath }
        & $script:Planner @parameters | Out-Null
        Get-Content -LiteralPath (Join-Path $script:OutputRoot 'scheduled-refresh-plan.json') -Raw | ConvertFrom-Json
    }

    function Assert-PlanSchema {
        $path = Join-Path $script:OutputRoot 'scheduled-refresh-plan.json'
        Test-Json -Path $path -SchemaFile $script:PlanSchema | Should -BeTrue
    }
}

Describe 'scheduled refresh policy and plan schemas' {
    It 'accepts the tracked policy example' {
        Test-Json -Path (Join-Path $script:Root 'config/scheduled-refresh.example.json') -SchemaFile $script:PolicySchema | Should -BeTrue
    }

    It 'rejects an overnight policy window' {
        $script:Project = Join-Path $TestDrive 'overnight'
        $script:PolicyPath = Join-Path $script:Project 'config/scheduled-refresh.local.json'
        $script:ResultPath = Join-Path $script:Project 'output/reports/source-refresh-result.json'
        $script:OutputRoot = Join-Path $script:Project 'output/reports'
        $script:Policy = New-Policy -Enabled $true -WindowStart '22:00' -WindowEnd '02:00'
        Save-Inputs
        { Invoke-Planner } | Should -Throw '*OvernightWindowRejected*'
    }
}

Describe 'report-only scheduled refresh planner' {
    BeforeEach {
        $script:Project = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:PolicyPath = Join-Path $script:Project 'config/scheduled-refresh.local.json'
        $script:HistoryPath = Join-Path $script:Project 'output/reports/history.json'
        $script:ResultPath = Join-Path $script:Project 'output/reports/source-refresh-result.json'
        $script:OutputRoot = Join-Path $script:Project 'output/reports'
        $script:Policy = New-Policy
        New-Item -ItemType Directory -Force -Path $script:OutputRoot | Out-Null
    }

    It 'maps all v2 classifications and derives counts' {
        $rows = @(
            (New-SourceRow -SourceId 'm3u-auto' -Classification 'AutoHandled' -ReasonCode 'ReusedValidCache'),
            (New-SourceRow -SourceId 'm3u-degraded' -Classification 'Degraded' -ReasonCode 'RefreshFailedLkgPreserved'),
            (New-SourceRow -SourceId 'm3u-review' -Classification 'ReviewNeeded' -ReasonCode 'InvalidCache'),
            (New-SourceRow -SourceId 'm3u-none' -Classification 'NoAction' -ReasonCode 'DisabledSource')
        )
        Save-Inputs -Rows $rows
        $plan = Invoke-Planner
        Assert-PlanSchema
        $plan.Counts.AutoHandled | Should -Be 1
        $plan.Counts.Degraded | Should -Be 1
        $plan.Counts.ReviewNeeded | Should -Be 1
        $plan.Counts.NoAction | Should -Be 1
        $plan.Notification.Level | Should -Be 'Interrupt'
        (@($plan.Notification.Items | Where-Object Action -eq 'NotifyInterrupt')).Count | Should -Be 1
        (@($plan.Notification.Items | Where-Object Action -eq 'NoNotification')).Count | Should -Be 3
    }

    It 'uses the local policy path before the tracked example' {
        $script:Policy = New-Policy -Enabled $true
        Save-Inputs
        Save-Json -Value (New-Policy -Enabled $false) -Path (Join-Path $script:Project 'config/scheduled-refresh.example.json')
        $plan = Invoke-Planner -UseDefaultPaths -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T03:00:00Z')
        Test-Json -Path $script:ResultPath -SchemaFile $script:ResultSchema | Should -BeTrue
        Assert-PlanSchema
        $plan.PolicyEnabled | Should -BeTrue
    }

    It 'rejects an invalid v2 schema version and emits an interrupt plan' {
        Save-Inputs -SchemaVersion 'source-refresh-result/v9'
        { Invoke-Planner } | Should -Throw '*InvalidSourceRefreshResultSchemaVersion*'
        $plan = Get-Content (Join-Path $script:OutputRoot 'scheduled-refresh-plan.json') -Raw | ConvertFrom-Json
        Assert-PlanSchema
        $plan.InputValidation.Status | Should -Be 'Invalid'
        $plan.Notification.Level | Should -Be 'Interrupt'
        $plan.Schedule.Decision | Should -Be 'INPUT_INVALID'
    }

    It 'rejects missing required v2 fields' {
        Save-Json -Value $script:Policy -Path $script:PolicyPath
        Save-Json -Value ([ordered]@{
                SchemaVersion = 'source-refresh-result/v2'
                EvaluationTimeUtc = '2026-01-01T00:00:00Z'
                ReviewNeeded = $false
                ReviewNeededCount = 0
            }) -Path $script:ResultPath
        { Invoke-Planner } | Should -Throw '*MissingRequiredField*'
        Assert-PlanSchema
    }

    It 'rejects unknown Classification values' {
        Save-Inputs -Rows @((New-SourceRow -Classification 'Unknown' -ReasonCode 'InvalidCache'))
        { Invoke-Planner } | Should -Throw '*UnknownClassification*'
        Assert-PlanSchema
    }

    It 'rejects unknown ReasonCode values' {
        Save-Inputs -Rows @((New-SourceRow -Classification 'ReviewNeeded' -ReasonCode 'Unknown'))
        { Invoke-Planner } | Should -Throw '*UnknownReasonCode*'
        Assert-PlanSchema
    }

    It 'rejects ReviewNeeded boolean mismatches' {
        $row = New-SourceRow -Classification 'ReviewNeeded' -ReasonCode 'InvalidCache'
        Save-Inputs -Rows @($row) -ReviewNeededOverride $false -ReviewNeededCountOverride 1
        { Invoke-Planner } | Should -Throw '*ReviewNeededMismatch*'
        Assert-PlanSchema
    }

    It 'rejects ReviewNeededCount mismatches' {
        $row = New-SourceRow -Classification 'ReviewNeeded' -ReasonCode 'InvalidCache'
        Save-Inputs -Rows @($row) -ReviewNeededOverride $true -ReviewNeededCountOverride 0
        { Invoke-Planner } | Should -Throw '*ReviewNeededCountMismatch*'
        Assert-PlanSchema
    }

    It 'reports disabled scheduling without starting a run' {
        Save-Inputs
        $plan = Invoke-Planner
        Assert-PlanSchema
        $plan.Schedule.Decision | Should -Be 'DISABLED'
        $plan.Safety.MutationScope | Should -Be 'ReportOnly'
        $plan.Safety.AcceptedStateMutation | Should -Be 'None'
        $plan.Safety.GenerationMutation | Should -Be 'None'
        $plan.Safety.PointerMutation | Should -Be 'None'
        $plan.Safety.PublishedOutputMutation | Should -Be 'None'
        $plan.Safety.ProviderStateMutation | Should -Be 'None'
        $plan.Safety.IdentityEvidenceMutation | Should -Be 'None'
        $plan.LockObservation.Status | Should -Be 'NotAttempted'
        $markdown = Get-Content -LiteralPath (Join-Path $script:OutputRoot 'scheduled-refresh-plan.md') -Raw
        $markdown | Should -Match '- MutationScope: ReportOnly'
        $markdown | Should -Match '- IdentityEvidenceMutation: None'
        $markdown | Should -Not -Match '- Count:'
    }

    It 'reports an enabled daily slot at the cadence boundary' {
        $script:Policy = New-Policy -Enabled $true -JitterMinutes 0
        Save-Inputs
        $before = Invoke-Planner -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T02:59:59Z')
        $before.Schedule.Decision | Should -Be 'WAITING_FOR_CADENCE'
        $ready = Invoke-Planner -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T03:00:00Z')
        Assert-PlanSchema
        $ready.Schedule.Decision | Should -Be 'READY_SCHEDULED'
        $ready.Schedule.JitterOffsetMinutes | Should -Be 0
    }

    It 'enforces start-inclusive and end-exclusive window boundaries' {
        $script:Policy = New-Policy -Enabled $true -At '03:00' -WindowStart '03:00' -WindowEnd '04:00' -JitterMinutes 0
        Save-Inputs
        (Invoke-Planner -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T03:00:00Z')).Schedule.Decision | Should -Be 'READY_SCHEDULED'
        $end = Invoke-Planner -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T04:00:00Z')
        $end.Schedule.Decision | Should -Be 'WAITING_FOR_WINDOW'
    }

    It 'defers when deterministic jitter falls outside the allowed window' {
        $script:Policy = New-Policy -Enabled $true -At '00:00' -WindowStart '23:00' -WindowEnd '23:30' -JitterMinutes 30
        Save-Inputs
        $plan = Invoke-Planner -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T00:00:00Z')
        Assert-PlanSchema
        $plan.Schedule.Decision | Should -Be 'WAITING_FOR_WINDOW'
        $plan.Schedule.ReasonCode | Should -Be 'JitterOutsideWindow'
    }

    It 'produces the same deterministic jitter for equivalent inputs' {
        $script:Policy = New-Policy -Enabled $true -JitterMinutes 30
        Save-Inputs
        $first = Invoke-Planner -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T03:00:00Z') | ConvertTo-Json -Depth 20
        $firstBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:OutputRoot 'scheduled-refresh-plan.json')))
        $second = Invoke-Planner -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T03:00:00Z') | ConvertTo-Json -Depth 20
        $secondBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:OutputRoot 'scheduled-refresh-plan.json')))
        $first | Should -Be $second
        $firstBytes | Should -Be $secondBytes
    }

    It 'allows a manual plan while disabled and outside the scheduled window' {
        Save-Inputs
        $plan = Invoke-Planner -TriggerKind Manual -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T12:00:00Z')
        Assert-PlanSchema
        $plan.Schedule.Decision | Should -Be 'READY_MANUAL'
        $plan.Schedule.ReasonCode | Should -Be 'ManualOverrideReady'
    }

    It 'does not increment scheduled counters for manual plans' {
        $script:Policy = New-Policy -Enabled $true
        Save-Inputs -Rows @((New-SourceRow -SourceId 'm3u-degraded' -Classification 'Degraded' -ReasonCode 'RefreshFailedLkgPreserved'))
        Save-History -Runs @(
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-degraded'; Classification = 'Degraded'; ReasonCode = 'RefreshFailedLkgPreserved' }) },
            [ordered]@{ TriggerKind = 'Manual'; Sources = @([ordered]@{ SourceId = 'm3u-degraded'; Classification = 'Degraded'; ReasonCode = 'RefreshFailedLkgPreserved' }) }
        )
        $manual = Invoke-Planner -TriggerKind Manual -UseHistory
        $item = @($manual.Notification.Items)[0]
        $item.ConsecutiveScheduledFailureCount | Should -Be 1
        $item.Action | Should -Be 'NoNotification'
        $scheduled = Invoke-Planner -TriggerKind Scheduled -UseHistory
        $scheduledItem = @($scheduled.Notification.Items)[0]
        $scheduledItem.ConsecutiveScheduledFailureCount | Should -Be 2
        $scheduled.Notification.Level | Should -Be 'Warning'
    }

    It 'warns and escalates repeated degraded failures' {
        $script:Policy = New-Policy -Enabled $true
        $row = New-SourceRow -SourceId 'm3u-degraded' -Classification 'Degraded' -ReasonCode 'RefreshFailedLkgPreserved'
        Save-Inputs -Rows @($row)
        Save-History -Runs @(
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-degraded'; Classification = 'Degraded'; ReasonCode = 'RefreshFailedLkgPreserved' }) }
        )
        $warning = Invoke-Planner -UseHistory
        $warning.Notification.Level | Should -Be 'Warning'
        $warning.Notification.SummaryCode | Should -Be 'DegradedWarning'
        Save-History -Runs @(
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-degraded'; Classification = 'Degraded'; ReasonCode = 'RefreshFailedLkgPreserved' }) },
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-degraded'; Classification = 'Degraded'; ReasonCode = 'RefreshFailedLkgPreserved' }) }
        )
        $escalated = Invoke-Planner -UseHistory
        $escalated.Notification.Level | Should -Be 'EscalatedInterrupt'
        $escalated.Notification.SummaryCode | Should -Be 'DegradedEscalated'
    }

    It 'uses mixed severity precedence across notification items' {
        $script:Policy = New-Policy -Enabled $true
        $rows = @(
            (New-SourceRow -SourceId 'm3u-degraded' -Classification 'Degraded' -ReasonCode 'RefreshFailedLkgPreserved'),
            (New-SourceRow -SourceId 'm3u-review' -Classification 'ReviewNeeded' -ReasonCode 'InvalidCache')
        )
        Save-Inputs -Rows $rows
        Save-History -Runs @(
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-degraded'; Classification = 'Degraded'; ReasonCode = 'RefreshFailedLkgPreserved' }) },
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-degraded'; Classification = 'Degraded'; ReasonCode = 'RefreshFailedLkgPreserved' }) }
        )
        $plan = Invoke-Planner -UseHistory
        $plan.Notification.Level | Should -Be 'EscalatedInterrupt'
        (@($plan.Notification.Items | Where-Object SourceId -eq 'm3u-degraded')).Action | Should -Be 'EscalateInterrupt'
        (@($plan.Notification.Items | Where-Object SourceId -eq 'm3u-review')).Action | Should -Be 'NotifyInterrupt'
    }

    It 'interrupts new ReviewNeeded and keeps unchanged duplicates active' {
        $script:Policy = New-Policy -Enabled $true
        $row = New-SourceRow -SourceId 'm3u-review' -Classification 'ReviewNeeded' -ReasonCode 'InvalidCache'
        Save-Inputs -Rows @($row)
        $new = Invoke-Planner
        $new.Notification.Level | Should -Be 'Interrupt'
        (@($new.Notification.Items)[0]).Action | Should -Be 'NotifyInterrupt'
        Save-History -Runs @(
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-review'; Classification = 'ReviewNeeded'; ReasonCode = 'InvalidCache' }) }
        )
        $duplicate = Invoke-Planner -UseHistory
        $duplicate.Notification.Level | Should -Be 'Interrupt'
        (@($duplicate.Notification.Items)[0]).Action | Should -Be 'SuppressDuplicate'
        Save-History -Runs @(
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-review'; Classification = 'ReviewNeeded'; ReasonCode = 'InvalidCache' }) },
            [ordered]@{ TriggerKind = 'Scheduled'; Sources = @([ordered]@{ SourceId = 'm3u-review'; Classification = 'ReviewNeeded'; ReasonCode = 'InvalidCache' }) }
        )
        $escalated = Invoke-Planner -UseHistory
        $escalated.Notification.Level | Should -Be 'EscalatedInterrupt'
        (@($escalated.Notification.Items)[0]).Action | Should -Be 'EscalateInterrupt'
    }

    It 'reports observed lock contention without acquiring a lock' {
        $script:Policy = New-Policy -Enabled $true
        Save-Inputs
        $plan = Invoke-Planner -ObservedLockState Busy
        Assert-PlanSchema
        $plan.Schedule.Decision | Should -Be 'BLOCKED_BY_LOCK'
        $plan.LockObservation.Status | Should -Be 'Busy'
        $plan.LockObservation.ReasonCode | Should -Be 'ObservedLockBusy'
        Test-Path (Join-Path $script:Project 'output/operations/scheduled-refresh.lock') | Should -BeFalse
    }

    It 'reports unknown lock state as blocked with explicit evidence' {
        $script:Policy = New-Policy -Enabled $true
        Save-Inputs
        $plan = Invoke-Planner -ObservedLockState Unknown
        Assert-PlanSchema
        $plan.Schedule.Decision | Should -Be 'BLOCKED_BY_LOCK'
        $plan.Schedule.ReasonCode | Should -Be 'ObservedLockUnknown'
        $plan.LockObservation.Status | Should -Be 'Unknown'
        $plan.LockObservation.ReasonCode | Should -Be 'ObservedLockUnknown'
    }

    It 'redacts display labels, URLs, credentials, paths, and payload-like reasons' {
        $row = New-SourceRow -SourceId 'C:\private\secret-source.json' -Name 'https://provider.invalid/ACCOUNT_ID/TOKEN' -Classification 'ReviewNeeded' -ReasonCode 'InvalidCache'
        $row.SafeReason = 'https://example.invalid/REDACTED payload content'
        Save-Inputs -Rows @($row)
        $null = Invoke-Planner
        $raw = (Get-Content -LiteralPath (Join-Path $script:OutputRoot 'scheduled-refresh-plan.json') -Raw) + (Get-Content -LiteralPath (Join-Path $script:OutputRoot 'scheduled-refresh-plan.md') -Raw)
        $raw | Should -Not -Match 'provider\.invalid|ACCOUNT_ID|TOKEN|secret-source|payload content'
        $raw | Should -Match 'source-'
    }

    It 'does not mutate accepted state, generations, pointers, or active output' {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Project 'state'), (Join-Path $script:Project 'output') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:Project 'state/accepted-lineup.json') -Value 'accepted-sentinel' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:Project 'output/merged.m3u') -Value 'm3u-sentinel' -Encoding utf8
        Save-Inputs
        $null = Invoke-Planner
        Get-Content -LiteralPath (Join-Path $script:Project 'state/accepted-lineup.json') -Raw | Should -Match 'accepted-sentinel'
        Get-Content -LiteralPath (Join-Path $script:Project 'output/merged.m3u') -Raw | Should -Match 'm3u-sentinel'
        Test-Path (Join-Path $script:Project 'state/generations') | Should -BeFalse
        Test-Path (Join-Path $script:Project 'state/accepted-lineup.json.previous') | Should -BeFalse
    }
}
