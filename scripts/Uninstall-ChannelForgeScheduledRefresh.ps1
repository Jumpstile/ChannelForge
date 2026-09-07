[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$Approve
)

$ErrorActionPreference = 'Stop'
$helperPath = Join-Path $PSScriptRoot '..\src\ChannelForge\Private\Initialize-ChannelForgeScheduledOperation.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'ScheduledOperationHelperMissing' }
. $helperPath

$rootInfo = Resolve-ChannelForgeScheduledOperationRoot -Root $Root
Assert-ChannelForgeTaskSchedulerAvailable
$rootFull = $rootInfo.FullPath
$identity = Get-ChannelForgeScheduledOperationTaskIdentity -RootInfo $rootInfo
$registrationSchemaPath = Join-Path $rootFull 'schemas/scheduled-refresh-registration.schema.json'
if (-not (Test-Path -LiteralPath $registrationSchemaPath -PathType Leaf)) { throw 'RequiredSchemaMissing' }
$existing = Get-ChannelForgeScheduledOperationTaskRecord -TaskPath $identity.TaskPath -TaskName $identity.TaskName
$registration = Read-ChannelForgeScheduledOperationRegistrationEvidence -Root $rootFull -SchemaPath $registrationSchemaPath
if ($null -eq $existing) {
    if ($null -ne $registration -and $registration.RootDigest -eq $identity.RootDigest) {
        Remove-Item -LiteralPath (Get-ChannelForgeScheduledOperationRegistrationPath -Root $rootFull) -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $rootFull 'output/operations/scheduled-refresh-registration.md') -Force -ErrorAction SilentlyContinue
    }
    [pscustomobject][ordered]@{ Status = 'NotInstalled'; TaskPath = $identity.TaskPath; TaskName = $identity.TaskName; RootDigest = $identity.RootDigest }
    return
}
if ($null -eq $existing.Marker) { throw 'ForeignTask' }
if ($existing.Marker.TaskName -ne $identity.TaskName -or $existing.Marker.RootDigest -ne $identity.RootDigest) { throw 'OwnershipMismatch' }
if (-not $Approve) {
    if ($null -eq $Host.UI) { throw 'ExplicitApprovalRequired' }
    $answer = Read-Host 'Type REMOVE to uninstall the ChannelForge scheduled refresh task'
    if ($answer -cne 'REMOVE') { throw 'ConsentNotGranted' }
}
Unregister-ScheduledTask -TaskName $identity.TaskName -TaskPath $identity.TaskPath -Confirm:$false -ErrorAction Stop
Remove-Item -LiteralPath (Get-ChannelForgeScheduledOperationRegistrationPath -Root $rootFull) -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $rootFull 'output/operations/scheduled-refresh-registration.md') -Force -ErrorAction SilentlyContinue
[pscustomobject][ordered]@{
    Status = 'Uninstalled'
    TaskPath = $identity.TaskPath
    TaskName = $identity.TaskName
    RootDigest = $identity.RootDigest
}
