<#
.SYNOPSIS
Prints one plain-language health report for this ChannelForge folder.

.DESCRIPTION
Read-only. Uses Get-ChannelForgePreflightReport (preflight-report/v1) and shows each finding as Pass, Fail or
Unknown with a next step. Unknown is never shown as Pass. Local checks only: no network, no Plex or Dispatcharr
probes. Exit code 0 when every finding is Pass, 1 when any is Fail or Unknown.
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot,
    [string]$CacheRoot,
    [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ChannelForge\ChannelForge.psd1') -Force

function Format-ChannelForgeDoctorFinding {
    param([Parameter(Mandatory)][object]$Finding)
    $label = switch ($Finding.Status) { 'Pass' { 'PASS   ' } 'Fail' { 'FAIL   ' } default { 'UNKNOWN' } }
    $line = '[{0}] {1}: {2}' -f $label, $Finding.Check, $Finding.Observed
    if ($Finding.Status -ne 'Pass') { $line += [Environment]::NewLine + '          Next step: ' + $Finding.NextStep }
    $line
}

$arguments = @{ RepositoryRoot = $Root }
foreach ($name in 'OutputRoot', 'CacheRoot', 'BackupRoot') {
    $value = Get-Variable -Name $name -ValueOnly
    if (-not [string]::IsNullOrWhiteSpace($value)) { $arguments[$name] = $value }
}
$report = Get-ChannelForgePreflightReport @arguments

'ChannelForge Doctor (read-only; nothing was changed)'
foreach ($finding in $report.Findings) { Format-ChannelForgeDoctorFinding -Finding $finding }
$s = $report.Summary
'Result: {0} - {1} passed, {2} failed, {3} unknown. Unknown means the check could not run; it is not a pass.' -f $s.Overall.ToUpperInvariant(), $s.Pass, $s.Fail, $s.Unknown
exit $(if ($s.Overall -eq 'Pass') { 0 } else { 1 })
