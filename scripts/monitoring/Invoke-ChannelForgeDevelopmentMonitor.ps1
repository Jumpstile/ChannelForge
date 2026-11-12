[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version 2.0

$modulePath = Join-Path $PSScriptRoot 'MonitorOutbox.psm1'
$manifestPath = Join-Path $PSScriptRoot 'channelforge-monitor-sources.json'
$configuredSpool = (Get-Item -Path Env:MONITOR_SPOOL_ROOT -ErrorAction SilentlyContinue).Value
if ([string]::IsNullOrWhiteSpace([string]$configuredSpool)) {
    $runnerTemp = (Get-Item -Path Env:RUNNER_TEMP -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace([string]$runnerTemp)) { $runnerTemp = [IO.Path]::GetTempPath() }
    $configuredSpool = Join-Path $runnerTemp 'channelforge-development-monitor-spool'
}
$spoolRoot = [IO.Path]::GetFullPath([string]$configuredSpool)

Import-Module -Name $modulePath -Force -ErrorAction Stop
[void](Initialize-MonitorOutbox -SpoolRoot $spoolRoot)
$token = [string](Get-Item -Path Env:GITHUB_TOKEN -ErrorAction SilentlyContinue).Value
$now = [DateTime]::UtcNow
$before = Invoke-MonitorOutboxReplay -SpoolRoot $spoolRoot -Token $token -NowUtc $now
$watch = Invoke-MonitorSourceWatch -MonitorId 'channelforge-ecosystem' -ManifestPath $manifestPath -SpoolRoot $spoolRoot -Token $token -NowUtc $now
$after = Invoke-MonitorOutboxReplay -SpoolRoot $spoolRoot -Token $token -NowUtc ([DateTime]::UtcNow) -DryRun:$DryRun
$pending = @(Get-MonitorOutboxItems -SpoolRoot $spoolRoot)
$errors = @($before.Errors) + @($after.Errors)
$runName = ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N') + '.json')
$receipt = [ordered]@{
    schemaVersion = 1
    monitorId = 'channelforge-ecosystem'
    repository = 'Jumpstile/ChannelForge'
    targetIssueNumber = [int]$watch.TargetIssueNumber
    githubIssue = '#' + [int]$watch.TargetIssueNumber
    observedAtUtc = [DateTime]::UtcNow.ToString('o')
    dryRun = [bool]$DryRun
    failedSources = [int]$watch.FailedSources
    replayBefore = $before
    replayAfter = $after
    pendingCount = $pending.Count
    errors = $errors
    status = if ($pending.Count -eq 0 -and $errors.Count -eq 0) { 'PASS' } else { 'HOLD' }
}
Write-MonitorAtomicText -Path (Join-Path (Join-Path $spoolRoot 'runs') $runName) -Text ($receipt | ConvertTo-Json -Depth 20)
$receipt | ConvertTo-Json -Depth 20
if (-not $DryRun -and ($pending.Count -gt 0 -or $errors.Count -gt 0)) { exit 2 }
