function Get-ChannelForgeScheduledOperationUtcText {
    param([Parameter(Mandatory)][datetimeoffset]$Value)
    $Value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-ChannelForgeScheduledOperationSha256Hex {
    param([Parameter(Mandatory)][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Assert-ChannelForgeTaskSchedulerAvailable {
    if ($env:OS -ne 'Windows_NT') {
        throw 'WindowsTaskSchedulerUnavailable'
    }
    foreach ($commandName in @('Get-ScheduledTask', 'Register-ScheduledTask', 'Unregister-ScheduledTask', 'New-ScheduledTaskTrigger', 'New-ScheduledTaskAction', 'New-ScheduledTaskPrincipal', 'New-ScheduledTaskSettingsSet', 'New-ScheduledTask', 'Export-ScheduledTask')) {
        if ($null -eq (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            throw 'WindowsTaskSchedulerUnavailable'
        }
    }
}

function Resolve-ChannelForgeScheduledOperationRoot {
    param([Parameter(Mandatory)][string]$Root)
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'RootPathMissing' }
    try { $full = [IO.Path]::GetFullPath($Root) } catch { throw 'RootPathUnsafe' }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw 'RootPathMissing' }
    try { $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop } catch { throw 'RootPathUnsafe' }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'RootPathReparsePoint' }
    if ($full.StartsWith('\\')) { throw 'RootPathUnc' }
    $full = $item.FullName.Replace('/', '\').TrimEnd('\')
    if ([IO.Path]::GetPathRoot($full).TrimEnd('\') -eq $full) { throw 'RootPathDriveRoot' }
    $caseInsensitiveCanonical = $full.ToUpperInvariant()
    [pscustomobject][ordered]@{
        FullPath = $full
        CanonicalCaseInsensitivePath = $caseInsensitiveCanonical
        Digest = Get-ChannelForgeScheduledOperationSha256Hex -Value $caseInsensitiveCanonical
    }
}

function Get-ChannelForgeScheduledOperationTaskIdentity {
    param([Parameter(Mandatory)][object]$RootInfo)
    [pscustomobject][ordered]@{
        Owner = 'ChannelForge'
        TaskPath = '\ChannelForge\'
        TaskName = 'ScheduledRefresh-' + $RootInfo.Digest.Substring(0, 16)
        RootDigest = $RootInfo.Digest
    }
}

function Get-ChannelForgeScheduledOperationPolicyCanonical {
    param([Parameter(Mandatory)][object]$Policy)
    [ordered]@{
        SchemaVersion = 'scheduled-refresh-policy/v1'
        Enabled = [bool]$Policy.Enabled
        TimeZoneId = 'UTC'
        Cadence = [ordered]@{
            Mode = 'Daily'
            At = [string]$Policy.Cadence.At
        }
        AllowedWindow = [ordered]@{
            Start = [string]$Policy.AllowedWindow.Start
            End = [string]$Policy.AllowedWindow.End
        }
        JitterMinutes = [int]$Policy.JitterMinutes
        MaxRunDurationMinutes = [int]$Policy.MaxRunDurationMinutes
        StaleRunThresholdMinutes = [int]$Policy.StaleRunThresholdMinutes
        HeartbeatIntervalSeconds = [int]$Policy.HeartbeatIntervalSeconds
        Retry = [ordered]@{ MaxAttemptsPerScheduleSlot = 1 }
        ManualOverride = [ordered]@{
            Allowed = [bool]$Policy.ManualOverride.Allowed
            AllowedWhenDisabled = [bool]$Policy.ManualOverride.AllowedWhenDisabled
            BypassAllowedWindow = [bool]$Policy.ManualOverride.BypassAllowedWindow
            CountsTowardScheduledCadence = [bool]$Policy.ManualOverride.CountsTowardScheduledCadence
        }
        Notification = [ordered]@{
            DegradedWarningAfterConsecutiveRuns = [int]$Policy.Notification.DegradedWarningAfterConsecutiveRuns
            RepeatedFailureEscalationAfterConsecutiveRuns = [int]$Policy.Notification.RepeatedFailureEscalationAfterConsecutiveRuns
            SuppressDuplicateIssueUntilFingerprintChanges = [bool]$Policy.Notification.SuppressDuplicateIssueUntilFingerprintChanges
        }
        Retention = [ordered]@{
            MaxRunRecords = [int]$Policy.Retention.MaxRunRecords
            MaxAgeDays = [int]$Policy.Retention.MaxAgeDays
        }
    }
}

function Get-ChannelForgeScheduledOperationPolicyInfo {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SchemaPath
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'PolicyMissing' }
    try {
        if (-not (Test-Json -Path $Path -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'PolicySchemaInvalid' }
        $policy = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -match 'PolicySchemaInvalid') { throw 'PolicySchemaInvalid' }
        throw 'PolicyUnreadable'
    }
    try {
        $start = [int]$policy.AllowedWindow.Start.Substring(0, 2) * 60 + [int]$policy.AllowedWindow.Start.Substring(3, 2)
        $end = [int]$policy.AllowedWindow.End.Substring(0, 2) * 60 + [int]$policy.AllowedWindow.End.Substring(3, 2)
    }
    catch { throw 'PolicySemanticInvalid' }
    if ($end -le $start) { throw 'PolicyOvernightWindow' }
    if (([int]$policy.StaleRunThresholdMinutes * 60) -lt ([int]$policy.HeartbeatIntervalSeconds * 2)) { throw 'PolicyStaleThresholdInvalid' }
    if ([int]$policy.Notification.RepeatedFailureEscalationAfterConsecutiveRuns -lt [int]$policy.Notification.DegradedWarningAfterConsecutiveRuns) { throw 'PolicyNotificationThresholdInvalid' }
    $canonical = Get-ChannelForgeScheduledOperationPolicyCanonical -Policy $policy
    $canonicalJson = $canonical | ConvertTo-Json -Depth 10 -Compress
    [pscustomobject][ordered]@{
        Path = $Path
        Raw = $policy
        Canonical = $canonical
        Digest = Get-ChannelForgeScheduledOperationSha256Hex -Value $canonicalJson
        AtMinutes = ([int]$policy.Cadence.At.Substring(0, 2) * 60) + [int]$policy.Cadence.At.Substring(3, 2)
        WindowStartMinutes = $start
        WindowEndMinutes = $end
    }
}

function Resolve-ChannelForgeScheduledOperationPolicyPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Path
    )
    if (-not [string]::IsNullOrWhiteSpace($Path)) { return [IO.Path]::GetFullPath($Path) }
    $local = Join-Path $Root 'config/scheduled-refresh.local.json'
    if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
    Join-Path $Root 'config/scheduled-refresh.example.json'
}

function Get-ChannelForgeScheduledOperationRuntime {
    $candidate = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        try { $candidate = (Get-Command pwsh -ErrorAction Stop).Source } catch { return [pscustomobject]@{ Available = $false; Code = 'RuntimeUnavailable'; Version = $null } }
    }
    try {
        $probe = & $candidate -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString() + "|" + $PSVersionTable.PSEdition' 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'runtime probe failed' }
        $parts = ([string]$probe).Trim().Split('|')
        $version = [version]$parts[0]
        if ($parts.Count -lt 2 -or $parts[1] -ne 'Core' -or $version -lt [version]'7.6') { return [pscustomobject]@{ Available = $false; Code = 'RuntimeVersionInvalid'; Version = $version.ToString() } }
        [pscustomobject]@{ Available = $true; Code = 'None'; Version = $version.ToString(); Path = [IO.Path]::GetFullPath($candidate) }
    }
    catch { [pscustomobject]@{ Available = $false; Code = 'RuntimeUnavailable'; Version = $null } }
}

function ConvertTo-ChannelForgeScheduledOperationArgument {
    param([Parameter(Mandatory)][string]$Value)
    '"' + $Value.Replace('"', '\"') + '"'
}

function New-ChannelForgeScheduledOperationTaskXml {
    param(
        [Parameter(Mandatory)][object]$Identity,
        [Parameter(Mandatory)][object]$RootInfo,
        [Parameter(Mandatory)][object]$PolicyInfo,
        [Parameter(Mandatory)][string]$RuntimePath,
        [Parameter(Mandatory)][string]$WrapperPath,
        [Parameter(Mandatory)][datetimeoffset]$StartBoundaryUtc
    )
    $trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddHours(3))
    $trigger.StartBoundary = $StartBoundaryUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $actionArguments = '-NoLogo -NoProfile -NonInteractive -File ' + (ConvertTo-ChannelForgeScheduledOperationArgument -Value $WrapperPath) + ' -Root ' + (ConvertTo-ChannelForgeScheduledOperationArgument -Value $RootInfo.FullPath) + ' -ScheduledInvocation'
    $action = New-ScheduledTaskAction -Execute $RuntimePath -Argument $actionArguments -WorkingDirectory $RootInfo.FullPath
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $executionMinutes = [Math]::Max(1, [int]$PolicyInfo.Raw.JitterMinutes + [int]$PolicyInfo.Raw.MaxRunDurationMinutes + 1)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::FromMinutes($executionMinutes))
    $definition = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'ChannelForge owned scheduled refresh; one bounded foreground invocation.'
    $xml = [xml](Export-ScheduledTask -InputObject $definition -ErrorAction Stop)
    $namespace = 'http://schemas.microsoft.com/windows/2004/02/mit/task'
    $data = $xml.CreateElement('Data', $namespace)
    $data.InnerText = 'ChannelForgeScheduledRefresh/v1;Owner=ChannelForge;RootDigest=' + $Identity.RootDigest + ';PolicyDigest=' + $PolicyInfo.Digest + ';TaskName=' + $Identity.TaskName + ';TriggerKind=Scheduled;WrapperContract=scheduled-refresh-wrapper/v1'
    $actionsNode = $xml.SelectSingleNode('//*[local-name()="Actions"]')
    $actionsNode.ParentNode.InsertBefore($data, $actionsNode) | Out-Null
    $xml.OuterXml
}

function Get-ChannelForgeScheduledOperationTaskXml {
    param([Parameter(Mandatory)][object]$Task)
    $taskFile = Join-Path (Join-Path (Join-Path $env:windir 'System32/Tasks') 'ChannelForge') $Task.TaskName
    if (Test-Path -LiteralPath $taskFile -PathType Leaf) {
        return Get-Content -LiteralPath $taskFile -Raw -ErrorAction Stop
    }
    Export-ScheduledTask -TaskName $Task.TaskName -TaskPath $Task.TaskPath -ErrorAction Stop
}

function ConvertFrom-ChannelForgeScheduledOperationMarker {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '^ChannelForgeScheduledRefresh/v1;Owner=ChannelForge;RootDigest=([0-9a-f]{64});PolicyDigest=([0-9a-f]{64});TaskName=(ScheduledRefresh-[0-9a-f]{16});TriggerKind=Scheduled;WrapperContract=scheduled-refresh-wrapper/v1$') { return $null }
    [pscustomobject][ordered]@{
        SchemaVersion = 'scheduled-refresh-registration/v1'
        Owner = 'ChannelForge'
        RootDigest = $Matches[1]
        PolicyDigest = $Matches[2]
        TaskName = $Matches[3]
        TriggerKind = 'Scheduled'
        WrapperContract = 'scheduled-refresh-wrapper/v1'
    }
}

function Get-ChannelForgeScheduledOperationTaskMarker {
    param([Parameter(Mandatory)][string]$Xml)
    try {
        $document = [xml]$Xml
        $node = $document.SelectSingleNode('//*[local-name()="Data"]')
        if ($null -eq $node) { return $null }
        ConvertFrom-ChannelForgeScheduledOperationMarker -Value ([string]$node.InnerText)
    }
    catch { $null }
}

function Get-ChannelForgeScheduledOperationTaskRecord {
    param(
        [Parameter(Mandatory)][string]$TaskPath,
        [Parameter(Mandatory)][string]$TaskName
    )
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) { return $null }
    $xml = Get-ChannelForgeScheduledOperationTaskXml -Task $task
    [pscustomobject][ordered]@{
        Task = $task
        Xml = $xml
        Marker = Get-ChannelForgeScheduledOperationTaskMarker -Xml $xml
    }
}

function Get-ChannelForgeScheduledOperationOwnedTaskRecords {
    param([Parameter(Mandatory)][string]$TaskPath)
    $tasks = @(Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue)
    foreach ($task in $tasks | Where-Object { $_.TaskName -like 'ScheduledRefresh-*' }) {
        try {
            $record = Get-ChannelForgeScheduledOperationTaskRecord -TaskPath $TaskPath -TaskName $task.TaskName
            if ($null -ne $record.Marker -and $record.Marker.Owner -eq 'ChannelForge') { $record }
        }
        catch { }
    }
}

function Get-ChannelForgeScheduledOperationRegistrationPath {
    param([Parameter(Mandatory)][string]$Root)
    Join-Path $Root 'output/operations/scheduled-refresh-registration.json'
}

function Write-ChannelForgeScheduledOperationRegistrationEvidence {
    param(
        [Parameter(Mandatory)][object]$Identity,
        [Parameter(Mandatory)][object]$PolicyInfo,
        [Parameter(Mandatory)][string]$TaskDefinitionDigest,
        [Parameter(Mandatory)][datetimeoffset]$RegisteredAtUtc,
        [Parameter(Mandatory)][datetimeoffset]$StartBoundaryUtc,
        [Parameter(Mandatory)][string]$RuntimeVersion,
        [Parameter(Mandatory)][int]$ExecutionTimeLimitMinutes,
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$Root
    )
    $path = Get-ChannelForgeScheduledOperationRegistrationPath -Root $Root
    $operations = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $operations | Out-Null
    $evidence = [ordered]@{
        SchemaVersion = 'scheduled-refresh-registration/v1'
        Owner = 'ChannelForge'
        TaskPath = $Identity.TaskPath
        TaskName = $Identity.TaskName
        RootDigest = $Identity.RootDigest
        PolicyDigest = $PolicyInfo.Digest
        TaskDefinitionDigest = $TaskDefinitionDigest
        RegisteredAtUtc = Get-ChannelForgeScheduledOperationUtcText -Value $RegisteredAtUtc
        TriggerKind = 'Scheduled'
        CadenceMode = 'Daily'
        CadenceAtUtc = [string]$PolicyInfo.Raw.Cadence.At
        StartBoundaryUtc = Get-ChannelForgeScheduledOperationUtcText -Value $StartBoundaryUtc
        ExecutionTimeLimitMinutes = $ExecutionTimeLimitMinutes
        RuntimeVersion = $RuntimeVersion
        RuntimeContract = 'PowerShell Core 7.6 or newer'
        WrapperContract = 'scheduled-refresh-wrapper/v1'
        ReadyForFirstRun = $true
    }
    [IO.File]::WriteAllText($path, (($evidence | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    if (-not (Test-Json -Path $path -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'RegistrationEvidenceSchemaInvalid' }
    $md = @(
        '# Scheduled refresh registration',
        '',
        'This redacted record describes the ChannelForge-owned Windows Task Scheduler registration.',
        '',
        "- Task path: $($evidence.TaskPath)",
        "- Task name: $($evidence.TaskName)",
        "- Root digest: $($evidence.RootDigest)",
        "- Policy digest: $($evidence.PolicyDigest)",
        "- Task definition digest: $($evidence.TaskDefinitionDigest)",
        "- Registered at (UTC): $($evidence.RegisteredAtUtc)",
        "- Cadence: $($evidence.CadenceMode) at $($evidence.CadenceAtUtc) UTC",
        "- Start boundary (UTC): $($evidence.StartBoundaryUtc)",
        "- Execution limit (minutes): $($evidence.ExecutionTimeLimitMinutes)",
        "- Runtime contract: $($evidence.RuntimeContract)",
        "- Wrapper contract: $($evidence.WrapperContract)",
        '',
        'The record intentionally excludes the repository path, provider and stream URLs, credentials, task output, and child process text.'
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $operations 'scheduled-refresh-registration.md'), ($md + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    [pscustomobject]$evidence
}

function Read-ChannelForgeScheduledOperationRegistrationEvidence {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$SchemaPath
    )
    $path = Get-ChannelForgeScheduledOperationRegistrationPath -Root $Root
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        if (-not (Test-Json -Path $path -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'RegistrationEvidenceSchemaInvalid' }
        Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch { throw 'RegistrationEvidenceInvalid' }
}

function Write-ChannelForgeScheduledOperationHistory {
    param(
        [Parameter(Mandatory)][object]$Report,
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][object]$PolicyInfo,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SchemaPath
    )
    $runs = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if (-not (Test-Json -Path $Path -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'HistoryEvidenceInvalid' }
        $existing = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $runs = @($existing.Runs)
    }
    $sourceItems = @()
    if ($null -ne $Plan -and $null -ne $Plan.Notification) {
        $sourceItems = @($Plan.Notification.Items | ForEach-Object {
                [ordered]@{
                    SourceId = [string]$_.SourceId
                    Classification = [string]$_.Classification
                    ReasonCode = [string]$_.ReasonCode
                    IssueFingerprint = [string]$_.IssueFingerprint
                }
            })
    }
    $newRun = [ordered]@{
        RunId = [string]$Report.RunId
        ScheduleSlotId = [string]$Report.ScheduleSlotId
        TriggerKind = [string]$Report.TriggerKind
        Status = [string]$Report.Status
        RequestedAtUtc = [string]$Report.RequestedAtUtc
        StartedAtUtc = $Report.StartedAtUtc
        FinishedAtUtc = $Report.FinishedAtUtc
        PolicyDigest = $Report.PolicyDigest
        InputResultDigest = $Report.InputResultDigest
        PlanDecision = $Report.PlanDecision
        PlanReasonCode = $Report.PlanReasonCode
        FailureCode = [string]$Report.FailureCode
        Counts = [ordered]@{
            AutoHandled = [int]$Report.Counts.AutoHandled
            Degraded = [int]$Report.Counts.Degraded
            ReviewNeeded = [int]$Report.Counts.ReviewNeeded
            NoAction = [int]$Report.Counts.NoAction
        }
        Notification = [ordered]@{
            Level = [string]$Report.NotificationDecision.Level
            Action = [string]$Report.NotificationDecision.Action
            SummaryCode = [string]$Report.NotificationDecision.SummaryCode
        }
        ExecutorStatus = [string]$Report.ExecutorStatus
        ExecutorInvocationCount = [int]$Report.ExecutorInvocationCount
        ExecutorTermination = [string]$Report.ExecutorTermination
        Sources = $sourceItems
    }
    $runs += [pscustomobject]$newRun
    $cutoff = [datetimeoffset]::UtcNow.AddDays(-[int]$PolicyInfo.Raw.Retention.MaxAgeDays)
    $runs = @($runs | Where-Object {
            try { ([datetimeoffset]$_.FinishedAtUtc).ToUniversalTime() -ge $cutoff } catch { $false }
        } | Select-Object -Last ([int]$PolicyInfo.Raw.Retention.MaxRunRecords))
    $document = [ordered]@{ SchemaVersion = 'scheduled-refresh-history/v1'; Runs = $runs }
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    [IO.File]::WriteAllText($Path, (($document | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    if (-not (Test-Json -Path $Path -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'HistoryEvidenceSchemaInvalid' }
}
