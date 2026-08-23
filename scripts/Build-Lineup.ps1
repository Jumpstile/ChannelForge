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
$cacheRoot = Join-Path $outDir "cache\remote-xmltv"
$m3uCacheRoot = Join-Path $outDir "cache\remote-m3u"
$playlistDir = Join-Path $dataDir "playlists"
$epgConfigPath = Join-Path $dataDir "epg/epg_sources.json"

# Path-safety guardrail: generated artifacts may only land inside output/.
Assert-ChannelForgeWritePath -Path $outDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $reportDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $cacheRoot -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $m3uCacheRoot -AllowedRoot $outDir
New-Item -ItemType Directory -Force -Path $outDir, $reportDir, $cacheRoot, $m3uCacheRoot | Out-Null

$m3uPath = Join-Path $outDir 'merged.m3u'
$m3uTempPath = Join-Path $outDir 'merged.m3u.tmp'
$m3uRollbackDir = Join-Path $outDir 'm3u-rollback'
$m3uRollbackPath = Join-Path $m3uRollbackDir 'merged.m3u.previous'
$m3uRollbackRelativePath = 'output/m3u-rollback/merged.m3u.previous'
Assert-ChannelForgeWritePath -Path $m3uPath -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $m3uTempPath -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $m3uRollbackDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $m3uRollbackPath -AllowedRoot $outDir
$m3uPreviousOutputPresent = Test-Path -LiteralPath $m3uPath -PathType Leaf
$m3uPreviousOutputPreserved = $false

if (Test-Path -LiteralPath $m3uTempPath -PathType Leaf) {
    try {
        Remove-Item -LiteralPath $m3uTempPath -Force -ErrorAction Stop
    }
    catch {
        throw 'Previous M3U staging output could not be cleared safely.'
    }
}

if ($m3uPreviousOutputPresent) {
    try {
        New-Item -ItemType Directory -Force -Path $m3uRollbackDir | Out-Null
        if (Test-Path -LiteralPath $m3uRollbackPath -PathType Leaf) {
            [System.IO.File]::Replace($m3uPath, $m3uRollbackPath, $null)
        }
        else {
            [System.IO.File]::Move($m3uPath, $m3uRollbackPath)
        }

        if (Test-Path -LiteralPath $m3uPath -PathType Leaf) {
            throw 'Public M3U publication path remained after quarantine.'
        }

        $m3uPreviousOutputPreserved = $true
    }
    catch {
        throw 'Previous M3U publication could not be quarantined safely.'
    }
}

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

$m3uStatus = 'NOT_CONFIGURED'
$m3uGenerated = $false
$m3uRelativePath = $null
$m3uHash = $null
$m3uFailureReason = $null
$m3uRemoteSourceCount = @($providerSources | Where-Object {
    $_.Enabled -and [string]::IsNullOrWhiteSpace([string]$_.LocalPlaylist) -and
    -not [string]::IsNullOrWhiteSpace([string]$_.Url)
}).Count
$m3uDisabledSourceCount = @($providerSources | Where-Object { -not $_.Enabled }).Count
$m3uActiveSourceCount = @($providerSources | Where-Object { $_.Enabled }).Count
$m3uAcquisitionStatuses = [System.Collections.Generic.List[object]]::new()
$channelCount = 0
$duplicateCount = 0
$warningCount = 0

if ($m3uActiveSourceCount -gt 0) {
    $m3uFailureStage = 'acquisition'
    try {
        $mergeSource = [System.Collections.Generic.List[object]]::new()
        for ($sourceIndex = 0; $sourceIndex -lt $providerSources.Count; $sourceIndex++) {
            $source = $providerSources[$sourceIndex]
            if (-not $source.Enabled) {
                continue
            }

            # Configuration order is deterministic source truth. It is used
            # instead of absolute local paths or remote URLs as the merge key.
            $orderKey = '{0:D8}' -f $sourceIndex
            if (-not [string]::IsNullOrWhiteSpace([string]$source.LocalPlaylist)) {
                $resolvedPlaylistPath = Join-Path $Root $source.LocalPlaylist
                Assert-ChannelForgeReadPath -Path $resolvedPlaylistPath -AllowedRoot $playlistDir
                [void]$mergeSource.Add([pscustomobject]@{
                    Path      = $resolvedPlaylistPath
                    Provider  = $providerConfig.provider
                    Playlist  = $source.Name
                    OrderKey  = $orderKey
                })
                continue
            }

            if ([string]::IsNullOrWhiteSpace([string]$source.Url)) {
                throw 'An enabled provider source has neither a local playlist nor a supported remote URL.'
            }

            $acquisitionStatus = [ordered]@{}
            $remoteChannels = @(Import-ChannelForgeConfiguredM3USource `
                -Source ([pscustomobject]@{
                    Name       = $source.Name
                    Url        = $source.Url
                    ProviderId = $providerConfig.provider
                }) `
                -Provider $providerConfig.provider `
                -CacheRoot $m3uCacheRoot `
                -AcquisitionStatus $acquisitionStatus)

            [void]$mergeSource.Add([pscustomobject]@{
                Channels  = $remoteChannels
                Provider  = $providerConfig.provider
                Playlist  = $source.Name
                OrderKey  = $orderKey
            })

            if ($acquisitionStatus.Count -gt 0) {
                [void]$m3uAcquisitionStatuses.Add([pscustomobject][ordered]@{
                    ProviderId        = Get-SafeReportText $acquisitionStatus['ProviderId']
                    SourceId           = Get-SafeReportText $acquisitionStatus['SourceId']
                    Outcome            = [string]$acquisitionStatus['Outcome']
                    Reason             = [string]$acquisitionStatus['Reason']
                    CacheKey           = [string]$acquisitionStatus['CacheKey']
                    HttpStatus         = $acquisitionStatus['StatusCode']
                    ContentType        = [string]$acquisitionStatus['ContentType']
                    ContentEncodings   = @($acquisitionStatus['ContentEncodings'])
                    RawContentLength   = $acquisitionStatus['RawContentLength']
                    DecompressedBytes  = $acquisitionStatus['DecompressedBytes']
                    ParsedChannelCount = $acquisitionStatus['ChannelCount']
                    HasETag            = [bool]$acquisitionStatus['HasETag']
                    HasLastModified    = [bool]$acquisitionStatus['HasLastModified']
                })
            }
        }

        if ($mergeSource.Count -eq 0) {
            throw 'No enabled provider M3U source could be acquired.'
        }

        $m3uFailureStage = 'merge'
        $mergeResult = Merge-ChannelForgeLineup `
            -Source @($mergeSource.ToArray()) `
            -AliasPath $aliasPath `
            -NumberingBlocksPath $numberingBlocksPath

        $m3uFailureStage = 'export'
        $mergeResult.Channels | Export-ChannelForgeM3UPlaylist -Path $m3uTempPath
        if (-not (Test-Path -LiteralPath $m3uTempPath -PathType Leaf)) {
            throw 'M3U exporter did not produce the staged output.'
        }

        $m3uHash = (Get-FileHash -LiteralPath $m3uTempPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $m3uFailureStage = 'publish'
        if (Test-Path -LiteralPath $m3uPath -PathType Leaf) {
            throw 'Public M3U publication path was recreated before promotion.'
        }
        [System.IO.File]::Move($m3uTempPath, $m3uPath)

        $m3uStatus = 'GENERATED'
        $m3uGenerated = $true
        $m3uRelativePath = 'output/merged.m3u'
        $channelCount = $mergeResult.Channels.Count
        $duplicateCount = $mergeResult.DuplicateCount
        $warningCount = $mergeResult.WarningCount
    }
    catch {
        if ($m3uFailureStage -eq 'acquisition' -and
            $_.Exception.Message -like '*approved location*') {
            throw
        }

        $m3uStatus = 'FAILED'
        $m3uGenerated = $false
        $m3uRelativePath = $null
        $m3uHash = $null
        if ($m3uFailureStage -eq 'acquisition') {
            $m3uFailureReason = 'Configured provider M3U input could not be acquired or parsed.'
        }
        elseif ($m3uFailureStage -eq 'merge') {
            $m3uFailureReason = 'Acquired provider M3U channels could not be merged deterministically.'
        }
        elseif ($m3uFailureStage -eq 'export') {
            $m3uFailureReason = 'Merged provider M3U channels could not be serialized.'
        }
        elseif ($m3uFailureStage -eq 'publish') {
            $m3uFailureReason = 'Merged M3U output could not be promoted safely.'
        }
        else {
            $m3uFailureReason = 'Provider M3U build processing failed.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $m3uTempPath -PathType Leaf) {
            Remove-Item -LiteralPath $m3uTempPath -Force -ErrorAction SilentlyContinue
        }
    }
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
$xmltvAcquisitionStatuses = [System.Collections.Generic.List[object]]::new()
$sourceEnumerationIndex = 0
foreach ($source in $epgSources) {
    $sourceProperties = @($source.PSObject.Properties.Name)
    $configuredPath = if ($sourceProperties -contains 'ConfiguredPath') {
        [string]$source.ConfiguredPath
    }
    else {
        ''
    }

    $hasRemoteUrl = -not [string]::IsNullOrWhiteSpace([string]$source.Url)
    $hasLocalPath = -not [string]::IsNullOrWhiteSpace([string]$source.Path)

    if ($source.Enabled -and $source.Supported -and
        [string]::Equals([string]$source.Format, 'xmltv', [System.StringComparison]::Ordinal) -and
        (($hasRemoteUrl -and -not $hasLocalPath) -or ($hasLocalPath -and -not $hasRemoteUrl))) {
        $pathKey = if ($hasRemoteUrl) {
            ''
        }
        elseif ([System.IO.Path]::IsPathRooted($configuredPath.Trim())) {
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

$xmltvSources = @($xmltvSourceRecords | ForEach-Object { $_.Source })
$xmltvSourceCount = $xmltvSources.Count

if ($xmltvSourceCount -eq 0) {
    if ($xmltvRemoteSourceCount -gt 0) {
        $xmltvStatus = 'FAILED'
        $xmltvFailureReason = 'An enabled remote XMLTV source could not be selected.'
    }
    else {
        $xmltvStatus = 'NOT_CONFIGURED'
        $xmltvDeferredReason = 'No enabled XMLTV source is configured.'
    }
}
else {
    $xmltvFailureStage = 'import'
    try {
        $allProgrammes = [System.Collections.Generic.List[object]]::new()

        foreach ($source in $xmltvSources) {
            $acquisitionStatus = [ordered]@{}
            $sourceProgrammes = @(Import-ChannelForgeConfiguredXmltvSource `
                -Source $source `
                -CacheRoot $cacheRoot `
                -AcquisitionStatus $acquisitionStatus)
            if ($acquisitionStatus.Count -gt 0) {
                [void]$xmltvAcquisitionStatuses.Add([pscustomobject][ordered]@{
                    SourceId = [string]$source.Name
                    Outcome  = [string]$acquisitionStatus['Outcome']
                    Reason   = [string]$acquisitionStatus['Reason']
                    CacheKey = [string]$acquisitionStatus['CacheKey']
                })
            }
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
        if ($xmltvFailureStage -eq 'import') {
            $hasRemoteXmltvSource = @($xmltvSources | Where-Object {
                [string]::Equals([string]$_.SourceKind, 'remote', [System.StringComparison]::Ordinal)
            }).Count -gt 0
            if ($hasRemoteXmltvSource) { $xmltvFailureReason = 'Configured XMLTV input could not be imported.' }
            else { $xmltvFailureReason = 'Configured local XMLTV input could not be imported.' }
        }
        elseif ($xmltvFailureStage -eq 'merge') {
            $xmltvFailureReason = 'Imported XMLTV programmes could not be merged deterministically.'
        }
        elseif ($xmltvFailureStage -eq 'export') {
            $xmltvFailureReason = 'Merged XMLTV programmes could not be serialized.'
        }
        elseif ($xmltvFailureStage -eq 'publish') {
            $xmltvFailureReason = 'XMLTV output could not be promoted safely.'
        }
        else {
            $xmltvFailureReason = 'XMLTV build processing failed.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $xmltvTempPath -PathType Leaf) {
            Remove-Item -LiteralPath $xmltvTempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

$overallStatus = if ($m3uStatus -eq 'FAILED' -or $xmltvStatus -eq 'FAILED') {
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
    M3UStatus                      = $m3uStatus
    M3UGenerated                   = $m3uGenerated
    M3UPath                        = $m3uRelativePath
    M3USha256                      = $m3uHash
    M3URemoteSourceCount           = $m3uRemoteSourceCount
    M3UDisabledSourceCount         = $m3uDisabledSourceCount
    M3UActiveSourceCount           = $m3uActiveSourceCount
    ChannelCount                   = $channelCount
    DuplicateCount                = $duplicateCount
    WarningCount                   = $warningCount
    M3UFailureReason               = $m3uFailureReason
    M3UAcquisitionStatus           = @($m3uAcquisitionStatuses.ToArray())
    M3UPreviousOutputPresent       = $m3uPreviousOutputPresent
    M3UPreviousOutputPreserved     = $m3uPreviousOutputPreserved
    M3URollbackPath                = if ($m3uPreviousOutputPreserved) { $m3uRollbackRelativePath } else { $null }
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
    XMLTVAcquisitionStatus          = @($xmltvAcquisitionStatuses.ToArray())
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
elseif ($m3uStatus -eq 'FAILED') {
    $md += "Merged M3U: FAILED. $m3uFailureReason"
}
else {
    $md += 'Merged M3U: deferred. No enabled provider source is configured.'
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
$md += '- Remote XMLTV and provider M3U acquisition: bounded HTTPS only; no redirects, proxies, credentials, retries, or live-network CI.'
$md += '- Scheduled refresh, durable source snapshots, and GUI workflows: deferred.'
$md += '- Plex EPG/guide binding: deferred; generated XMLTV is a separate output.'
$md += ""
$md += "## Provider M3U Sources"
foreach ($s in $providerSources) {
    $state = if ($s.Enabled) { 'enabled' } else { 'disabled' }
    $playlistState = if ($s.LocalPlaylist) { 'local playlist configured' } else { 'remote playlist configured' }
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

if ($m3uStatus -eq 'FAILED' -or $xmltvStatus -eq 'FAILED') {
    $failureMessage = if ($m3uStatus -eq 'FAILED') { $m3uFailureReason } else { $xmltvFailureReason }
    Write-Host "ChannelForge build failed: $failureMessage" -ForegroundColor Red
    throw $failureMessage
}

Write-Host "ChannelForge build completed." -ForegroundColor Green
Write-Host "Report: $planPath"
