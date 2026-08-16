param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$required = @(
    "data/providers/mybunny.json",
    "data/epg/epg_sources.json",
    "data/lineup/locals.json",
    "data/lineup/numbering_blocks.json",
    "data/lineup/categories.json",
    "data/rules/aliases.json"
)

foreach ($rel in $required) {
    $path = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required file: $rel"
    }
}

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'src\ChannelForge\ChannelForge.psd1') -Force

$provider = Get-Content (Join-Path $Root "data/providers/mybunny.json") -Raw | ConvertFrom-Json
$epgPath = Join-Path $Root "data/epg/epg_sources.json"
$epg = Get-Content $epgPath -Raw | ConvertFrom-Json
$locals = Get-Content (Join-Path $Root "data/lineup/locals.json") -Raw | ConvertFrom-Json

if (@($provider.sources).Count -lt 1) { throw "No M3U sources defined." }
if (@($epg.epg_sources).Count -lt 1) { throw "No EPG sources defined." }
if (@($locals.locals).Count -ne 14) { throw "Expected 14 local channels, found $(@($locals.locals).Count)." }

$badProviderUrlCount = @($provider.sources | Where-Object { $_.url -notmatch '^https://' }).Count
if ($badProviderUrlCount -gt 0) {
    throw "Found $badProviderUrlCount provider URL configuration error(s); expected HTTPS URLs."
}

# Read-ChannelForgeEpgSource validates the existing local/remote schema
# boundary, including exactly one path or URL, XMLTV format defaulting, and
# acceptable HTTPS URL shape. It validates URL structure only and never
# dereferences a network source.
$epgSources = @(Read-ChannelForgeEpgSource -Path $epgPath)
$localEpgCount = 0
$remoteEpgCount = 0

foreach ($source in $epgSources) {
    if (-not [string]::IsNullOrWhiteSpace([string]$source.Url)) {
        $remoteEpgCount++
        continue
    }

    if ([string]::IsNullOrWhiteSpace([string]$source.ConfiguredPath) -or
        [string]::IsNullOrWhiteSpace([string]$source.Path) -or
        -not $source.Supported -or
        [string]$source.ConfiguredPath -match '^[a-z][a-z0-9+.-]*://') {
        throw "EPG source '$($source.Name)' is not a valid local XMLTV path configuration."
    }

    $localEpgCount++
}

Write-Host "Validation passed." -ForegroundColor Green
Write-Host "M3U sources: $(@($provider.sources).Count)"
Write-Host "EPG sources: $(@($epg.epg_sources).Count)"
Write-Host "EPG local sources: $localEpgCount"
Write-Host "EPG remote sources: $remoteEpgCount"
Write-Host "Locals: $(@($locals.locals).Count)"