[CmdletBinding()]
param(
    [string]$DataRoot = '/data'
)

# Container entry point: check the data folder, then run the server launcher. Prints nothing secret.
$ErrorActionPreference = 'Stop'
$config = Join-Path $DataRoot 'config'
try {
    New-Item -ItemType Directory -Force -Path $config | Out-Null
    $probe = Join-Path $config ('.write-check-' + [guid]::NewGuid().ToString('N'))
    Set-Content -LiteralPath $probe -Value 'ok'
    Remove-Item -LiteralPath $probe -Force
}
catch {
    [Console]::Error.WriteLine("ChannelForge cannot write to $config. Mount a writable folder at $DataRoot and run again.")
    exit 1
}

$launcherArgs = @{ ConfigRoot = $config; BindAddress = '0.0.0.0'; Port = 47850; StaticRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'gui/dist') }
$allowed = @($env:CHANNELFORGE_ALLOWED_HOST -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($allowed.Count -gt 0) { $launcherArgs.AllowedHost = $allowed }
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Start-ChannelForgeServer.ps1') @launcherArgs
