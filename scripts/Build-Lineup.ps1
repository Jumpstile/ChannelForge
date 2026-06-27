param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required file: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$dataDir = Join-Path $Root "data"
$outDir = Join-Path $Root "output"
$reportDir = Join-Path $outDir "reports"
New-Item -ItemType Directory -Force -Path $outDir, $reportDir | Out-Null

$provider = Read-JsonFile (Join-Path $dataDir "providers/mybunny.json")
$epg = Read-JsonFile (Join-Path $dataDir "epg/epg_sources.json")
$locals = Read-JsonFile (Join-Path $dataDir "lineup/locals.json")
$blocks = Read-JsonFile (Join-Path $dataDir "lineup/numbering_blocks.json")

$summary = [ordered]@{
    GeneratedAt = (Get-Date).ToString("s")
    Provider = $provider.provider
    M3USources = @($provider.sources).Count
    EPGSources = @($epg.epg_sources).Count
    LocalChannels = @($locals.locals).Count
    NumberingBlocks = @($blocks.blocks).Count
    OutputM3U = "/output/merged.m3u"
    OutputXMLTV = "/output/merged.xmltv"
    Status = "SOURCE_OF_TRUTH_READY"
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reportDir "build-summary.json") -Encoding UTF8

# Generate human-readable lineup plan.
$md = @()
$md += "# ChannelForge Build Summary"
$md += ""
$md += "Generated: $($summary.GeneratedAt)"
$md += ""
$md += "## Provider M3U Sources"
foreach ($s in $provider.sources) {
    $md += "- $($s.name): $($s.url)"
}
$md += ""
$md += "## EPG Sources"
foreach ($e in ($epg.epg_sources | Sort-Object priority)) {
    $md += "- [$($e.priority)] $($e.name) - $($e.role)"
}
$md += ""
$md += "## Local Channels"
foreach ($l in ($locals.locals | Sort-Object number)) {
    $md += "- $($l.number) - $($l.display)"
}
$md += ""
$md += "## Numbering Blocks"
foreach ($b in $blocks.blocks) {
    $md += "- $($b.start)-$($b.end): $($b.category) — $($b.notes)"
}

$md -join "`n" | Set-Content -LiteralPath (Join-Path $reportDir "lineup-plan.md") -Encoding UTF8

Write-Host "ChannelForge source-of-truth build completed." -ForegroundColor Green
Write-Host "Report: $(Join-Path $reportDir 'lineup-plan.md')"
