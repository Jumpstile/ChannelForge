[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$helperPath = Join-Path $PSScriptRoot '..\src\ChannelForge\Private\Initialize-ChannelForgeScheduledOperation.ps1'
$contractPath = Join-Path $PSScriptRoot '..\src\ChannelForge\Private\Get-ChannelForgeScheduledOperationContract.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf) -or -not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { throw 'ScheduledOperationHelperMissing' }
. $helperPath
. $contractPath

$rootInfo = Resolve-ChannelForgeScheduledOperationRoot -Root $Root
Assert-ChannelForgeTaskSchedulerAvailable
$rootFull = $rootInfo.FullPath
$identity = Get-ChannelForgeScheduledOperationTaskIdentity -RootInfo $rootInfo
$registrationSchemaPath = Join-Path $rootFull 'schemas/scheduled-refresh-registration.schema.json'
$policySchemaPath = Join-Path $rootFull 'schemas/scheduled-refresh-policy.schema.json'
$registration = if (Test-Path -LiteralPath $registrationSchemaPath -PathType Leaf) { Read-ChannelForgeScheduledOperationRegistrationEvidence -Root $rootFull -SchemaPath $registrationSchemaPath } else { $null }
$record = Get-ChannelForgeScheduledOperationTaskRecord -TaskPath $identity.TaskPath -TaskName $identity.TaskName
$policyInfo = $null
$policyStatus = 'Unavailable'
try {
    $policyPath = Resolve-ChannelForgeScheduledOperationPolicyPath -Root $rootFull
    $policyInfo = Get-ChannelForgeScheduledOperationPolicyInfo -Path $policyPath -SchemaPath $policySchemaPath
    $policyStatus = if ($policyInfo.Raw.Enabled) { 'Enabled' } else { 'Disabled' }
}
catch { $policyStatus = 'Invalid' }
$runtime = Get-ChannelForgeScheduledOperationRuntime
$state = 'Missing'
$contract = $null
$failureCode = 'TaskMissing'
if ($null -ne $record) {
    if ($null -eq $record.Marker) {
        $state = 'OwnershipMismatch'
        $failureCode = 'ForeignTask'
    }
    elseif ($record.Marker.TaskName -ne $identity.TaskName -or $record.Marker.RootDigest -ne $identity.RootDigest) {
        $state = 'OwnershipMismatch'
        $failureCode = 'OwnershipMismatch'
    }
    elseif ($null -eq $registration) {
        $state = 'Drifted'
        $failureCode = 'RegistrationEvidenceMissing'
    }
    elseif ($registration.RootDigest -ne $identity.RootDigest -or $registration.TaskName -ne $identity.TaskName -or $registration.PolicyDigest -ne $record.Marker.PolicyDigest) {
        $state = 'Drifted'
        $failureCode = 'RegistrationEvidenceMismatch'
    }
    elseif ($null -eq $policyInfo) {
        $state = 'PolicyInvalid'
        $failureCode = 'PolicyInvalid'
    }
    elseif ($registration.PolicyDigest -ne $policyInfo.Digest) {
        $state = 'Drifted'
        $failureCode = 'PolicyDigestDrifted'
    }
    elseif (-not $runtime.Available) {
        $state = 'RuntimeUnavailable'
        $failureCode = $runtime.Code
    }
    else {
        $contract = Get-ChannelForgeScheduledOperationTaskContract -Xml $record.Xml -RootInfo $rootInfo -WrapperPath ([IO.Path]::GetFullPath((Join-Path $rootFull 'scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1'))) -RuntimePath $runtime.Path -PolicyInfo $policyInfo
        if (-not $contract.Compliant) {
            $state = 'Drifted'
            $failureCode = $contract.ViolationCodes -join ','
        }
        elseif ($policyStatus -eq 'Disabled') {
            $state = 'Disabled'
            $failureCode = 'PolicyDisabled'
        }
        else {
            $state = 'Installed'
            $failureCode = 'None'
        }
    }
}
$taskInfo = $null
if ($null -ne $record) {
    try { $taskInfo = Get-ScheduledTaskInfo -TaskName $identity.TaskName -TaskPath $identity.TaskPath -ErrorAction Stop } catch { }
}
[pscustomobject][ordered]@{
    Status = $state
    FailureCode = $failureCode
    TaskPath = $identity.TaskPath
    TaskName = $identity.TaskName
    RootDigest = $identity.RootDigest
    TaskPolicyDigest = if ($null -ne $record.Marker) { [string]$record.Marker.PolicyDigest } else { $null }
    RegistrationPolicyDigest = if ($null -ne $registration) { [string]$registration.PolicyDigest } else { $null }
    CurrentPolicyDigest = if ($null -ne $policyInfo) { [string]$policyInfo.Digest } else { $null }
    PolicyStatus = $policyStatus
    RuntimeStatus = if ($runtime.Available) { 'Available' } else { $runtime.Code }
    RuntimeVersion = $runtime.Version
    TaskState = if ($null -ne $record) { [string]$record.Task.State } else { $null }
    LastRunTimeUtc = if ($null -ne $taskInfo -and $null -ne $taskInfo.LastRunTime) { ([datetimeoffset]$taskInfo.LastRunTime).ToUniversalTime().ToString('o') } else { $null }
    NextRunTimeUtc = if ($null -ne $taskInfo -and $null -ne $taskInfo.NextRunTime) { ([datetimeoffset]$taskInfo.NextRunTime).ToUniversalTime().ToString('o') } else { $null }
    Contract = if ($null -ne $contract) { [pscustomobject][ordered]@{ Compliant = $contract.Compliant; ViolationCodes = @($contract.ViolationCodes); StartBoundaryUtc = $contract.StartBoundaryUtc; MultipleInstancesPolicy = $contract.MultipleInstancesPolicy; StartWhenAvailable = $contract.StartWhenAvailable; PrincipalLogonType = $contract.PrincipalLogonType; PrincipalRunLevel = $contract.PrincipalRunLevel } } else { $null }
}
