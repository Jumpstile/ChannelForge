[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DataRoot = (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'ChannelForge'),

    [switch]$RemoveData,

    [switch]$Force
)

# Removes the start-up task and what the install added. Keeps the data folder unless -RemoveData is given.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$private = Join-Path $root 'src\ChannelForge\Private'
foreach ($name in 'Test-ChannelForgeElevated', 'Initialize-ChannelForgeServerTask') {
    . (Join-Path $private ($name + '.ps1'))
}
Uninstall-ChannelForgeServerTask -DataRoot $DataRoot -RemoveData:$RemoveData -Force:$Force -WhatIf:$WhatIfPreference
