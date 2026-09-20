[CmdletBinding()]
param([string]$InstallRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd([char]92, [char]47)
$pidPath = Join-Path $root 'state/runtime/server.pid'
if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) { Write-Output 'ChannelForge is not running.'; exit 0 }
$pidValue = 0
[int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$pidValue) | Out-Null
if ($pidValue -gt 0) {
    try { Stop-Process -Id $pidValue -Force -ErrorAction Stop } catch [Microsoft.PowerShell.Commands.ProcessCommandException] { }
}
Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
Write-Output 'ChannelForge stopped.'
