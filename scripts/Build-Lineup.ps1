param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

# Always load the module from this script's own location, never from -Root
# (which a caller may point at a different data/output location, e.g. in
# tests). Mixing the two would mean tests cannot point -Root at fixture
# data without also faking a copy of the module.
$ModuleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ModuleRoot 'src\ChannelForge\ChannelForge.psd1') -Force

function Read-JsonFile {
    param([string]$Path)
    Assert-ChannelForgePathExists -Path $Path -PathType Leaf -Description 'Required source file'
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$dataDir = Join-Path $Root "data"
$outDir = Join-Path $Root "output"
$reportDir = Join-Path $outDir "reports"

# Path-safety guardrail: build reports may only land inside the project's
# own output/ folder (a disposable artifact area per ADR 0001), never
# wherever $Root happens to resolve to.
Assert-ChannelForgeWritePath -Path $outDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $reportDir -AllowedRoot $outDir
New-Item -ItemType Directory -Force -Path $outDir, $reportDir | Out-Null

$provider = Read-JsonFile (Join-Path $dataDir "providers/mybunny.json")
$epg = Read-JsonFile (Join-Path $dataDir "epg/epg_sources.json")
$locals = Read-JsonFile (Join-Path $dataDir "lineup/locals.json")
$blocks = Read-JsonFile (Join-Path $dataDir "lineup/numbering_blocks.json")

$summaryPath = Join-Path $reportDir "build-summary.json"
$planPath = Join-Path $reportDir "lineup-plan.md"
Assert-ChannelForgeWritePath -Path $summaryPath -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $planPath -AllowedRoot $outDir

# M3U/XMLTV output generation is not implemented yet (see issue #7). The
# report below describes the validated source-of-truth configuration only
# and must not claim output files exist that this script never writes.
$summary = [ordered]@{
    GeneratedAt     = (Get-Date).ToString("s")
    Provider        = $provider.provider
    M3USources      = @($provider.sources).Count
    EPGSources      = @($epg.epg_sources).Count
    LocalChannels   = @($locals.locals).Count
    NumberingBlocks = @($blocks.blocks).Count
    M3UGenerated    = $false
    XMLTVGenerated  = $false
    Status          = "SOURCE_OF_TRUTH_VALIDATED"
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

# Generate human-readable lineup plan.
$md = @()
$md += "# ChannelForge Build Summary"
$md += ""
$md += "Generated: $($summary.GeneratedAt)"
$md += ""
$md += "This report describes the current source-of-truth configuration only. M3U and XMLTV output generation is not implemented yet (see issue #7)."
$md += ""
# Provider/EPG source URLs are treated as secrets (see docs/reference/SECURITY.md)
# and must never appear in generated reports. List source names and state
# only; never include $s.url or $e.url here.
$md += "## Provider M3U Sources"
foreach ($s in $provider.sources) {
    $state = if ($s.enabled) { 'enabled' } else { 'disabled' }
    $md += "- $($s.name) ($state)"
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
    $md += "- $($b.start)-$($b.end): $($b.category) - $($b.notes)"
}

$md -join "`n" | Set-Content -LiteralPath $planPath -Encoding UTF8

Write-Host "ChannelForge source-of-truth build completed." -ForegroundColor Green
Write-Host "Report: $planPath"
