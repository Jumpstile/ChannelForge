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

# Path-safety guardrail: build reports and the merged playlist may only
# land inside the project's own output/ folder (a disposable artifact area
# per ADR 0001), never wherever $Root happens to resolve to.
Assert-ChannelForgeWritePath -Path $outDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $reportDir -AllowedRoot $outDir
New-Item -ItemType Directory -Force -Path $outDir, $reportDir | Out-Null

$provider = Read-JsonFile (Join-Path $dataDir "providers/mybunny.json")
$epg = Read-JsonFile (Join-Path $dataDir "epg/epg_sources.json")
$locals = Read-JsonFile (Join-Path $dataDir "lineup/locals.json")
$blocks = Read-JsonFile (Join-Path $dataDir "lineup/numbering_blocks.json")
$aliasPath = Join-Path $dataDir "rules/aliases.json"
$numberingBlocksPath = Join-Path $dataDir "lineup/numbering_blocks.json"

$summaryPath = Join-Path $reportDir "build-summary.json"
$planPath = Join-Path $reportDir "lineup-plan.md"
Assert-ChannelForgeWritePath -Path $summaryPath -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $planPath -AllowedRoot $outDir

# M3U generation (issue #7 Phase 1): only sources that are enabled AND have
# a local_playlist configured participate. There is no HTTP fetch yet, so a
# source with no local_playlist is skipped, not an error - this is the
# documented Phase 1 boundary, not a silent gap.
$playlistSources = @($provider.sources | Where-Object { $_.enabled -and $_.local_playlist })

$m3uGenerated = $false
$m3uRelativePath = $null
$m3uHash = $null
$channelCount = 0
$duplicateCount = 0
$warningCount = 0

if ($playlistSources.Count -gt 0) {
    $mergeSource = @($playlistSources | ForEach-Object {
        [pscustomobject]@{
            Path     = Join-Path $Root $_.local_playlist
            Provider = $provider.provider
            Playlist = $_.name
        }
    })

    $mergeResult = Merge-ChannelForgeLineup -Source $mergeSource -AliasPath $aliasPath -NumberingBlocksPath $numberingBlocksPath

    $m3uPath = Join-Path $outDir "merged.m3u"
    Assert-ChannelForgeWritePath -Path $m3uPath -AllowedRoot $outDir
    $mergeResult.Channels | Export-ChannelForgeM3UPlaylist -Path $m3uPath

    $m3uGenerated = $true
    $m3uRelativePath = "output/merged.m3u"
    $m3uHash = (Get-FileHash -LiteralPath $m3uPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $channelCount = $mergeResult.Channels.Count
    $duplicateCount = $mergeResult.DuplicateCount
    $warningCount = $mergeResult.WarningCount
}

# XMLTV generation is explicitly deferred, not silently dropped: there is no
# programme/guide data source anywhere in the repo today (BuildContext's
# Programmes collection is an unused placeholder). Generating XMLTV without
# real programme data would mean fabricating content, which the project's
# evidence-over-assumptions principle (ADR 0005) does not allow.
$xmltvDeferredReason = "No programme/EPG guide data source exists yet; generating XMLTV without real programme data would be fabricated content. Deferred until an EPG fetch path exists (see issue #7 follow-up)."

$summary = [ordered]@{
    GeneratedAt         = (Get-Date).ToString("s")
    Provider            = $provider.provider
    M3USources          = @($provider.sources).Count
    EPGSources          = @($epg.epg_sources).Count
    LocalChannels       = @($locals.locals).Count
    NumberingBlocks     = @($blocks.blocks).Count
    M3UGenerated        = $m3uGenerated
    M3UPath             = $m3uRelativePath
    M3USha256           = $m3uHash
    ChannelCount        = $channelCount
    DuplicateCount      = $duplicateCount
    WarningCount        = $warningCount
    XMLTVGenerated      = $false
    XMLTVDeferredReason = $xmltvDeferredReason
    Status              = if ($m3uGenerated) { "M3U_GENERATED" } else { "SOURCE_OF_TRUTH_VALIDATED" }
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

# Generate human-readable lineup plan.
# Provider/EPG/stream URLs are treated as secrets (see docs/reference/SECURITY.md)
# and must never appear in generated reports. List source/channel names and
# state only; never include $s.url, $e.url, or $channel.Url here. Never
# include $Root or any other absolute/local-only path either - only the
# project-relative $m3uRelativePath.
$md = @()
$md += "# ChannelForge Build Summary"
$md += ""
$md += "Generated: $($summary.GeneratedAt)"
$md += ""

if ($m3uGenerated) {
    $md += "Merged M3U: $m3uRelativePath ($channelCount channels, $duplicateCount duplicates excluded, $warningCount warnings, SHA-256 $m3uHash)"
}
else {
    $md += "Merged M3U: not generated. No provider source has a local_playlist configured yet (HTTP fetch is deferred; see issue #7)."
}
$md += ""
$md += "Known limitations:"
$md += "- XMLTV output: deferred. $xmltvDeferredReason"
$md += "- Live HTTP provider/EPG fetch: deferred. Only local_playlist files are read in this phase."
$md += "- Plex EPG/guide binding: deferred until XMLTV exists. Plex can still play a merged M3U's channels; it will have no guide data."
$md += ""
$md += "## Provider M3U Sources"
foreach ($s in $provider.sources) {
    $state = if ($s.enabled) { 'enabled' } else { 'disabled' }
    $playlistState = if ($s.local_playlist) { 'local playlist configured' } else { 'no local playlist' }
    $md += "- $($s.name) ($state, $playlistState)"
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

Write-Host "ChannelForge build completed." -ForegroundColor Green
Write-Host "Report: $planPath"
