param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    # Explicit override for the provider config file.
    [string]$ProviderPath,

    # Candidate-only fault injection is test-only and never affects accepted
    # state. It names one of C01-C15 or the directory move hooks.
    [string]$FaultHook = ''
)

$ErrorActionPreference = "Stop"

# Always load the module from this script's own location, never from -Root.
$ModuleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ModuleRoot 'src\ChannelForge\ChannelForge.psd1') -Force

function Invoke-ChannelForgePrivateCandidateFunction {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Arguments
    )

    $module = $null
    foreach ($candidateModule in @(Get-Module -Name ChannelForge)) {
        $hasFunction = & $candidateModule {
            param($privateName)
            $null -ne (Get-Command -Name $privateName -CommandType Function -ErrorAction SilentlyContinue)
        } $Name
        if ($null -eq $module -and $hasFunction) {
            $module = $candidateModule
        }
    }
    if ($null -eq $module) {
        throw 'ChannelForge module is not loaded; candidate projection cannot continue.'
    }
    return @(& $module {
            param($privateName, $privateArguments)
            & $privateName @privateArguments
        } $Name $Arguments)
}

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

function Get-SafeReportIdentityText {
    param([object]$Value)

    # Preserve leading/trailing identity characters for exact-guide evidence;
    # only the safety check is shared with ordinary report text.
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($text -match '(?i)(https?://|ftp://|file://|[a-z]:[\\/]|^\\\\|ACCOUNT_ID|API_TOKEN|PASSWORD|TOKEN|SECRET)') {
        return '[redacted]'
    }

    return $text
}

function ConvertTo-SafeChannelForgeIdentityEvidence {
    param(
        [AllowNull()]
        [object]$Evidence
    )

    if ($null -eq $Evidence) {
        return $null
    }

    $sourceKind = if ($null -ne $Evidence.PSObject.Properties['SourceKind']) {
        [string]$Evidence.SourceKind
    }
    else {
        'local'
    }
    $sourceReference = if ($null -ne $Evidence.PSObject.Properties['SourceReference']) {
        Get-SafeReportText $Evidence.SourceReference
    }
    else {
        $null
    }

    return [ordered]@{
        EvidenceType   = Get-SafeReportText $Evidence.EvidenceType
        SourceId       = Get-SafeReportText $Evidence.SourceId
        SourceKind     = Get-SafeReportText $sourceKind
        SourceReference = $sourceReference
        Compression    = Get-SafeReportText $Evidence.Compression
        ProgrammeCount = $Evidence.ProgrammeCount
        ChannelCount   = $Evidence.ChannelCount
        DocumentBytes  = $Evidence.DocumentBytes
    }
}

function ConvertTo-SafeChannelForgeIdentityCandidates {
    param(
        [AllowEmptyCollection()]
        [object[]]$Candidates
    )

    return @($Candidates | ForEach-Object {
            [ordered]@{
                SourceId         = Get-SafeReportText $_.SourceId
                XmltvChannelId   = Get-SafeReportIdentityText $_.XmltvChannelId
                DeclarationCount = $_.DeclarationCount
                ProgrammeCount   = $_.ProgrammeCount
                Evidence         = @($_.Evidence | ForEach-Object {
                        ConvertTo-SafeChannelForgeIdentityEvidence -Evidence $_
                    })
            }
        })
}

function ConvertTo-SafeChannelForgeIdentityRecord {
    param(
        [Parameter(Mandatory)]
        [object]$Record
    )

    $safe = [ordered]@{
        Status = Get-SafeReportText $Record.Status
        Reason = Get-SafeReportText $Record.Reason
    }

    if ($null -ne $Record.PSObject.Properties['M3UChannel']) {
        $channel = $Record.M3UChannel
        $safe.M3UChannel = [ordered]@{
            TvgId          = Get-SafeReportIdentityText $Record.TvgId
            DisplayName    = Get-SafeReportText $Record.DisplayName
            AssignedNumber = if ($null -eq $channel.AssignedNumber) { $null } else { $channel.AssignedNumber }
            Provider       = Get-SafeReportText $channel.Provider
            Playlist       = Get-SafeReportText $channel.Playlist
        }
    }
    elseif ($null -ne $Record.PSObject.Properties['TvgId']) {
        $safe.TvgId = Get-SafeReportIdentityText $Record.TvgId
        $safe.DisplayName = Get-SafeReportText $Record.DisplayName
    }

    if ($null -ne $Record.PSObject.Properties['XmltvChannelId']) {
        $safe.XmltvChannelId = Get-SafeReportIdentityText $Record.XmltvChannelId
    }
    if ($null -ne $Record.PSObject.Properties['XmltvSourceId']) {
        $safe.XmltvSourceId = Get-SafeReportText $Record.XmltvSourceId
    }
    if ($null -ne $Record.PSObject.Properties['Candidates']) {
        $safe.Candidates = ConvertTo-SafeChannelForgeIdentityCandidates -Candidates @($Record.Candidates)
    }
    if ($null -ne $Record.PSObject.Properties['Evidence']) {
        $safe.Evidence = @($Record.Evidence | ForEach-Object {
                ConvertTo-SafeChannelForgeIdentityEvidence -Evidence $_
            })
    }

    if ($null -ne $Record.PSObject.Properties['M3UIdentityCollision']) {
        $collision = $Record.M3UIdentityCollision
        $safe.M3UIdentityCollision = [ordered]@{
            IdentityKey = Get-SafeReportText $collision.IdentityKey
            Channels    = @($collision.Channels | ForEach-Object {
                    [ordered]@{
                        TvgId       = Get-SafeReportIdentityText $_.TvgId
                        DisplayName = Get-SafeReportText $_.DisplayName
                        Provider    = Get-SafeReportText $_.Provider
                        Playlist    = Get-SafeReportText $_.Playlist
                    }
                })
        }
    }

    return [pscustomobject]$safe
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

function Select-ChannelForgeEpgConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EpgDirectory,

        [Parameter(Mandatory)]
        [string]$SchemaPath
    )

    $defaultPath = Join-Path $EpgDirectory 'epg_sources.json'
    $localPath = Join-Path $EpgDirectory 'epg_sources.local.json'

    if (Test-Path -LiteralPath $localPath) {
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw 'Local EPG configuration path exists but is not a file; refusing to use the tracked default.'
        }

        try {
            $schemaValid = Test-Json -Path $localPath -SchemaFile $SchemaPath -ErrorAction Stop
            if (-not $schemaValid) {
                throw 'Schema validation returned false.'
            }
        }
        catch {
            # The local file is user intent. Once present, any malformed or
            # schema-invalid content must block the build rather than silently
            # switching to the tracked example/default configuration.
            throw 'Local EPG configuration is invalid; refusing to use the tracked default.'
        }

        return [pscustomobject]@{
            Path   = [System.IO.Path]::GetFullPath($localPath)
            Source = 'LocalOverride'
        }
    }

    return [pscustomobject]@{
        Path   = [System.IO.Path]::GetFullPath($defaultPath)
        Source = 'Default'
    }
}

$dataDir = Join-Path $Root "data"
$outDir = Join-Path $Root "output"
$reportDir = Join-Path $outDir "reports"
$cacheRoot = Join-Path $outDir "cache\remote-xmltv"
$m3uCacheRoot = Join-Path $outDir "cache\remote-m3u"
$playlistDir = Join-Path $dataDir "playlists"
$epgDirectory = Join-Path $dataDir 'epg'
$epgSchemaPath = Join-Path $ModuleRoot 'schemas/epg_sources.schema.json'

# Path-safety guardrail: generated artifacts may only land inside output/.
Assert-ChannelForgeWritePath -Path $outDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $reportDir -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $cacheRoot -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $m3uCacheRoot -AllowedRoot $outDir
New-Item -ItemType Directory -Force -Path $outDir, $reportDir, $cacheRoot, $m3uCacheRoot | Out-Null

$m3uPath = Join-Path $outDir 'merged.m3u'
$xmltvPath = Join-Path $outDir 'merged.xml'
$m3uRollbackRelativePath = 'output/m3u-rollback/merged.m3u.previous'
$xmltvRollbackRelativePath = 'output/xmltv-rollback/merged.xml.previous'
# Candidate builds never read, write, move, replace, quarantine, or delete
# the public artifacts or their existing rollback directories.
Assert-ChannelForgeWritePath -Path $m3uPath -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $xmltvPath -AllowedRoot $outDir
$m3uPreviousOutputPresent = Test-Path -LiteralPath $m3uPath -PathType Leaf
$xmltvPreviousOutputPresent = Test-Path -LiteralPath $xmltvPath -PathType Leaf
$m3uPreviousOutputPreserved = $false
$xmltvPreviousOutputPreserved = $false

$candidateRoot = Join-Path $outDir 'candidates'
$candidateStagingRoot = Join-Path (Join-Path $candidateRoot '.staging') ([guid]::NewGuid().ToString('N'))
$candidateM3UPath = Join-Path $candidateStagingRoot 'merged.m3u'
$candidateXmltvPath = Join-Path $candidateStagingRoot 'merged.xml'
$candidateManifestPath = Join-Path $candidateStagingRoot 'manifest.json'
$candidateReviewJsonPath = Join-Path $candidateStagingRoot 'lineup-change-review.json'
$candidateReviewMarkdownPath = Join-Path $candidateStagingRoot 'lineup-change-review.md'
$m3uTempPath = Join-Path $candidateStagingRoot '.merged.m3u.export.tmp'
$xmltvTempPath = Join-Path $candidateStagingRoot '.merged.xml.export.tmp'
Assert-ChannelForgeWritePath -Path $candidateRoot -AllowedRoot $outDir
Assert-ChannelForgeWritePath -Path $candidateStagingRoot -AllowedRoot $outDir
New-Item -ItemType Directory -Force -Path $candidateStagingRoot | Out-Null
$candidateNamespacePath = $null
$candidateBuildIdentity = $null
$candidateManifestHash = $null
$candidatePublished = $false

$m3uRawOccurrences = @()
$identityBindingResult = $null
$allProgrammes = @()
$xmltvMergeResult = $null

$providersDir = Join-Path $dataDir "providers"
$resolvedProviderPath = Resolve-ChannelForgeProviderConfigPath `
    -ProviderDirectory $providersDir `
    -TrackedFileName 'mybunny.json' `
    -OverridePath $ProviderPath

# Provider and EPG source files go through their centralized readers so URL
# trust-boundary validation remains in one place. A present local EPG override
# is schema-validated before reading and is never replaced by the default after
# selection. URL values are never written to reports or included in build
# decisions beyond being classified as remote.
$providerSources = @(Read-ChannelForgeProvider -Path $resolvedProviderPath)
$providerConfig = Read-JsonFile $resolvedProviderPath
$epgSelection = Select-ChannelForgeEpgConfig -EpgDirectory $epgDirectory -SchemaPath $epgSchemaPath
$epgConfigPath = $epgSelection.Path
$epgConfigSource = $epgSelection.Source
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
$mergedM3UChannels = @()

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
        $m3uRawOccurrences = @(Invoke-ChannelForgePrivateCandidateFunction `
            -Name 'Get-ChannelForgeRawM3UProjection' `
            -Arguments @{ Channel = @($mergeResult.AllChannels) })
        $candidateChannels = @($m3uRawOccurrences |
            Where-Object { $null -ne $_.Channel -and -not $_.Channel.IsDuplicate } |
            Sort-Object @{ Expression = { [string]$_.EntryId } }, @{ Expression = { [string]$_.RawM3UOccurrenceDigest } } |
            ForEach-Object { $_.Channel })
        $candidateChannels | Export-ChannelForgeM3UPlaylist -Path $m3uTempPath
        if (-not (Test-Path -LiteralPath $m3uTempPath -PathType Leaf)) {
            throw 'M3U exporter did not produce the staged output.'
        }

        $m3uBytes = [System.IO.File]::ReadAllBytes($m3uTempPath)
        Invoke-ChannelForgePrivateCandidateFunction `
            -Name 'Write-ChannelForgeCandidateArtifact' `
            -Arguments @{ Path = $candidateM3UPath; Bytes = $m3uBytes; HookPrefix = 'CandidateStageWrite.M3U'; FaultHook = $FaultHook } | Out-Null
        Remove-Item -LiteralPath $m3uTempPath -Force
        $m3uHash = (Get-FileHash -LiteralPath $candidateM3UPath -Algorithm SHA256).Hash.ToLowerInvariant()

        $m3uStatus = 'GENERATED'
        $m3uGenerated = $true
        $m3uRelativePath = $null
        $mergedM3UChannels = @($candidateChannels)
        $channelCount = $candidateChannels.Count
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
$m3uXmltvBindingStatus = 'NOT_EVALUATED'
$m3uXmltvBindingReason = 'M3U/XMLTV identity binding was not evaluated.'
$m3uXmltvExactBindings = @()
$m3uXmltvUnboundChannels = @()
$m3uXmltvReviewNeeded = @()
$m3uXmltvOrphanedXmltvChannels = @()

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

        $xmltvFailureStage = 'identity-binding'
        if ($m3uGenerated) {
            $identityBindingResult = Resolve-ChannelForgeM3UXmltvBinding `
                -Channel $mergedM3UChannels `
                -Programme @($allProgrammes.ToArray()) `
                -M3UIdentityCollisions @($mergeResult.IdentityCollisions)

            $m3uXmltvBindingStatus = [string]$identityBindingResult.Status
            $m3uXmltvBindingReason = 'Only exact, unambiguous tvg-id/XMLTV channel-id matches are publishable bindings.'
            $m3uXmltvExactBindings = @($identityBindingResult.ExactBindings | ForEach-Object {
                    ConvertTo-SafeChannelForgeIdentityRecord -Record $_
                })
            $m3uXmltvUnboundChannels = @($identityBindingResult.UnboundChannels | ForEach-Object {
                    ConvertTo-SafeChannelForgeIdentityRecord -Record $_
                })
            $m3uXmltvReviewNeeded = @($identityBindingResult.ReviewNeeded | ForEach-Object {
                    ConvertTo-SafeChannelForgeIdentityRecord -Record $_
                })
            $m3uXmltvOrphanedXmltvChannels = @($identityBindingResult.OrphanedXmltvChannels | ForEach-Object {
                    ConvertTo-SafeChannelForgeIdentityRecord -Record $_
                })
        }
        else {
            $m3uXmltvBindingStatus = 'NOT_EVALUATED'
            $m3uXmltvBindingReason = 'M3U output was not generated; XMLTV identity binding remains unbound.'
        }

        $xmltvFailureStage = 'export'
        Export-ChannelForgeXmltv `
            -MergeResult $xmltvMergeResult `
            -Path $xmltvTempPath `
            -AllowedRoot $outDir

        if (-not (Test-Path -LiteralPath $xmltvTempPath -PathType Leaf)) {
            throw 'XMLTV exporter did not produce the staged output.'
        }

        $xmltvBytes = [System.IO.File]::ReadAllBytes($xmltvTempPath)
        Invoke-ChannelForgePrivateCandidateFunction `
            -Name 'Write-ChannelForgeCandidateArtifact' `
            -Arguments @{ Path = $candidateXmltvPath; Bytes = $xmltvBytes; HookPrefix = 'CandidateStageWrite.XMLTV'; FaultHook = $FaultHook } | Out-Null
        Remove-Item -LiteralPath $xmltvTempPath -Force
        $xmltvHash = (Get-FileHash -LiteralPath $candidateXmltvPath -Algorithm SHA256).Hash.ToLowerInvariant()

        $xmltvStatus = 'GENERATED'
        $xmltvGenerated = $true
        $xmltvRelativePath = $null
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
        elseif ($xmltvFailureStage -eq 'identity-binding') {
            $xmltvFailureReason = 'M3U/XMLTV identity binding could not be evaluated safely.'
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

if ($m3uGenerated -or $xmltvGenerated) {
    try {
        $rawXmltvOccurrences = if ($allProgrammes.Count -gt 0) {
            @(Invoke-ChannelForgePrivateCandidateFunction `
                -Name 'Get-ChannelForgeRawXmltvProjection' `
                -Arguments @{ Programme = @($allProgrammes.ToArray()) })
        }
        else {
            @()
        }

        $selectedSourceIds = @($m3uRawOccurrences | ForEach-Object { [string]$_.LogicalSourceId })
        $selectedSourceIds += @($rawXmltvOccurrences | ForEach-Object { [string]$_.LogicalSourceId })
        $selectedSourceIds = @($selectedSourceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $candidateM3UBytes = if ($m3uGenerated) {
            [System.IO.File]::ReadAllBytes((Join-Path $candidateStagingRoot 'merged.m3u'))
        }
        else {
            $null
        }
        $candidateXMLTVBytes = if ($xmltvGenerated) {
            [System.IO.File]::ReadAllBytes((Join-Path $candidateStagingRoot 'merged.xml'))
        }
        else {
            $null
        }
        $manifestResult = Invoke-ChannelForgePrivateCandidateFunction `
            -Name 'ConvertTo-ChannelForgeCandidateManifest' `
            -Arguments @{
                RawM3UOccurrences       = @($m3uRawOccurrences)
                M3UIdentityCollisions   = @($mergeResult.IdentityCollisions)
                RawXmltvOccurrences     = @($rawXmltvOccurrences)
                IdentityBindingResult   = $identityBindingResult
                M3UBytes                = $candidateM3UBytes
                XMLTVBytes              = $candidateXMLTVBytes
                SelectedSourceIds       = $selectedSourceIds
            }
        if ($null -eq $manifestResult -or $manifestResult.Count -eq 0) {
            throw 'Candidate manifest construction returned no result.'
        }
        $manifestResult = @($manifestResult)[-1]
        $candidateBuildIdentity = [string]$manifestResult.BuildIdentity
        $candidateManifestHash = [string]$manifestResult.CandidateManifestHash

        $manifestObject = [ordered]@{}
        foreach ($property in @($manifestResult.Manifest.PSObject.Properties)) {
            $manifestObject[$property.Name] = $property.Value
        }
        $manifestObject['CandidateManifestHash'] = $candidateManifestHash
        $manifestBytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes(
            [string](Invoke-ChannelForgePrivateCandidateFunction `
                -Name 'ConvertTo-ChannelForgeCanonicalJson' `
                -Arguments @{ InputObject = $manifestObject }))
        Invoke-ChannelForgePrivateCandidateFunction `
            -Name 'Write-ChannelForgeCandidateArtifact' `
            -Arguments @{ Path = $candidateManifestPath; Bytes = $manifestBytes; HookPrefix = 'CandidateStageWrite.Manifest'; FaultHook = $FaultHook } | Out-Null

        $reviewObject = [ordered]@{
            Version                = 'blocker-2-contract/v1'
            BuildIdentity          = $candidateBuildIdentity
            CandidateManifestHash  = $candidateManifestHash
            BindingRecords         = @($manifestResult.BindingProjection)
            M3UIdentityCollisions  = @($manifestResult.Manifest.M3UIdentityCollisions)
            RawM3UOccurrenceCount  = @($m3uRawOccurrences).Count
            RawXMLTVOccurrenceCount = @($rawXmltvOccurrences).Count
            ExactBindingCount      = @($m3uXmltvExactBindings).Count
            UnboundCount            = @($m3uXmltvUnboundChannels).Count
            ReviewNeededCount      = @($m3uXmltvReviewNeeded).Count
            XMLTVOnlyCount         = @($m3uXmltvOrphanedXmltvChannels).Count
        }
        $reviewBytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes(
            [string](Invoke-ChannelForgePrivateCandidateFunction `
                -Name 'ConvertTo-ChannelForgeCanonicalJson' `
                -Arguments @{ InputObject = $reviewObject }))
        Invoke-ChannelForgePrivateCandidateFunction `
            -Name 'Write-ChannelForgeCandidateArtifact' `
            -Arguments @{ Path = $candidateReviewJsonPath; Bytes = $reviewBytes; HookPrefix = 'CandidateStageWrite.ReviewJSON'; FaultHook = $FaultHook } | Out-Null

        $reviewMarkdown = @(
            '# ChannelForge Lineup Change Review',
            '',
            "Build identity: $candidateBuildIdentity",
            "Candidate manifest: $candidateManifestHash",
            "Exact bindings: $(@($m3uXmltvExactBindings).Count)",
            "Unbound M3U channels: $(@($m3uXmltvUnboundChannels).Count)",
            "Review-needed identities: $(@($m3uXmltvReviewNeeded).Count)",
            "XMLTV-only channels: $(@($m3uXmltvOrphanedXmltvChannels).Count)",
            '',
            'This is a candidate-only report. Accepted state and public merged artifacts are unchanged.'
        ) -join "`n"
        $reviewMarkdownBytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($reviewMarkdown + "`n")
        Invoke-ChannelForgePrivateCandidateFunction `
            -Name 'Write-ChannelForgeCandidateArtifact' `
            -Arguments @{ Path = $candidateReviewMarkdownPath; Bytes = $reviewMarkdownBytes; HookPrefix = 'CandidateStageWrite.ReviewMarkdown'; FaultHook = $FaultHook } | Out-Null

        $candidateNamespacePath = Invoke-ChannelForgePrivateCandidateFunction `
            -Name 'Publish-ChannelForgeCandidateNamespace' `
            -Arguments @{ OutputRoot = $outDir; StagingPath = $candidateStagingRoot; CandidateManifestHash = $candidateManifestHash; FaultHook = $FaultHook }
        $candidateNamespacePath = [string]@($candidateNamespacePath)[-1]
        $candidatePublished = $true
        $m3uRelativePath = if ($m3uGenerated) {
            [System.IO.Path]::GetRelativePath($Root, (Join-Path $candidateNamespacePath 'merged.m3u')).Replace('\', '/')
        }
        else {
            $null
        }
        $xmltvRelativePath = if ($xmltvGenerated) {
            [System.IO.Path]::GetRelativePath($Root, (Join-Path $candidateNamespacePath 'merged.xml')).Replace('\', '/')
        }
        else {
            $null
        }
    }
    catch {
        if (-not $candidatePublished -and (Test-Path -LiteralPath $candidateStagingRoot)) {
            Remove-Item -LiteralPath $candidateStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
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
    CandidateBuildIdentity         = $candidateBuildIdentity
    CandidateManifestHash          = $candidateManifestHash
    CandidateNamespacePath          = if ($candidatePublished) { [System.IO.Path]::GetRelativePath($Root, $candidateNamespacePath).Replace('\', '/') } else { $null }
    Provider                       = Get-SafeReportText $providerConfig.provider
    M3USources                     = $providerSources.Count
    EPGSources                     = $epgSources.Count
    EPGConfigSource                 = $epgConfigSource
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
    M3UXmltvBindingStatus           = $m3uXmltvBindingStatus
    M3UXmltvBindingReason           = $m3uXmltvBindingReason
    M3UXmltvExactBindingCount       = @($m3uXmltvExactBindings).Count
    M3UXmltvUnboundChannelCount     = @($m3uXmltvUnboundChannels).Count
    M3UXmltvReviewNeededCount       = @($m3uXmltvReviewNeeded).Count
    M3UXmltvOrphanedXmltvCount      = @($m3uXmltvOrphanedXmltvChannels).Count
    M3UXmltvExactBindings            = $m3uXmltvExactBindings
    M3UXmltvUnboundChannels          = $m3uXmltvUnboundChannels
    M3UXmltvReviewNeeded             = $m3uXmltvReviewNeeded
    M3UXmltvOrphanedXmltvChannels    = $m3uXmltvOrphanedXmltvChannels
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
# redacted identity provenance, and hashes. Provider/EPG URLs, local paths,
# credentials, and raw source evidence are deliberately excluded.
$md = @()
$md += "# ChannelForge Build Summary"
$md += ""
$md += "Generated: $($summary.GeneratedAt)"
$md += "EPG configuration: $epgConfigSource"
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

$md += ''
$md += '## M3U/XMLTV Identity Binding'
$md += "Status: $m3uXmltvBindingStatus. $m3uXmltvBindingReason"
$md += "Exact bindings: $(@($m3uXmltvExactBindings).Count); unbound M3U channels: $(@($m3uXmltvUnboundChannels).Count); review-needed identities: $(@($m3uXmltvReviewNeeded).Count); XMLTV-only channels: $(@($m3uXmltvOrphanedXmltvChannels).Count)."
foreach ($binding in @($m3uXmltvExactBindings)) {
    $md += "- EXACT: tvg-id '$($binding.M3UChannel.TvgId)' -> XMLTV channel '$($binding.XmltvChannelId)' (source '$($binding.XmltvSourceId)')."
}
foreach ($unbound in @($m3uXmltvUnboundChannels)) {
    $md += "- UNBOUND: tvg-id '$($unbound.M3UChannel.TvgId)' / $($unbound.M3UChannel.DisplayName) ($($unbound.Reason))."
}
foreach ($review in @($m3uXmltvReviewNeeded)) {
    $md += "- REVIEW NEEDED: tvg-id '$($review.M3UChannel.TvgId)' / $($review.M3UChannel.DisplayName) ($($review.Reason)); no candidate was selected."
    if ($null -ne $review.PSObject.Properties['M3UIdentityCollision']) {
        $collisionIds = @($review.M3UIdentityCollision.Channels | ForEach-Object { "'$($_.TvgId)'" }) -join ', '
        $md += "- M3U COLLISION: normalized identity '$($review.M3UIdentityCollision.IdentityKey)' includes raw tvg-ids $collisionIds; no binding was selected."
    }
}
foreach ($orphan in @($m3uXmltvOrphanedXmltvChannels)) {
    $md += "- XMLTV-ONLY: channel '$($orphan.XmltvChannelId)' ($($orphan.Reason))."
}

$md += ""
$md += "Known limitations:"
$md += '- Remote XMLTV and provider M3U acquisition: bounded HTTPS only; no redirects, proxies, credentials, retries, or live-network CI.'
$md += '- Scheduled refresh, durable source snapshots, and GUI workflows: deferred.'
$md += '- Target-specific EPG assignment and automatic Plex refresh: deferred; exact M3U/XMLTV identity bindings are reported separately and generated M3U/XMLTV remain separate outputs.'
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
