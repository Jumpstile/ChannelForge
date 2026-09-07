[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$PolicyPath,
    [switch]$Approve
)

$ErrorActionPreference = 'Stop'
$helperPath = Join-Path $PSScriptRoot '..\src\ChannelForge\Private\Initialize-ChannelForgeScheduledOperation.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'ScheduledOperationHelperMissing' }
. $helperPath

$rootInfo = Resolve-ChannelForgeScheduledOperationRoot -Root $Root
$rootFull = $rootInfo.FullPath
Assert-ChannelForgeTaskSchedulerAvailable
$schemaRoot = Join-Path $rootFull 'schemas'
$policySchemaPath = Join-Path $schemaRoot 'scheduled-refresh-policy.schema.json'
$registrationSchemaPath = Join-Path $schemaRoot 'scheduled-refresh-registration.schema.json'
if (-not (Test-Path -LiteralPath $policySchemaPath -PathType Leaf) -or -not (Test-Path -LiteralPath $registrationSchemaPath -PathType Leaf)) { throw 'RequiredSchemaMissing' }
$policyFile = Resolve-ChannelForgeScheduledOperationPolicyPath -Root $rootFull -Path $PolicyPath
$configRoot = [IO.Path]::GetFullPath((Join-Path $rootFull 'config')).TrimEnd('\')
$policyFull = [IO.Path]::GetFullPath($policyFile)
if ($policyFull -ne $configRoot -and -not $policyFull.StartsWith($configRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'PolicyPathUnsafe' }
$policyInfo = Get-ChannelForgeScheduledOperationPolicyInfo -Path $policyFile -SchemaPath $policySchemaPath
if (-not [bool]$policyInfo.Raw.Enabled) { throw 'PolicyDisabled' }
$runtime = Get-ChannelForgeScheduledOperationRuntime
if (-not $runtime.Available) { throw [string]$runtime.Code }
$identity = Get-ChannelForgeScheduledOperationTaskIdentity -RootInfo $rootInfo
$wrapperPath = [IO.Path]::GetFullPath((Join-Path $rootFull 'scripts/Invoke-ChannelForgeScheduledRefreshRun.ps1'))
if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) { throw 'ScheduledRefreshWrapperMissing' }

$existing = Get-ChannelForgeScheduledOperationTaskRecord -TaskPath $identity.TaskPath -TaskName $identity.TaskName
if ($null -ne $existing) {
    if ($null -eq $existing.Marker) { throw 'ForeignTask' }
    if ($existing.Marker.TaskName -ne $identity.TaskName -or $existing.Marker.RootDigest -ne $identity.RootDigest) { throw 'OwnershipMismatch' }
}

if (-not $Approve) {
    if ($null -eq $Host.UI) { throw 'ExplicitApprovalRequired' }
    $answer = Read-Host 'Type ENABLE to install or update the ChannelForge scheduled refresh task'
    if ($answer -cne 'ENABLE') { throw 'ConsentNotGranted' }
}

$now = [datetimeoffset]::UtcNow
$startBoundary = [datetimeoffset]::new($now.UtcDateTime.Date.AddMinutes($policyInfo.AtMinutes), [timespan]::Zero)
if ($startBoundary -le $now) { $startBoundary = $startBoundary.AddDays(1) }
$xml = New-ChannelForgeScheduledOperationTaskXml -Identity $identity -RootInfo $rootInfo -PolicyInfo $policyInfo -RuntimePath $runtime.Path -WrapperPath $wrapperPath -StartBoundaryUtc $startBoundary
$definitionDigest = Get-ChannelForgeScheduledOperationSha256Hex -Value $xml
$executionLimitMinutes = [Math]::Max(1, [int]$policyInfo.Raw.JitterMinutes + [int]$policyInfo.Raw.MaxRunDurationMinutes + 1)
if ($null -eq $existing) {
    Register-ScheduledTask -TaskName $identity.TaskName -TaskPath $identity.TaskPath -Xml $xml -ErrorAction Stop | Out-Null
    $operation = 'Installed'
}
else {
    Register-ScheduledTask -TaskName $identity.TaskName -TaskPath $identity.TaskPath -Xml $xml -Force -ErrorAction Stop | Out-Null
    $operation = 'Updated'
}
$evidence = Write-ChannelForgeScheduledOperationRegistrationEvidence -Identity $identity -PolicyInfo $policyInfo -TaskDefinitionDigest $definitionDigest -RegisteredAtUtc $now -StartBoundaryUtc $startBoundary -RuntimeVersion $runtime.Version -ExecutionTimeLimitMinutes $executionLimitMinutes -SchemaPath $registrationSchemaPath -Root $rootFull
[pscustomobject][ordered]@{
    Status = $operation
    TaskPath = $identity.TaskPath
    TaskName = $identity.TaskName
    RootDigest = $identity.RootDigest
    PolicyDigest = $policyInfo.Digest
    RegisteredAtUtc = $evidence.RegisteredAtUtc
}
