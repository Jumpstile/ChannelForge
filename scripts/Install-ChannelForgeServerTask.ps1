[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 47850,

    [ValidateNotNullOrEmpty()]
    [string]$BindAddress = '127.0.0.1',

    [string]$AllowedHost = '',

    [string]$DataRoot = (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ChannelForge')
)

# Runs the ChannelForge server at Windows start-up as a scheduled task (LOCAL SERVICE).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$private = Join-Path $root 'src\ChannelForge\Private'
foreach ($name in 'Test-ChannelForgeElevated', 'Read-ChannelForgeAdminPasswordFile', 'Get-ChannelForgeStartGuard', 'Initialize-ChannelForgeServerTask') {
    . (Join-Path $private ($name + '.ps1'))
}
Install-ChannelForgeServerTask -Root $root -Port $Port -BindAddress $BindAddress -AllowedHost $AllowedHost -DataRoot $DataRoot -WhatIf:$WhatIfPreference
