<#
.SYNOPSIS
Prints one plain-language health report for this ChannelForge folder.

.DESCRIPTION
Read-only. Uses Get-ChannelForgePreflightReport (preflight-report/v1) and shows each finding as Pass, Fail or
Unknown with a next step. Unknown is never shown as Pass. It also tests each enabled source: remote sources get one small bounded
request through the pinned HTTPS transport (the only network use, and only when you run this script); local
files are checked for existence and readability. No Plex or Dispatcharr probes. Exit code 0 when every finding is Pass, 1 when any is Fail or Unknown.
#>
[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot,
    [string]$CacheRoot,
    [string]$BackupRoot,
    [string]$ProviderConfigPath,
    [string]$EpgConfigPath
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

foreach ($pair in @(@('ProviderConfigPath', 'data/providers/provider'), @('EpgConfigPath', 'data/epg/epg_sources'))) {
    if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $pair[0] -ValueOnly))) {
        $path = Join-Path $Root ($pair[1] + '.local.json')
        if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path $Root ($pair[1] + '.example.json') }
        Set-Variable -Name $pair[0] -Value $path
    }
}
$sourceFindings = & (Get-Module ChannelForge) { param($r, $p, $e) Get-ChannelForgeSourceReachabilityFindings -RepositoryRoot $r -ProviderConfigPath $p -EpgConfigPath $e } ([IO.Path]::GetFullPath($Root)) $ProviderConfigPath $EpgConfigPath
$findings = @($report.Findings) + @($sourceFindings)
$pass = @($findings | Where-Object Status -eq 'Pass').Count
$fail = @($findings | Where-Object Status -eq 'Fail').Count
$unknown = @($findings | Where-Object Status -eq 'Unknown').Count
$overall = if ($fail -gt 0) { 'Fail' } elseif ($unknown -gt 0) { 'Unknown' } else { 'Pass' }

'ChannelForge Doctor (nothing was changed; enabled remote sources get one small request)'
foreach ($finding in $findings) { Format-ChannelForgeDoctorFinding -Finding $finding }
'Result: {0} - {1} passed, {2} failed, {3} unknown. Unknown means the check could not run; it is not a pass.' -f $overall.ToUpperInvariant(), $pass, $fail, $unknown
exit $(if ($overall -eq 'Pass') { 0 } else { 1 })
