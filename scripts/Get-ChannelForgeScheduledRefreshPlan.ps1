[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$PolicyPath,
    [string]$SourceRefreshResultPath,
    [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]::UtcNow),
    [string]$OutputRoot,
    [ValidateSet('Scheduled', 'Manual')]
    [string]$TriggerKind = 'Scheduled',
    [string]$NotificationHistoryPath,
    [ValidateSet('NotAttempted', 'Busy', 'StaleEvidence', 'Unknown')]
    [string]$ObservedLockState = 'NotAttempted'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSScriptRoot
$rootFull = [IO.Path]::GetFullPath($Root)
$policySchemaPath = Join-Path $scriptRoot 'schemas/scheduled-refresh-policy.schema.json'
$resultSchemaPath = Join-Path $scriptRoot 'schemas/source-refresh-result.schema.json'
$planSchemaPath = Join-Path $scriptRoot 'schemas/scheduled-refresh-plan.schema.json'

function Throw-FailClosed {
    param([Parameter(Mandatory)][string]$Code)
    throw "FAIL_CLOSED: $Code"
}


function Assert-RequiredProperties {
    param(
        [Parameter(Mandatory)][object]$Object,
        [Parameter(Mandatory)][string[]]$Names,
        [Parameter(Mandatory)][string]$MissingCode
    )

    foreach ($name in $Names) {
        if ($null -eq $Object.PSObject.Properties[$name]) {
            Throw-FailClosed -Code $MissingCode
        }
    }
}

function Read-JsonDocument {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$MissingCode,
        [Parameter(Mandatory)][string]$InvalidCode
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Throw-FailClosed -Code $MissingCode
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Throw-FailClosed -Code $InvalidCode
    }
}

function Test-IntegerValue {
    param([AllowNull()][object]$Value)
    return $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [short] -or
        $Value -is [ushort] -or
        $Value -is [int] -or
        $Value -is [uint] -or
        $Value -is [long] -or
        $Value -is [ulong]
}

function ConvertTo-UtcDateTimeOffset {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$InvalidCode
    )

    try {
        return ([datetimeoffset]::Parse(
                [string]$Value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime()
    }
    catch {
        Throw-FailClosed -Code $InvalidCode
    }
}

function ConvertTo-Minutes {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$InvalidCode
    )

    if ($Value -notmatch '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$') {
        Throw-FailClosed -Code $InvalidCode
    }
    return ([int]$Value.Substring(0, 2) * 60) + [int]$Value.Substring(3, 2)
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$Value)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Value)
        return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-UtcText {
    param([AllowNull()][datetimeoffset]$Value)
    if ($null -eq $Value) { return $null }
    return $Value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-SafeSourceId {
    param([Parameter(Mandatory)][string]$SourceId)

    if ($SourceId -match '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
        return $SourceId
    }
    return 'source-' + (Get-Sha256Hex -Value $SourceId).Substring(0, 16)
}

function Get-PolicyDocument {
    param([Parameter(Mandatory)][string]$Path)

    $policy = Read-JsonDocument -Path $Path -MissingCode 'PolicyMissing' -InvalidCode 'PolicyJsonInvalid'
    try {
        if (-not (Test-Json -Path $Path -SchemaFile $policySchemaPath -ErrorAction Stop)) {
            Throw-FailClosed -Code 'PolicySchemaInvalid'
        }
    }
    catch {
        if ($_.Exception.Message -like 'FAIL_CLOSED:*') { throw }
        Throw-FailClosed -Code 'PolicySchemaInvalid'
    }

    $startMinutes = ConvertTo-Minutes -Value ([string]$policy.AllowedWindow.Start) -InvalidCode 'PolicyWindowInvalid'
    $endMinutes = ConvertTo-Minutes -Value ([string]$policy.AllowedWindow.End) -InvalidCode 'PolicyWindowInvalid'
    if ($endMinutes -le $startMinutes) {
        Throw-FailClosed -Code 'OvernightWindowRejected'
    }
    if (([int]$policy.StaleRunThresholdMinutes * 60) -lt ([int]$policy.HeartbeatIntervalSeconds * 2)) {
        Throw-FailClosed -Code 'StaleThresholdTooShort'
    }
    if ([int]$policy.Notification.RepeatedFailureEscalationAfterConsecutiveRuns -lt
        [int]$policy.Notification.DegradedWarningAfterConsecutiveRuns) {
        Throw-FailClosed -Code 'NotificationThresholdOrderInvalid'
    }

    $canonical = [ordered]@{
        SchemaVersion = 'scheduled-refresh-policy/v1'
        Enabled = [bool]$policy.Enabled
        TimeZoneId = 'UTC'
        Cadence = [ordered]@{
            Mode = 'Daily'
            At = [string]$policy.Cadence.At
        }
        AllowedWindow = [ordered]@{
            Start = [string]$policy.AllowedWindow.Start
            End = [string]$policy.AllowedWindow.End
        }
        JitterMinutes = [int]$policy.JitterMinutes
        MaxRunDurationMinutes = [int]$policy.MaxRunDurationMinutes
        StaleRunThresholdMinutes = [int]$policy.StaleRunThresholdMinutes
        HeartbeatIntervalSeconds = [int]$policy.HeartbeatIntervalSeconds
        Retry = [ordered]@{ MaxAttemptsPerScheduleSlot = 1 }
        ManualOverride = [ordered]@{
            Allowed = [bool]$policy.ManualOverride.Allowed
            AllowedWhenDisabled = [bool]$policy.ManualOverride.AllowedWhenDisabled
            BypassAllowedWindow = [bool]$policy.ManualOverride.BypassAllowedWindow
            CountsTowardScheduledCadence = [bool]$policy.ManualOverride.CountsTowardScheduledCadence
        }
        Notification = [ordered]@{
            DegradedWarningAfterConsecutiveRuns = [int]$policy.Notification.DegradedWarningAfterConsecutiveRuns
            RepeatedFailureEscalationAfterConsecutiveRuns = [int]$policy.Notification.RepeatedFailureEscalationAfterConsecutiveRuns
            SuppressDuplicateIssueUntilFingerprintChanges = [bool]$policy.Notification.SuppressDuplicateIssueUntilFingerprintChanges
        }
        Retention = [ordered]@{
            MaxRunRecords = [int]$policy.Retention.MaxRunRecords
            MaxAgeDays = [int]$policy.Retention.MaxAgeDays
        }
    }
    $canonicalJson = $canonical | ConvertTo-Json -Depth 10 -Compress
    return [pscustomobject][ordered]@{
        Raw = $policy
        Canonical = $canonical
        Digest = Get-Sha256Hex -Value $canonicalJson
        WindowStartMinutes = $startMinutes
        WindowEndMinutes = $endMinutes
        AtMinutes = ConvertTo-Minutes -Value ([string]$policy.Cadence.At) -InvalidCode 'PolicyCadenceInvalid'
    }
}

function Get-InputValidationErrorCode {
    param([Parameter(Mandatory)][string]$Message)
    if ($Message -match 'FAIL_CLOSED:\s*([A-Za-z0-9_]+)') {
        return $Matches[1]
    }
    return 'SourceRefreshResultInvalid'
}

function Get-SourceRefreshDocument {
    param([Parameter(Mandatory)][string]$Path)

    $result = Read-JsonDocument -Path $Path -MissingCode 'SourceRefreshResultMissing' -InvalidCode 'SourceRefreshResultJsonInvalid'
    if ($null -eq $result -or $result -is [array]) {
        Throw-FailClosed -Code 'SourceRefreshResultObjectRequired'
    }
    Assert-RequiredProperties -Object $result -Names @(
        'SchemaVersion', 'EvaluationTimeUtc', 'ReviewNeeded', 'ReviewNeededCount', 'Sources'
    ) -MissingCode 'MissingRequiredField'
    if ([string]$result.SchemaVersion -cne 'source-refresh-result/v2') {
        Throw-FailClosed -Code 'InvalidSourceRefreshResultSchemaVersion'
    }
    if ($result.ReviewNeeded -isnot [bool]) {
        Throw-FailClosed -Code 'ReviewNeededTypeInvalid'
    }
    if (-not (Test-IntegerValue $result.ReviewNeededCount) -or [int64]$result.ReviewNeededCount -lt 0) {
        Throw-FailClosed -Code 'ReviewNeededCountTypeInvalid'
    }
    $evaluation = ConvertTo-UtcDateTimeOffset -Value $result.EvaluationTimeUtc -InvalidCode 'EvaluationTimeInvalid'
    if ($null -eq $result.Sources) {
        Throw-FailClosed -Code 'SourcesRequired'
    }

    $allowedClassifications = @('AutoHandled', 'Degraded', 'ReviewNeeded', 'NoAction')
    $allowedReasons = @(
        'ReusedValidCache', 'ConditionalUnchanged', 'ConditionalChanged', 'FullRefreshValidated',
        'RefreshFailedLkgPreserved', 'RefreshFailedNoLkg', 'InvalidCache', 'DisabledSource', 'LocalSource'
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @($result.Sources)) {
        Assert-RequiredProperties -Object $row -Names @(
            'SourceId', 'Name', 'Kind', 'PlannedAction', 'Attempted', 'Result', 'Classification',
            'ReasonCode', 'CacheChanged', 'LastKnownGoodPreserved', 'ValidatorOutcome', 'SafeReason'
        ) -MissingCode 'MissingRequiredField'
        if ([string]$row.Classification -notin $allowedClassifications) {
            Throw-FailClosed -Code 'UnknownClassification'
        }
        if ([string]$row.ReasonCode -notin $allowedReasons) {
            Throw-FailClosed -Code 'UnknownReasonCode'
        }
        if ($row.Attempted -isnot [bool] -or $row.CacheChanged -isnot [bool] -or
            $row.LastKnownGoodPreserved -isnot [bool]) {
            Throw-FailClosed -Code 'SourceBooleanTypeInvalid'
        }
        $rows.Add($row) | Out-Null
    }

    try {
        if (-not (Test-Json -Path $Path -SchemaFile $resultSchemaPath -ErrorAction Stop)) {
            Throw-FailClosed -Code 'SourceRefreshResultSchemaInvalid'
        }
    }
    catch {
        if ($_.Exception.Message -like 'FAIL_CLOSED:*') { throw }
        Throw-FailClosed -Code 'SourceRefreshResultSchemaInvalid'
    }

    $reviewRows = @($rows | Where-Object { [string]$_.Classification -ceq 'ReviewNeeded' }).Count
    if ([bool]$result.ReviewNeeded -ne ($reviewRows -gt 0)) {
        Throw-FailClosed -Code 'ReviewNeededMismatch'
    }
    if ([int64]$result.ReviewNeededCount -ne $reviewRows) {
        Throw-FailClosed -Code 'ReviewNeededCountMismatch'
    }

    $canonicalSources = @($rows | Sort-Object @{ Expression = { [string]$_.Kind } }, @{ Expression = { [string]$_.SourceId } } | ForEach-Object {
            [ordered]@{
                SourceId = [string]$_.SourceId
                Kind = [string]$_.Kind
                PlannedAction = [string]$_.PlannedAction
                Attempted = [bool]$_.Attempted
                Result = [string]$_.Result
                Classification = [string]$_.Classification
                ReasonCode = [string]$_.ReasonCode
                CacheChanged = [bool]$_.CacheChanged
                LastKnownGoodPreserved = [bool]$_.LastKnownGoodPreserved
                ValidatorOutcome = [string]$_.ValidatorOutcome
            }
        })
    $canonical = [ordered]@{
        SchemaVersion = 'source-refresh-result/v2'
        EvaluationTimeUtc = Get-UtcText -Value $evaluation
        ReviewNeeded = [bool]$result.ReviewNeeded
        ReviewNeededCount = [int]$result.ReviewNeededCount
        Sources = $canonicalSources
    }
    $digest = Get-Sha256Hex -Value (($canonical | ConvertTo-Json -Depth 10 -Compress))
    return [pscustomobject][ordered]@{
        Raw = $result
        Rows = @($rows)
        EvaluationTimeUtc = $evaluation
        Digest = $digest
        ReviewNeeded = [bool]$result.ReviewNeeded
        ReviewNeededCount = [int]$result.ReviewNeededCount
    }
}

function Get-HistoryRuns {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }
    $history = Read-JsonDocument -Path $Path -MissingCode 'NotificationHistoryMissing' -InvalidCode 'NotificationHistoryInvalid'
    if ($null -eq $history -or $history -is [array]) { Throw-FailClosed -Code 'NotificationHistoryInvalid' }
    Assert-RequiredProperties -Object $history -Names @('SchemaVersion', 'Runs') -MissingCode 'NotificationHistoryMissingField'
    if ([string]$history.SchemaVersion -cne 'scheduled-refresh-history/v1') { Throw-FailClosed -Code 'NotificationHistorySchemaInvalid' }
    $runs = [System.Collections.Generic.List[object]]::new()
    foreach ($run in @($history.Runs)) {
        Assert-RequiredProperties -Object $run -Names @('TriggerKind', 'Sources') -MissingCode 'NotificationHistoryMissingField'
        if ([string]$run.TriggerKind -notin @('Scheduled', 'Manual')) { Throw-FailClosed -Code 'NotificationHistoryTriggerInvalid' }
        foreach ($source in @($run.Sources)) {
            Assert-RequiredProperties -Object $source -Names @('SourceId', 'Classification', 'ReasonCode') -MissingCode 'NotificationHistoryMissingField'
            if ([string]$source.Classification -notin @('AutoHandled', 'Degraded', 'ReviewNeeded', 'NoAction')) { Throw-FailClosed -Code 'NotificationHistoryClassificationInvalid' }
            if ([string]$source.ReasonCode -notin @(
                    'ReusedValidCache', 'ConditionalUnchanged', 'ConditionalChanged', 'FullRefreshValidated',
                    'RefreshFailedLkgPreserved', 'RefreshFailedNoLkg', 'InvalidCache', 'DisabledSource', 'LocalSource')) {
                Throw-FailClosed -Code 'NotificationHistoryReasonInvalid'
            }
        }
        $runs.Add($run) | Out-Null
    }
    return @($runs)
}

function Get-PriorScheduledFailureCount {
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Runs,
        [Parameter(Mandatory)][string]$SourceId,
        [Parameter(Mandatory)][string]$Classification,
        [Parameter(Mandatory)][string]$ReasonCode
    )

    if ($Classification -notin @('Degraded', 'ReviewNeeded')) { return 0 }
    $count = 0
    for ($index = $Runs.Count - 1; $index -ge 0; $index--) {
        $run = $Runs[$index]
        if ([string]$run.TriggerKind -eq 'Manual') { continue }
        $matchedSources = @($run.Sources | Where-Object {
                [string]$_.SourceId -ceq $SourceId -and
                [string]$_.Classification -ceq $Classification -and
                [string]$_.ReasonCode -ceq $ReasonCode
            })
        if ($matchedSources.Count -eq 1) {
            $count++
        }
        else {
            break
        }
    }
    return $count
}

function Get-JitterOffsetMinutes {
    param(
        [Parameter(Mandatory)][string]$PolicyDigest,
        [Parameter(Mandatory)][datetimeoffset]$NominalDueUtc,
        [Parameter(Mandatory)][int]$JitterMinutes
    )

    if ($JitterMinutes -eq 0) { return 0 }
    $hash = Get-Sha256Hex -Value ($PolicyDigest + '|' + (Get-UtcText -Value $NominalDueUtc))
    $bucket = [Convert]::ToUInt32($hash.Substring(0, 8), 16)
    return ([int]($bucket % (2 * $JitterMinutes + 1))) - $JitterMinutes
}

function Get-ScheduleSlot {
    param(
        [Parameter(Mandatory)][datetime]$Date,
        [Parameter(Mandatory)][psobject]$Policy,
        [Parameter(Mandatory)][int]$AtMinutes,
        [Parameter(Mandatory)][int]$WindowStartMinutes,
        [Parameter(Mandatory)][int]$WindowEndMinutes
    )

    $nominal = [datetimeoffset]::new($Date.AddMinutes($AtMinutes), [TimeSpan]::Zero)
    $windowStart = [datetimeoffset]::new($Date.AddMinutes($WindowStartMinutes), [TimeSpan]::Zero)
    $windowEnd = [datetimeoffset]::new($Date.AddMinutes($WindowEndMinutes), [TimeSpan]::Zero)
    $jitter = Get-JitterOffsetMinutes -PolicyDigest $Policy.Digest -NominalDueUtc $nominal -JitterMinutes ([int]$Policy.Raw.JitterMinutes)
    $proposed = $nominal.AddMinutes($jitter)
    return [pscustomobject][ordered]@{
        NominalDueUtc = $nominal
        WindowStartUtc = $windowStart
        WindowEndUtc = $windowEnd
        JitterOffsetMinutes = $jitter
        ProposedStartUtc = $proposed
        JitterInsideWindow = $proposed -ge $windowStart -and $proposed -lt $windowEnd
    }
}

function New-EmptyCounts {
    return [ordered]@{ AutoHandled = 0; Degraded = 0; ReviewNeeded = 0; NoAction = 0 }
}

function New-Safety {
    return [ordered]@{
        MutationScope = 'ReportOnly'
        AcceptedStateMutation = 'None'
        GenerationMutation = 'None'
        PointerMutation = 'None'
        PublishedOutputMutation = 'None'
        ProviderStateMutation = 'None'
        IdentityEvidenceMutation = 'None'
    }
}

function Write-PlanReports {
    param(
        [Parameter(Mandatory)][psobject]$Projection,
        [Parameter(Mandatory)][string]$ReportRoot
    )

    $fullReportRoot = [IO.Path]::GetFullPath($ReportRoot)
    New-Item -ItemType Directory -Force -Path $fullReportRoot | Out-Null
    $jsonPath = Join-Path $fullReportRoot 'scheduled-refresh-plan.json'
    $mdPath = Join-Path $fullReportRoot 'scheduled-refresh-plan.md'
    [IO.File]::WriteAllText(
        $jsonPath,
        (($Projection | ConvertTo-Json -Depth 20) + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false))

    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add('# Scheduled refresh plan')
    $md.Add('')
    $md.Add("Evaluation time: $($Projection.EvaluatedAtUtc)")
    $md.Add("Trigger: $($Projection.TriggerKind)")
    $md.Add("Schedule decision: $($Projection.Schedule.Decision)")
    $md.Add("Schedule reason: $($Projection.Schedule.ReasonCode)")
    $md.Add("Policy enabled: $($Projection.PolicyEnabled)")
    $md.Add("Notification: $($Projection.Notification.Level)")
    $md.Add('')
    $md.Add('This report is report-only evidence. It does not acquire a lock, fetch a source, mutate a cache, create accepted state, create a generation, replace a pointer, or publish output.')
    $md.Add('')
    $md.Add('| Classification | Count |')
    $md.Add('| --- | ---: |')
    $md.Add("| AutoHandled | $($Projection.Counts.AutoHandled) |")
    $md.Add("| Degraded | $($Projection.Counts.Degraded) |")
    $md.Add("| ReviewNeeded | $($Projection.Counts.ReviewNeeded) |")
    $md.Add("| NoAction | $($Projection.Counts.NoAction) |")
    $md.Add('')
    $md.Add('## Notification items')
    $md.Add('')
    $md.Add('| Source | Classification | Reason | Action | Scheduled failure count |')
    $md.Add('| --- | --- | --- | --- | ---: |')
    if (@($Projection.Notification.Items).Count -eq 0) {
        $md.Add('| None | — | — | NoNotification | 0 |')
    }
    else {
        foreach ($item in $Projection.Notification.Items) {
            $md.Add("| $($item.SourceId) | $($item.Classification) | $($item.ReasonCode) | $($item.Action) | $($item.ConsecutiveScheduledFailureCount) |")
        }
    }
    $md.Add('')
    $md.Add('## Safety boundary')
    $md.Add('')
    foreach ($property in $Projection.Safety.PSObject.Properties) {
        $md.Add("- $($property.Name): $($property.Value)")
    }
    $md.Add('')
    $md.Add("Lock observation: $($Projection.LockObservation.Status) ($($Projection.LockObservation.ReasonCode))")
    $md.Add("Input validation: $($Projection.InputValidation.Status)")
    if (@($Projection.InputValidation.Errors).Count -gt 0) {
        foreach ($errorCode in $Projection.InputValidation.Errors) {
            $md.Add("- Input error: $errorCode")
        }
    }
    [IO.File]::WriteAllText(
        $mdPath,
        (($md -join [Environment]::NewLine) + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false))
    return [pscustomobject][ordered]@{ JsonPath = $jsonPath; MarkdownPath = $mdPath }
}

if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $localPolicyPath = Join-Path $rootFull 'config/scheduled-refresh.local.json'
    $examplePolicyPath = Join-Path $rootFull 'config/scheduled-refresh.example.json'
    $PolicyPath = if (Test-Path -LiteralPath $localPolicyPath -PathType Leaf) { $localPolicyPath } else { $examplePolicyPath }
}
if ([string]::IsNullOrWhiteSpace($SourceRefreshResultPath)) {
    $SourceRefreshResultPath = Join-Path $rootFull 'output/reports/source-refresh-result.json'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $rootFull 'output/reports'
}

$policy = Get-PolicyDocument -Path $PolicyPath
$evaluation = $EvaluationTimeUtc.ToUniversalTime()
$inputValidationErrors = [System.Collections.Generic.List[string]]::new()
$sourceResult = $null
try {
    $sourceResult = Get-SourceRefreshDocument -Path $SourceRefreshResultPath
}
catch {
    $inputValidationErrors.Add((Get-InputValidationErrorCode -Message $_.Exception.Message)) | Out-Null
}

$counts = New-EmptyCounts
$notificationItems = [System.Collections.Generic.List[object]]::new()
$notificationLevel = 'Quiet'
$notificationSeverity = 0
$summaryCode = 'NoNotification'
$inputProjection = $null
$historyRuns = @()

if ($null -ne $sourceResult) {
    foreach ($row in $sourceResult.Rows) {
        $counts[[string]$row.Classification] = [int]$counts[[string]$row.Classification] + 1
    }
    $inputProjection = [ordered]@{
        SchemaVersion = 'source-refresh-result/v2'
        EvaluationTimeUtc = Get-UtcText -Value $sourceResult.EvaluationTimeUtc
        InputDigest = $sourceResult.Digest
        ReviewNeeded = $sourceResult.ReviewNeeded
        ReviewNeededCount = $sourceResult.ReviewNeededCount
    }
    try {
        $historyRuns = @(Get-HistoryRuns -Path $NotificationHistoryPath)
    }
    catch {
        $inputValidationErrors.Add((Get-InputValidationErrorCode -Message $_.Exception.Message)) | Out-Null
    }
}

if ($null -ne $sourceResult -and $inputValidationErrors.Count -eq 0) {
    foreach ($row in $sourceResult.Rows) {
        $classification = [string]$row.Classification
        $reasonCode = [string]$row.ReasonCode
        $sourceId = [string]$row.SourceId
        $priorFailureCount = if ($classification -in @('Degraded', 'ReviewNeeded')) {
            Get-PriorScheduledFailureCount -Runs $historyRuns -SourceId $sourceId -Classification $classification -ReasonCode $reasonCode
        }
        else { 0 }
        $failureCount = $priorFailureCount
        if ($TriggerKind -eq 'Scheduled' -and $classification -in @('Degraded', 'ReviewNeeded')) {
            $failureCount++
        }
        $action = 'NoNotification'
        $severity = 0
        if ($classification -eq 'Degraded') {
            if ($failureCount -ge [int]$policy.Raw.Notification.RepeatedFailureEscalationAfterConsecutiveRuns) {
                $action = 'EscalateInterrupt'
                $severity = 3
            }
            elseif ($failureCount -ge [int]$policy.Raw.Notification.DegradedWarningAfterConsecutiveRuns) {
                $action = 'NotifyWarning'
                $severity = 1
            }
        }
        elseif ($classification -eq 'ReviewNeeded') {
            $severity = 2
            if ($priorFailureCount -gt 0 -and [bool]$policy.Raw.Notification.SuppressDuplicateIssueUntilFingerprintChanges) {
                $action = 'SuppressDuplicate'
            }
            else {
                $action = 'NotifyInterrupt'
            }
            if ($failureCount -ge [int]$policy.Raw.Notification.RepeatedFailureEscalationAfterConsecutiveRuns) {
                $action = 'EscalateInterrupt'
                $severity = 3
            }
        }
        if ($severity -gt $notificationSeverity) {
            $notificationSeverity = $severity
            $notificationLevel = switch ($severity) {
                3 { 'EscalatedInterrupt' }
                2 { 'Interrupt' }
                1 { 'Warning' }
                default { 'Quiet' }
            }
        }
        $notificationItems.Add([pscustomobject][ordered]@{
                SourceId = Get-SafeSourceId -SourceId $sourceId
                Classification = $classification
                ReasonCode = $reasonCode
                IssueFingerprint = Get-Sha256Hex -Value ($sourceId + '|' + $classification + '|' + $reasonCode)
                Action = $action
                ConsecutiveScheduledFailureCount = $failureCount
            }) | Out-Null
    }
    if ($notificationLevel -eq 'EscalatedInterrupt') {
        if (@($notificationItems | Where-Object Classification -eq 'ReviewNeeded').Count -gt 0) {
            $summaryCode = 'ReviewNeededEscalated'
        }
        else {
            $summaryCode = 'DegradedEscalated'
        }
    }
    elseif ($notificationLevel -eq 'Interrupt') {
        if (@($notificationItems | Where-Object { $_.Classification -eq 'ReviewNeeded' -and $_.Action -eq 'SuppressDuplicate' }).Count -gt 0 -and
            @($notificationItems | Where-Object { $_.Action -eq 'NotifyInterrupt' }).Count -eq 0) {
            $summaryCode = 'ReviewNeededActive'
        }
        else {
            $summaryCode = 'ReviewNeededInterrupt'
        }
    }
    elseif ($notificationLevel -eq 'Warning') {
        $summaryCode = 'DegradedWarning'
    }
}
else {
    $notificationLevel = 'Interrupt'
    $summaryCode = 'InputContractInvalid'
}

$scheduleDecision = 'INPUT_INVALID'
$scheduleReason = 'InputContractInvalid'
$slot = $null
$nextSlot = $null
if ($inputValidationErrors.Count -eq 0) {
    if ($TriggerKind -eq 'Manual') {
        if (-not [bool]$policy.Raw.ManualOverride.Allowed -or
            (-not [bool]$policy.Raw.Enabled -and -not [bool]$policy.Raw.ManualOverride.AllowedWhenDisabled)) {
            $scheduleDecision = 'MANUAL_NOT_ALLOWED'
            $scheduleReason = 'ManualOverrideDisabled'
        }
        elseif ($ObservedLockState -eq 'Busy' -or $ObservedLockState -eq 'StaleEvidence' -or $ObservedLockState -eq 'Unknown') {
            $scheduleDecision = 'BLOCKED_BY_LOCK'
            $scheduleReason = if ($ObservedLockState -eq 'Busy') { 'ObservedLockBusy' } elseif ($ObservedLockState -eq 'StaleEvidence') { 'ObservedStaleLockEvidence' } else { 'ObservedLockUnknown' }
        }
        elseif ([bool]$policy.Raw.ManualOverride.BypassAllowedWindow) {
            $scheduleDecision = 'READY_MANUAL'
            $scheduleReason = 'ManualOverrideReady'
        }
        else {
            $date = $evaluation.UtcDateTime.Date
            $slot = Get-ScheduleSlot -Date $date -Policy $policy -AtMinutes $policy.AtMinutes -WindowStartMinutes $policy.WindowStartMinutes -WindowEndMinutes $policy.WindowEndMinutes
            if ($evaluation -ge $slot.WindowStartUtc -and $evaluation -lt $slot.WindowEndUtc) {
                $scheduleDecision = 'READY_MANUAL'
                $scheduleReason = 'ManualOverrideReady'
            }
            else {
                $scheduleDecision = 'WAITING_FOR_WINDOW'
                $scheduleReason = 'OutsideAllowedWindow'
            }
        }
    }
    elseif (-not [bool]$policy.Raw.Enabled) {
        $scheduleDecision = 'DISABLED'
        $scheduleReason = 'ScheduleDisabled'
    }
    else {
        $date = $evaluation.UtcDateTime.Date
        $slot = Get-ScheduleSlot -Date $date -Policy $policy -AtMinutes $policy.AtMinutes -WindowStartMinutes $policy.WindowStartMinutes -WindowEndMinutes $policy.WindowEndMinutes
        $tomorrow = $date.AddDays(1)
        $nextSlot = Get-ScheduleSlot -Date $tomorrow -Policy $policy -AtMinutes $policy.AtMinutes -WindowStartMinutes $policy.WindowStartMinutes -WindowEndMinutes $policy.WindowEndMinutes
        if (-not $slot.JitterInsideWindow) {
            $scheduleDecision = 'WAITING_FOR_WINDOW'
            $scheduleReason = 'JitterOutsideWindow'
            $slot = $nextSlot
            $nextSlot = Get-ScheduleSlot -Date $tomorrow.AddDays(1) -Policy $policy -AtMinutes $policy.AtMinutes -WindowStartMinutes $policy.WindowStartMinutes -WindowEndMinutes $policy.WindowEndMinutes
        }
        elseif ($evaluation -lt $slot.ProposedStartUtc) {
            $scheduleDecision = 'WAITING_FOR_CADENCE'
            $scheduleReason = 'ScheduledSlotNotDue'
            $nextSlot = $slot
        }
        elseif ($evaluation -lt $slot.WindowEndUtc) {
            $scheduleDecision = 'READY_SCHEDULED'
            $scheduleReason = 'ScheduledRunReady'
        }
        else {
            $scheduleDecision = 'WAITING_FOR_WINDOW'
            $scheduleReason = 'OutsideAllowedWindow'
            $slot = $nextSlot
            $nextSlot = Get-ScheduleSlot -Date $tomorrow.AddDays(1) -Policy $policy -AtMinutes $policy.AtMinutes -WindowStartMinutes $policy.WindowStartMinutes -WindowEndMinutes $policy.WindowEndMinutes
        }
        if ($ObservedLockState -eq 'Busy' -or $ObservedLockState -eq 'StaleEvidence' -or $ObservedLockState -eq 'Unknown') {
            if ($scheduleDecision -eq 'READY_SCHEDULED') {
                $scheduleDecision = 'BLOCKED_BY_LOCK'
                $scheduleReason = if ($ObservedLockState -eq 'Busy') { 'ObservedLockBusy' } elseif ($ObservedLockState -eq 'StaleEvidence') { 'ObservedStaleLockEvidence' } else { 'ObservedLockUnknown' }
            }
        }
    }
}

$lockStatus = switch ($ObservedLockState) {
    'Busy' { 'Busy' }
    'StaleEvidence' { 'StaleEvidence' }
    'Unknown' { 'Unknown' }
    default { 'NotAttempted' }
}
$lockReason = switch ($ObservedLockState) {
    'Busy' { 'ObservedLockBusy' }
    'StaleEvidence' { 'ObservedStaleLockEvidence' }
    'Unknown' { 'ObservedLockUnknown' }
    default { 'ReportOnlyNoLockAcquisition' }
}

$projection = [ordered]@{
    SchemaVersion = 'scheduled-refresh-plan/v1'
    EvaluatedAtUtc = Get-UtcText -Value $evaluation
    TriggerKind = $TriggerKind
    PolicyDigest = $policy.Digest
    PolicyEnabled = [bool]$policy.Raw.Enabled
    InputValidation = [ordered]@{
        Status = if ($inputValidationErrors.Count -eq 0) { 'Valid' } else { 'Invalid' }
        Errors = @($inputValidationErrors)
    }
    InputResult = $inputProjection
    Schedule = [ordered]@{
        Decision = $scheduleDecision
        ReasonCode = $scheduleReason
        NominalDueUtc = if ($null -ne $slot) { Get-UtcText -Value $slot.NominalDueUtc } else { $null }
        WindowStartUtc = if ($null -ne $slot) { Get-UtcText -Value $slot.WindowStartUtc } else { $null }
        WindowEndUtc = if ($null -ne $slot) { Get-UtcText -Value $slot.WindowEndUtc } else { $null }
        JitterOffsetMinutes = if ($null -ne $slot) { [int]$slot.JitterOffsetMinutes } else { 0 }
        ProposedStartUtc = if ($null -ne $slot) { Get-UtcText -Value $slot.ProposedStartUtc } else { $null }
        NextDueUtc = if ($null -ne $nextSlot) { Get-UtcText -Value $nextSlot.ProposedStartUtc } else { $null }
    }
    Counts = $counts
    Notification = [ordered]@{
        Level = $notificationLevel
        SummaryCode = $summaryCode
        Items = @($notificationItems)
    }
    LockObservation = [ordered]@{
        Status = $lockStatus
        ReasonCode = $lockReason
    }
    Safety = [pscustomobject](New-Safety)
}

$reportPaths = Write-PlanReports -Projection ([pscustomobject]$projection) -ReportRoot $OutputRoot
try {
    if (-not (Test-Json -Path $reportPaths.JsonPath -SchemaFile $planSchemaPath -ErrorAction Stop)) {
        Throw-FailClosed -Code 'PlanSchemaInvalid'
    }
}
catch {
    if ($_.Exception.Message -like 'FAIL_CLOSED:*') { throw }
    Throw-FailClosed -Code 'PlanSchemaInvalid'
}
if ($inputValidationErrors.Count -gt 0) {
    Throw-FailClosed -Code ($inputValidationErrors -join ',')
}

[pscustomobject][ordered]@{
    JsonPath = $reportPaths.JsonPath
    MarkdownPath = $reportPaths.MarkdownPath
    SchemaVersion = 'scheduled-refresh-plan/v1'
    Decision = $projection.Schedule.Decision
    NotificationLevel = $projection.Notification.Level
}
