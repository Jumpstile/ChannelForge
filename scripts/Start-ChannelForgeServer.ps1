[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigRoot,

    [ValidateRange(1024, 65535)]
    [int]$Port = 47850,

    [ValidateNotNullOrEmpty()]
    [string]$BindAddress = '127.0.0.1',

    [string]$StaticRoot = '',

    [string[]]$AllowedHost = @()
)

# Server launcher: sign-in is always required. The server prints the one-time setup code itself.
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigRoot)) { throw 'ChannelForge needs a config folder to run as a server. Use -ConfigRoot <folder>.' }
New-Item -ItemType Directory -Force -Path $ConfigRoot | Out-Null
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/ChannelForge/ChannelForge.psd1'
Import-Module $modulePath -Force

$serverArgs = @{ Port = $Port; BindAddress = $BindAddress; ConfigRoot = $ConfigRoot; RequireSignIn = $true }
if ($StaticRoot) { $serverArgs.StaticRoot = $StaticRoot }
if (@($AllowedHost).Count -gt 0) { $serverArgs.AllowedHost = @($AllowedHost) }
Start-ChannelForgeWebServer @serverArgs
