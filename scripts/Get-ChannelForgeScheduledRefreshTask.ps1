[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$helperPath = Join-Path $PSScriptRoot '..\src\ChannelForge\Private\Initialize-ChannelForgeScheduledOperation.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'ScheduledOperationHelperMissing' }
. $helperPath

$rootInfo = Resolve-ChannelForgeScheduledOperationRoot -Root $Root
Assert-ChannelForgeTaskSchedulerAvailable
$records = @(Get-ChannelForgeScheduledOperationOwnedTaskRecords -TaskPath '\ChannelForge\')
$items = foreach ($record in $records) {
    $taskInfo = $null
    try { $taskInfo = Get-ScheduledTaskInfo -TaskName $record.Task.TaskName -TaskPath $record.Task.TaskPath -ErrorAction Stop } catch { }
    [pscustomobject][ordered]@{
        Owner = 'ChannelForge'
        TaskPath = '\ChannelForge\'
        TaskName = [string]$record.Task.TaskName
        RootDigest = [string]$record.Marker.RootDigest
        PolicyDigest = [string]$record.Marker.PolicyDigest
        TriggerKind = 'Scheduled'
        State = [string]$record.Task.State
        LastRunTimeUtc = if ($null -ne $taskInfo -and $null -ne $taskInfo.LastRunTime) { ([datetimeoffset]$taskInfo.LastRunTime).ToUniversalTime().ToString('o') } else { $null }
        NextRunTimeUtc = if ($null -ne $taskInfo -and $null -ne $taskInfo.NextRunTime) { ([datetimeoffset]$taskInfo.NextRunTime).ToUniversalTime().ToString('o') } else { $null }
    }
}
[pscustomobject][ordered]@{
    TaskPath = '\ChannelForge\'
    OwnedTaskCount = @($items).Count
    Tasks = @($items)
}
