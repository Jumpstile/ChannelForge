param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    # Explicit override for the provider config file (issue #20). Resolved
    # relative to data/providers/ and confined there - see
    # Resolve-ChannelForgeProviderConfigPath. Highest precedence: when set,
    # it bypasses *.local.json auto-discovery (and any ambiguity in it)
    # entirely.
    [string]$ProviderPath
)

$ErrorActionPreference = "Stop"

# Always load the module from this script's own location, never from -Root.
$ModuleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ModuleRoot 'src\ChannelForge\ChannelForge.psd1') -Force

function Read-JsonFile {
    param([string]$Path)
    Assert-ChannelForgePathExists -Path $Path -PathType Leaf -Description 'Required source file'
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-SafeReportText {
    param([object]$Value)

    $text = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    if ($text -match '(?i)(https?://|ftp://|file://|[a-z]:[\\/]|^\\\\|ACCOUNT_ID|API_TOKEN|PASSWORD|TOKEN|SECRET)') {
        return '[redacted]'
    }

    return $text
}

function Compare-ChannelForgeBuildText {
    param(
        [AllowNull()]
        [object]$Left,

        [AllowNull()]
        [object]$Right
    )

    $leftText = if ($null -eq $Left) { '' } else { [string]$Left }
    $rightText = if ($null -eq $Right) { '' } else { [string]$Right }

    return [System.StringComparer]::Ordinal.Compare($leftText, $rightText)
}

$dataDir = Join-Path $Root "data"
$outDir = Join-Path $Root "output"
$reportDir = Join-Path $outDir "reports"
$playlistDir = Join-Path $dataDir "playlists"
$epgConfigPath = Join-Path $dataDir "epg/epg_sources.json"

# Path-safety guardrail: generated artifacts may only land inside output/.
Assert-ChannelForgeWritePath -Path $outDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $reportDir -AllowedRoot $outDir
New-Item -ItemType Directory -Force -Path $outDir, $reportDir | Out-Null

$xmltvPath = Join-Path $outDir 'merged.xml'
$xmltvTempPath = Join-Path $outDir 'merged.xml.tmp'
$xmltvRollbackDir = Join-Path $outDir 'xmltv-rollback'
$xmltvRollbackPath = Join-Path $xmltvRollbackDir 'merged.xml.previous'
$xmltvRollbackRelativePath = 'output/xmltv-rollback/merged.xml.previous'
Assert-ChannelForgeWritePath -Path $xmltvPath -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $xmltvTempPath -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $xmltvRollbackDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $xmltvRollbackPath -AllowedRoot $outDir
$xmltvPreviousOutputPresent = Test-Path -LiteralPath $xmltvPath -PathType Leaf
$xmltvPreviousOutputPreserved = $false

if (Test-Path -LiteralPath $xmltvTempPath -PathType Leaf) {
    try {
        Remove-Item -LiteralPath $xmltvTempPath -Force -ErrorAction Stop
    }
    catch {
        throw 'Previous XMLTV staging output could not be cleared safely.'
    }
}

# output/merged.xml is the current-build publication contract. Quarantine any
# prior public artifact before this run reads configuration or attempts a new
# publication. The quarantine slot is disposable rollback evidence only; it
# is never used as input, cache, source snapshot, or current output.
if ($xmltvPreviousOutputPresent) {
    try {
        New-Item -ItemType Directory -Force -Path $xmltvRollbackDir | Out-Null
        if (Test-Path -LiteralPath $xmltvRollbackPath -PathType Leaf) {
            [System.IO.File]::Replace($xmltvPath, $xmltvRollbackPath, $null)
        }
        else {
            [System.IO.File]::Move($xmltvPath, $xmltvRollbackPath)
        }

        if (Test-Path -LiteralPath $xmltvPath -PathType Leaf) {
            throw 'Public XMLTV publication path remained after quarantine.'
        }

        $xmltvPreviousOutputPreserved = $true
    }
    catch {
        throw 'Previous XMLTV publication could not be quarantined safely.'
    }
}

$providersDir = Join-Path $dataDir "providers"
$resolvedProviderPath = Resolve-ChannelForgeProviderConfigPath `
    -ProviderDirectory $providersDir `
    -TrackedFileName 'mybunny.json' `
    -OverridePath $ProviderPath

# Provider and EPG source files go through their centralized readers so URL
# trust-boundary validation remains in one place. URL values are never written
# to reports or included in build decisions beyond being classified as remote.
$providerSources = @(Read-ChannelForgeProvider -Path $resolvedProviderPath)
$providerConfig = Read-JsonFile $resolvedProviderPath
$epgSources = @(Read-ChannelForgeEpgSource -Path $epgConfigPath)
$locals = Read-JsonFile (Join-Path $dataDir "lineup/locals.json")
$blocks = Read-JsonFile (Join-Path $dataDir "lineup/numbering_blocks.json")
$aliasPath = Join-Path $dataDir "rules/aliases.json"
$numberingBlocksPath = Join-Path $dataDir "lineup/numbering_blocks.json"

$summaryPath = Join-Path $reportDir "build-summary.json"
$planPath = Join-Path $reportDir "lineup-plan.md"
Assert-ChannelForgeWritePath -Path $summaryPath -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $planPath -AllowedRoot $outDir

# M3U generation remains unchanged in scope: only enabled sources with a
# local_playlist participate. Remote provider acquisition is not attempted.
$playlistSources = @($providerSources | Where-Object { $_.Enabled -and $_.LocalPlaylist })
$m3uGenerated = $false
$m3uRelativePath = $null
$m3uHash = $null
$channelCount = 0
$duplicateCount = 0
$warningCount = 0

if ($playlistSources.Count -gt 0) {
    $mergeSource = @($playlistSources | ForEach-Object {
        $resolvedPlaylistPath = Join-Path $Root $_.LocalPlaylist
        Assert-ChannelForgeReadPath -Path $resolvedPlaylistPath -AllowedRoot $playlistDir

        [pscustomobject]@{
            Path     = $resolvedPlaylistPath
            Provider = $providerConfig.provider
            Playlist = $_.Name
        }
    })

    $mergeResult = Merge-ChannelForgeLineup `
        -Source $mergeSource `
        -AliasPath $aliasPath `
        -NumberingBlocksPath $numberingBlocksPath

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

$xmltvStatus = 'NOT_CONFIGURED'
$xmltvGenerated = $false
$xmltvRelativePath = $null
$xmltvHash = $null
$xmltvDeferredReason = $null
$xmltvFailureReason = $null
$xmltvSourceCount = 0
$xmltvRemoteSourceCount = @($epgSources | Where-Object {
    $_.Enabled -and -not [string]::IsNullOrWhiteSpace([string]$_.Url)
}).Count
$xmltvDisabledSourceCount = @($epgSources | Where-Object { -not $_.Enabled }).Count
$xmltvProgrammeCount = 0
$xmltvBindingCount = 0
$xmltvDuplicateGroupCount = 0
$xmltvConflictCount = 0

# Keep the raw configured path separately from the resolved access path. A
# rooted path is deliberately excluded from the ordering key: machine-local
# paths may be used to open a file, but never influence artifacts, warnings,
# identifiers, or decisions.
$xmltvSourceRecords = [System.Collections.Generic.List[object]]::new()
$sourceEnumerationIndex = 0
foreach ($source in $epgSources) {
    $sourceProperties = @($source.PSObject.Properties.Name)
    $configuredPath = if ($sourceProperties -contains 'ConfiguredPath') {
        [string]$source.ConfiguredPath
    }
    else {
        ''
    }

    if ($source.Enabled -and $source.Supported -and
        [string]::Equals([string]$source.Format, 'xmltv', [System.StringComparison]::Ordinal) -and
        [string]::IsNullOrWhiteSpace([string]$source.Url) -and
        -not [string]::IsNullOrWhiteSpace([string]$source.Path)) {
        $pathKey = if ([System.IO.Path]::IsPathRooted($configuredPath.Trim())) {
            ''
        }
        else {
            $configuredPath.Trim()
        }

        $xmltvSourceRecords.Add([pscustomobject]@{
            Source         = $source
            Priority       = [int]$source.Priority
            Name           = [string]$source.Name
            ConfiguredPath = $pathKey
            InputIndex     = $sourceEnumerationIndex
        })
    }

    $sourceEnumerationIndex++
}

$xmltvSourceRecords.Sort([System.Comparison[object]]{
    param($left, $right)

    $comparison = if ($left.Priority -lt $right.Priority) { -1 } elseif ($left.Priority -gt $right.Priority) { 1 } else { 0 }
    if ($comparison -ne 0) { return $comparison }

    $comparison = Compare-ChannelForgeBuildText -Left $left.Name -Right $right.Name
    if ($comparison -ne 0) { return $comparison }

    $comparison = Compare-ChannelForgeBuildText -Left $left.ConfiguredPath -Right $right.ConfiguredPath
    if ($comparison -ne 0) { return $comparison }

    if ($left.InputIndex -lt $right.InputIndex) { return -1 }
    if ($left.InputIndex -gt $right.InputIndex) { return 1 }
    return 0
})

$localXmltvSources = @($xmltvSourceRecords | ForEach-Object { $_.Source })
$xmltvSourceCount = $localXmltvSources.Count

if ($xmltvSourceCount -eq 0) {
    if ($xmltvRemoteSourceCount -gt 0) {
        $xmltvStatus = 'DEFERRED_REMOTE_ONLY'
        $xmltvDeferredReason = 'Remote XMLTV acquisition is deferred; no local XMLTV source was processed.'
    }
    else {
        $xmltvStatus = 'NOT_CONFIGURED'
        $xmltvDeferredReason = 'No enabled local XMLTV source is configured.'
    }
}
else {
    $xmltvFailureStage = 'import'
    try {
        $allProgrammes = [System.Collections.Generic.List[object]]::new()

        foreach ($source in $localXmltvSources) {
            $sourceProgrammes = @(Import-ChannelForgeConfiguredXmltvSource -Source $source)
            foreach ($programme in $sourceProgrammes) {
                [void]$allProgrammes.Add($programme)
            }
        }

        if ($allProgrammes.Count -eq 0) {
            throw 'No XMLTV programmes were imported.'
        }

        $xmltvFailureStage = 'merge'
        $xmltvMergeResult = Merge-ChannelForgeXmltvProgrammes -Programme @($allProgrammes.ToArray())
        $xmltvProgrammeCount = @($xmltvMergeResult.BoundProgrammes).Count
        $xmltvBindingCount = @($xmltvMergeResult.Bindings).Count
        $xmltvDuplicateGroupCount = @($xmltvMergeResult.Duplicates).Count
        $xmltvConflictCount = @($xmltvMergeResult.Conflicts).Count

        if ($xmltvMergeResult.HasConflicts -or $xmltvConflictCount -gt 0) {
            throw 'XMLTV merge contains conflicts or NeedsReview records.'
        }

        $xmltvFailureStage = 'export'
        Export-ChannelForgeXmltv `
            -MergeResult $xmltvMergeResult `
            -Path $xmltvTempPath `
            -AllowedRoot $outDir

        if (-not (Test-Path -LiteralPath $xmltvTempPath -PathType Leaf)) {
            throw 'XMLTV exporter did not produce the staged output.'
        }

        $xmltvHash = (Get-FileHash -LiteralPath $xmltvTempPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $xmltvFailureStage = 'publish'
        if (Test-Path -LiteralPath $xmltvPath -PathType Leaf) {
            throw 'Public XMLTV publication path was recreated before promotion.'
        }
        [System.IO.File]::Move($xmltvTempPath, $xmltvPath)

        $xmltvStatus = 'GENERATED'
        $xmltvGenerated = $true
        $xmltvRelativePath = 'output/merged.xml'
    }
    catch {
        $xmltvStatus = 'FAILED'
        $xmltvGenerated = $false
        $xmltvRelativePath = $null
        $xmltvHash = $null
        $xmltvFailureReason = switch ($xmltvFailureStage) {
            'import'  { 'Configured local XMLTV input could not be imported.'; break }
            'merge'   { 'Imported XMLTV programmes could not be merged deterministically.'; break }
            'export'  { 'Merged XMLTV programmes could not be serialized.'; break }
            'publish' { 'XMLTV output could not be promoted safely.'; break }
            default   { 'Local XMLTV build processing failed.'; break }
        }
    }
    finally {
        if (Test-Path -LiteralPath $xmltvTempPath -PathType Leaf) {
            Remove-Item -LiteralPath $xmltvTempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

$overallStatus = if ($xmltvStatus -eq 'FAILED') {
    'FAILED'
}
elseif ($m3uGenerated -and $xmltvGenerated) {
    'M3U_XMLTV_GENERATED'
}
elseif ($m3uGenerated) {
    'M3U_GENERATED'
}
elseif ($xmltvGenerated) {
    'XMLTV_GENERATED'
}
else {
    'SOURCE_OF_TRUTH_VALIDATED'
}

$summary = [ordered]@{
    GeneratedAt                    = (Get-Date).ToString("s")
    Provider                       = Get-SafeReportText $providerConfig.provider
    M3USources                     = $providerSources.Count
    EPGSources                     = $epgSources.Count
    LocalChannels                  = @($locals.locals).Count
    NumberingBlocks                = @($blocks.blocks).Count
    M3UGenerated                   = $m3uGenerated
    M3UPath                        = $m3uRelativePath
    M3USha256                      = $m3uHash
    ChannelCount                   = $channelCount
    DuplicateCount                = $duplicateCount
    WarningCount                   = $warningCount
    XMLTVStatus                    = $xmltvStatus
    XMLTVGenerated                 = $xmltvGenerated
    XMLTVPath                      = $xmltvRelativePath
    XMLTVSha256                    = $xmltvHash
    XMLTVSourceCount               = $xmltvSourceCount
    XMLTVRemoteSourceCount         = $xmltvRemoteSourceCount
    XMLTVDisabledSourceCount       = $xmltvDisabledSourceCount
    XMLTVProgrammeCount            = $xmltvProgrammeCount
    XMLTVBindingCount              = $xmltvBindingCount
    XMLTVDuplicateGroupCount       = $xmltvDuplicateGroupCount
    XMLTVConflictCount             = $xmltvConflictCount
    XMLTVDeferredReason            = $xmltvDeferredReason
    XMLTVFailureReason             = $xmltvFailureReason
    XMLTVPreviousOutputPresent     = $xmltvPreviousOutputPresent
    XMLTVPreviousOutputPreserved   = $xmltvPreviousOutputPreserved
    XMLTVRollbackPath               = if ($xmltvPreviousOutputPreserved) { $xmltvRollbackRelativePath } else { $null }
    Status                         = $overallStatus
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

# Generated reports contain only safe labels, counts, relative output names,
# and hashes. Provider/EPG URLs, local paths, credentials, and evidence are
# deliberately excluded.
$md = @()
$md += "# ChannelForge Build Summary"
$md += ""
$md += "Generated: $($summary.GeneratedAt)"
$md += ""

if ($m3uGenerated) {
    $md += "Merged M3U: $m3uRelativePath ($channelCount channels, $duplicateCount duplicates excluded, $warningCount warnings, SHA-256 $m3uHash)"
}
else {
    $md += 'Merged M3U: not generated. No provider source has a local_playlist configured yet (HTTP fetch is deferred).'
}

$md += ""
$md += "## XMLTV Result"
switch ($xmltvStatus) {
    'GENERATED' {
        $md += "Generated XMLTV: $xmltvRelativePath ($xmltvProgrammeCount programmes, $xmltvBindingCount channels, $xmltvDuplicateGroupCount duplicate groups, SHA-256 $xmltvHash)"
    }
    'FAILED' {
        $md += "XMLTV output: FAILED. $xmltvFailureReason"
    }
    default {
        $md += "XMLTV output: deferred. $xmltvDeferredReason"
    }
}

if ($xmltvStatus -ne 'GENERATED') {
    $md += 'Current XMLTV publication: absent.'
}

if ($xmltvPreviousOutputPreserved) {
    $md += 'Prior XMLTV artifact: preserved for rollback/inspection only.'
}

$md += ""
$md += "Known limitations:"
$md += '- Remote HTTP provider/EPG fetch: deferred. Only local files are read in this phase.'
$md += '- Cache, scheduled refresh, provider adapters, and GUI workflows: deferred.'
$md += '- Plex EPG/guide binding: deferred; generated XMLTV is a separate output.'
$md += ""
$md += "## Provider M3U Sources"
foreach ($s in $providerSources) {
    $state = if ($s.Enabled) { 'enabled' } else { 'disabled' }
    $playlistState = if ($s.LocalPlaylist) { 'local playlist configured' } else { 'no local playlist' }
    $md += "- $(Get-SafeReportText $s.Name) ($state, $playlistState)"
}
$md += ""
$md += "## EPG Sources"
foreach ($e in $epgSources) {
    $md += "- [$($e.Priority)] $(Get-SafeReportText $e.Name) - $(Get-SafeReportText $e.Role)"
}
$md += ""
$md += "## Local Channels"
foreach ($l in ($locals.locals | Sort-Object number)) {
    $md += "- $($l.number) - $(Get-SafeReportText $l.display)"
}
$md += ""
$md += "## Numbering Blocks"
foreach ($b in $blocks.blocks) {
    $md += "- $($b.start)-$($b.end): $(Get-SafeReportText $b.category) - $(Get-SafeReportText $b.notes)"
}

$md -join "`n" | Set-Content -LiteralPath $planPath -Encoding UTF8

if ($xmltvStatus -eq 'FAILED') {
    Write-Host "ChannelForge build failed: $xmltvFailureReason" -ForegroundColor Red
    throw $xmltvFailureReason
}

Write-Host "ChannelForge build completed." -ForegroundColor Green
Write-Host "Report: $planPath"
