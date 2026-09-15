[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,

    [ValidateSet('127.0.0.1', '[::1]')]
    [string]$BindAddress = '127.0.0.1'
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ChannelForge\ChannelForge.psd1'
Import-Module $modulePath -Force

Start-ChannelForgeWebServer @PSBoundParameters
