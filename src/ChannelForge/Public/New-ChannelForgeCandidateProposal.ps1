function New-ChannelForgeCandidateProposal {
    [CmdletBinding()]
    param(
        [string]$Root = (Get-Location).Path,
        [string]$ProviderPath,
        [string]$M3UPath,
        [string]$XMLTVPath,
        [Parameter(Mandatory)][string]$OutputRoot,
        [string]$TransactionId = ([guid]::NewGuid().ToString('N').ToLowerInvariant()),
        [string]$FaultHook = '',
        [ValidateSet('blocker-2-contract/v7','blocker-2-contract/v8')]
        [string]$CandidateContractVersion = 'blocker-2-contract/v7',
        [switch]$EmitEntrySlices
    )

    $dataDir = Join-Path $Root 'data'
    $outputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
    $playlistDir = Join-Path $dataDir 'playlists'
    $providerDir = Join-Path $dataDir 'providers'
    $aliasPath = Join-Path $dataDir 'rules\aliases.json'
    $blocksPath = Join-Path $dataDir 'lineup\numbering_blocks.json'
    $sourceList = [System.Collections.Generic.List[object]]::new()
    $index = 0

     if (-not [string]::IsNullOrWhiteSpace($M3UPath)) {
         $path = [System.IO.Path]::GetFullPath($M3UPath)
         Assert-ChannelForgeReadPath -Path $path -AllowedRoot $Root
         $providerName = 'candidate'
         $sourceName = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $channels = @(Import-ChannelForgeM3UPlaylist -Path $path -Provider $providerName -Playlist $sourceName -CandidateContractVersion $CandidateContractVersion)
        $logicalId = Get-ChannelForgeLogicalSourceId -ProviderName $providerName -SourceName $sourceName -SourceKind 'M3U' -SourceOrdinal 0
        $raw = @(Get-ChannelForgeRawM3UProjection -Channel $channels -LogicalSourceId $logicalId -CandidateContractVersion $CandidateContractVersion)
         [void]$sourceList.Add([pscustomobject]@{
                 LogicalSourceId = $logicalId
                 Channels = @($channels)
                 Raw = $raw
                 SourceName = $sourceName
                 SourceOrdinal = 0
                SourcePath = $path
             })
         $providerConfig = [pscustomobject]@{ provider = $providerName }
         $merge = [pscustomobject]@{
             Channels = @($channels)
             IdentityCollisions = @()
         }
     }
     else {
         if ([string]::IsNullOrWhiteSpace($ProviderPath)) { $ProviderPath = Join-Path $providerDir 'mybunny.json' }
         $providerPath = Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $providerDir -TrackedFileName 'mybunny.json' -OverridePath $ProviderPath
         $providerConfig = Get-Content -LiteralPath $providerPath -Raw | ConvertFrom-Json
         $providerSources = @(Read-ChannelForgeProvider -Path $providerPath)
         foreach ($source in @($providerSources | Where-Object Enabled)) {
             if ([string]::IsNullOrWhiteSpace([string]$source.LocalPlaylist)) { throw 'Candidate build requires local provider playlists; remote acquisition is not candidate-only.' }
             $path = Join-Path $Root ([string]$source.LocalPlaylist)
             Assert-ChannelForgeReadPath -Path $path -AllowedRoot $playlistDir
            $channels = @(Import-ChannelForgeM3UPlaylist -Path $path -Provider $providerConfig.provider -Playlist $source.Name -CandidateContractVersion $CandidateContractVersion)
            $logicalId = Get-ChannelForgeLogicalSourceId -ProviderName $providerConfig.provider -SourceName $source.Name -SourceKind 'M3U' -SourceOrdinal $index
            $raw = @(Get-ChannelForgeRawM3UProjection -Channel $channels -LogicalSourceId $logicalId -CandidateContractVersion $CandidateContractVersion)
             [void]$sourceList.Add([pscustomobject]@{
                     LogicalSourceId = $logicalId
                     Channels = @($channels)
                     Raw = $raw
                     SourceName = [string]$source.Name
                     SourceOrdinal = $index
                    SourcePath = $path
                 })
             $index++
         }
         if ($sourceList.Count -eq 0) { throw 'No enabled local provider playlist is configured.' }
         $sourceList = @($sourceList | Sort-Object LogicalSourceId)
         $mergeSources = @($sourceList | ForEach-Object {
                 [pscustomobject]@{
                     Channels = $_.Channels
                     Provider = $providerConfig.provider
                     Playlist = $_.SourceName
                     OrderKey = $_.LogicalSourceId
                 }
             })
         $merge = Merge-ChannelForgeLineup -Source $mergeSources -AliasPath $aliasPath -NumberingBlocksPath $blocksPath
     }
     foreach ($sourceRecord in @($sourceList)) {
         $sourceRecord.Raw = @($sourceRecord.Raw | Sort-Object EntryId)
         $sourceRecord.Channels = @($sourceRecord.Raw | ForEach-Object Channel)
     }
     if ([string]::IsNullOrWhiteSpace($M3UPath)) {
         $merge = Merge-ChannelForgeLineup -Source @($sourceList | ForEach-Object {
                 [pscustomobject]@{
                     Channels = $_.Channels
                     Provider = $providerConfig.provider
                     Playlist = $_.SourceName
                     OrderKey = $_.LogicalSourceId
                 }
             }) -AliasPath $aliasPath -NumberingBlocksPath $blocksPath
     }
     else {
         $merge.Channels = @($sourceList | ForEach-Object Channels)
     }
     $rawAll = @($sourceList | ForEach-Object Raw)
     $inputArtifactHashes = [System.Collections.Generic.List[object]]::new()
     foreach ($sourceRecord in @($sourceList)) {
         [void]$inputArtifactHashes.Add([pscustomobject][ordered]@{
                 LogicalSourceId = [string]$sourceRecord.LogicalSourceId
                 ArtifactKind = 'M3U'
                 ArtifactHash = Get-ChannelForgeDomainHash -Domain 'input-m3u/v2' -Bytes ([System.IO.File]::ReadAllBytes([string]$sourceRecord.SourcePath))
             })
     }
     $txRoot = Join-Path (Join-Path $outputRoot 'candidates\.staging') $TransactionId
     New-Item -ItemType Directory -Force -Path $txRoot | Out-Null
     $m3uTemp = Join-Path $txRoot 'merged.m3u'
     $merge.Channels | Export-ChannelForgeM3UPlaylist -Path $m3uTemp
     $m3uBytes = [System.IO.File]::ReadAllBytes($m3uTemp)
     Remove-Item -LiteralPath $m3uTemp -Force
     $xmltvBytes = $null
     $rawXmltv = @()
     $programmes = @()
     if (-not [string]::IsNullOrWhiteSpace($XMLTVPath)) {
         $xmlPath = [System.IO.Path]::GetFullPath($XMLTVPath)
         Assert-ChannelForgeReadPath -Path $xmlPath -AllowedRoot $Root
         $xmlStatus = [ordered]@{}
        $programmes = @(Import-ChannelForgeXmltvSource -Path $xmlPath -SourceId 'candidate-xmltv' -AcquisitionStatus $xmlStatus -CandidateContractVersion $CandidateContractVersion)
        $xmlMerge = Merge-ChannelForgeXmltvProgrammes -Programme $programmes
        $xmlTemp = Join-Path $txRoot 'merged.xml'
        Export-ChannelForgeXmltv -MergeResult $xmlMerge -Path $xmlTemp -AllowedRoot $txRoot
        $xmltvBytes = [System.IO.File]::ReadAllBytes($xmlTemp)
        Remove-Item -LiteralPath $xmlTemp -Force
        $rawXmltv = @(Get-ChannelForgeRawXmltvProjection -Programme $programmes -CandidateContractVersion $CandidateContractVersion)
         foreach ($logicalSourceId in @($rawXmltv | ForEach-Object { [string]$_.LogicalSourceId } | Sort-Object -Unique)) {
             [void]$inputArtifactHashes.Add([pscustomobject][ordered]@{
                     LogicalSourceId = $logicalSourceId
                     ArtifactKind = 'XMLTV'
                     ArtifactHash = [string]$xmlStatus.InputArtifactHash
                 })
         }
     }
     $binding = if ($programmes.Count -gt 0) {
         Resolve-ChannelForgeM3UXmltvBinding -Channel @($merge.Channels) -Programme $programmes -M3UIdentityCollisions @($merge.IdentityCollisions)
     }
    else {
        [pscustomobject]@{ ExactBindings=@(); UnboundChannels=@(); ReviewNeeded=@(); OrphanedXmltvChannels=@() }
    }
    $serializedM3UEntryOrder = @($merge.Channels | ForEach-Object { $channel = $_; @($rawAll | Where-Object { $_.Channel -eq $channel } | Select-Object -First 1 | ForEach-Object EntryId) })
         $manifestArguments = @{
             RawM3UOccurrences = $rawAll
             M3UIdentityCollisions = @($merge.IdentityCollisions)
             RawXmltvOccurrences = $rawXmltv
             IdentityBindingResult = $binding
             M3UBytes = $m3uBytes
             XMLTVBytes = $xmltvBytes
             InputArtifactHashes = @($inputArtifactHashes.ToArray())
             SerializedM3UEntryOrder = $serializedM3UEntryOrder
             CandidateContractVersion = $CandidateContractVersion
             SelectedSourceIds = @($inputArtifactHashes | ForEach-Object { [string]$_.LogicalSourceId } | Sort-Object -Unique)
         }
     $manifestResult = ConvertTo-ChannelForgeCandidateManifest @manifestArguments
     $counts = Get-ChannelForgeCandidateReviewCounts `
         -RawM3UOccurrences @($rawAll) `
         -RawXmltvOccurrences @($rawXmltv) `
         -BindingProjection @($manifestResult.BindingProjection)
     $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
     $review = [ordered]@{
         Version = $CandidateContractVersion
         BuildIdentity = $manifestResult.BuildIdentity
         ReviewRecords = @($manifestResult.Manifest.ReviewRecords)
         M3UIdentityCollisions = @($manifestResult.Manifest.M3UIdentityCollisions)
         RawM3UOccurrenceCount = [int]$counts.RawM3UOccurrenceCount
         RawXMLTVOccurrenceCount = [int]$counts.RawXMLTVOccurrenceCount
         ExactBindingCount = [int]$counts.ExactBindingCount
         UnboundCount = [int]$counts.UnboundCount
         ReviewNeededCount = [int]$counts.ReviewNeededCount
         XMLTVOnlyCount = [int]$counts.XMLTVOnlyCount
     }
     $reviewBytes = $utf8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $review))
     $reviewMarkdown = @(
         '# ChannelForge Lineup Change Review'
         ''
         "Build identity: $($manifestResult.BuildIdentity)"
         "Exact bindings: $($counts.ExactBindingCount)"
         "Unbound M3U channels: $($counts.UnboundCount)"
         "Review-needed identities: $($counts.ReviewNeededCount)"
         "XMLTV-only channels: $($counts.XMLTVOnlyCount)"
         ''
         'This is a candidate-only report. Accepted state and public merged artifacts are unchanged.'
     ) -join "`n"
     $reviewMdBytes = $utf8.GetBytes($reviewMarkdown + "`n")
     $manifestArguments.ReviewJSONBytes = $reviewBytes
     $manifestArguments.ReviewMarkdownBytes = $reviewMdBytes
     $manifestArguments.ReviewCounts = $counts
     $manifestResult = ConvertTo-ChannelForgeCandidateManifest @manifestArguments
     $manifest = [ordered]@{}
     foreach ($p in @($manifestResult.Manifest.PSObject.Properties)) { $manifest[$p.Name] = $p.Value }
     $manifestHash = [string]$manifestResult.CandidateManifestHash
     $manifest.CandidateManifestHash = $manifestHash
     $manifestBytes = $utf8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $manifest))
    try {
        Write-ChannelForgeCandidateArtifact -Path (Join-Path $txRoot 'merged.m3u') -Bytes $m3uBytes -HookPrefix 'CandidateStageWrite.M3U' -FaultHook $FaultHook | Out-Null
        if ($null -ne $xmltvBytes) {
            Write-ChannelForgeCandidateArtifact -Path (Join-Path $txRoot 'merged.xml') -Bytes $xmltvBytes -HookPrefix 'CandidateStageWrite.XMLTV' -FaultHook $FaultHook | Out-Null
        }
        Write-ChannelForgeCandidateArtifact -Path (Join-Path $txRoot 'lineup-change-review.json') -Bytes $reviewBytes -HookPrefix 'CandidateStageWrite.ReviewJSON' -FaultHook $FaultHook | Out-Null
        Write-ChannelForgeCandidateArtifact -Path (Join-Path $txRoot 'lineup-change-review.md') -Bytes $reviewMdBytes -HookPrefix 'CandidateStageWrite.ReviewMarkdown' -FaultHook $FaultHook | Out-Null
        Write-ChannelForgeCandidateArtifact -Path (Join-Path $txRoot 'manifest.json') -Bytes $manifestBytes -HookPrefix 'CandidateStageWrite.Manifest' -FaultHook $FaultHook | Out-Null
        $finalPath = Publish-ChannelForgeCandidateNamespace -OutputRoot $outputRoot -StagingPath $txRoot -CandidateManifestHash $manifestHash -FaultHook $FaultHook
        [pscustomobject][ordered]@{ CandidateManifestHash = $manifestHash; BuildIdentity = $manifestResult.BuildIdentity; CandidateDirectory = $finalPath; Manifest = [pscustomobject]$manifest }
    }
    catch {
        if (Test-Path -LiteralPath $txRoot) {
            Remove-Item -LiteralPath $txRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}
