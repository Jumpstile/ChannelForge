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

$provider = Get-Content (Join-Path $Root "data/providers/mybunny.json") -Raw | ConvertFrom-Json
$epg = Get-Content (Join-Path $Root "data/epg/epg_sources.json") -Raw | ConvertFrom-Json
$locals = Get-Content (Join-Path $Root "data/lineup/locals.json") -Raw | ConvertFrom-Json

if (@($provider.sources).Count -lt 1) { throw "No M3U sources defined." }
if (@($epg.epg_sources).Count -lt 1) { throw "No EPG sources defined." }
if (@($locals.locals).Count -ne 14) { throw "Expected 14 local channels, found $(@($locals.locals).Count)." }

$badUrls = @()
foreach ($s in $provider.sources) {
    if ($s.url -notmatch '^https://') { $badUrls += $s.url }
}
foreach ($e in $epg.epg_sources) {
    if ($e.url -notmatch '^https://') { $badUrls += $e.url }
}
if ($badUrls.Count -gt 0) {
    throw "Found non-HTTPS URLs: $($badUrls -join ', ')"
}

Write-Host "Validation passed." -ForegroundColor Green
Write-Host "M3U sources: $(@($provider.sources).Count)"
Write-Host "EPG sources: $(@($epg.epg_sources).Count)"
Write-Host "Locals: $(@($locals.locals).Count)"
