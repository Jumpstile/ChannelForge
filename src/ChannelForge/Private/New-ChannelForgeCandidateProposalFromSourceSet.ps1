function New-ChannelForgeCandidateProposalFromSourceSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object[]]$PlaylistSources,
        [AllowEmptyCollection()][object[]]$GuideSources = @(),
        [AllowEmptyCollection()][object[]]$Bindings = @(),
        [Parameter(Mandatory)][string]$OutputRoot,
        [string]$TransactionId = ([guid]::NewGuid().ToString('N').ToLowerInvariant()),
        [string]$FaultHook = '',
        [ValidateSet('blocker-2-contract/v7')]
        [string]$CandidateContractVersion = 'blocker-2-contract/v7'
    )

    if (@($PlaylistSources).Count -eq 0) { throw 'A source-set candidate requires at least one playlist.' }
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $outputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
    $aliasPath = Join-Path $rootFull 'data\rules\aliases.json'
    $blocksPath = Join-Path $rootFull 'data\lineup\numbering_blocks.json'
    $sourceList = [System.Collections.Generic.List[object]]::new()

    $orderedPlaylists = @($PlaylistSources | Sort-Object Priority, SourceId)
    $playlistOrdinal = 0
    foreach ($source in $orderedPlaylists) {
        $path = [System.IO.Path]::GetFullPath([string]$source.Path)
        Assert-ChannelForgeReadPath -Path $path -AllowedRoot $rootFull
        $logicalSourceId = Get-ChannelForgeLogicalSourceId `
            -ProviderName 'candidate' `
            -SourceName ([string]$source.Label) `
            -SourceKind 'M3U' `
            -SourceOrdinal $playlistOrdinal
        $channels = @(Import-ChannelForgeM3UPlaylist `
                -Path $path `
                -Provider 'candidate' `
                -Playlist ([string]$source.Label) `
                -CandidateContractVersion $CandidateContractVersion)
        $raw = @(Get-ChannelForgeRawM3UProjection `
                -Channel $channels `
                -LogicalSourceId $logicalSourceId `
                -CandidateContractVersion $CandidateContractVersion)
        [void]$sourceList.Add([pscustomobject]@{
                LogicalSourceId = $logicalSourceId
                SourceId = [string]$source.SourceId
                SourceKey = [string]$source.SourceKey
                Label = [string]$source.Label
                Priority = [int]$source.Priority
                Channels = @($channels)
                Raw = $raw
                SourceOrdinal = $playlistOrdinal
                SourcePath = $path
            })
        $playlistOrdinal++
    }

    $mergeSources = @($sourceList | ForEach-Object {
            [pscustomobject]@{
                Channels = $_.Channels
                Provider = 'candidate'
                Playlist = $_.Label
                OrderKey = '{0:D10}' -f $_.SourceOrdinal
            }
        })
    $merge = Merge-ChannelForgeLineup `
        -Source $mergeSources `
        -AliasPath $aliasPath `
        -NumberingBlocksPath $blocksPath `
        -CandidateContractVersion $CandidateContractVersion
    foreach ($sourceRecord in @($sourceList)) {
        $sourceRecord.Raw = @($sourceRecord.Raw | Sort-Object EntryId)
        $sourceRecord.Channels = @($sourceRecord.Raw | ForEach-Object Channel)
    }

    $rawAll = @($sourceList | ForEach-Object Raw)
    $inputArtifactHashes = [System.Collections.Generic.List[object]]::new()
    foreach ($sourceRecord in @($sourceList)) {
        [void]$inputArtifactHashes.Add([pscustomobject][ordered]@{
                LogicalSourceId = [string]$sourceRecord.LogicalSourceId
                ArtifactKind = 'M3U'
                ArtifactHash = Get-ChannelForgeDomainHash `
                    -Domain 'input-m3u/v2' `
                    -Bytes ([System.IO.File]::ReadAllBytes([string]$sourceRecord.SourcePath))
            })
    }

    $guideRecords = [System.Collections.Generic.List[object]]::new()
    $guideOrdinal = 0
    foreach ($guide in @($GuideSources | Sort-Object Priority, SourceId)) {
        $logicalSourceId = Get-ChannelForgeLogicalSourceId `
            -ProviderName 'candidate' `
            -SourceName ([string]$guide.Label) `
            -SourceKind 'XMLTV' `
            -SourceOrdinal $guideOrdinal
        [void]$guideRecords.Add([pscustomobject]@{
                SourceId = [string]$guide.SourceId
                LogicalSourceId = $logicalSourceId
                SourceKey = [string]$guide.SourceKey
                Label = [string]$guide.Label
                Priority = [int]$guide.Priority
                Path = [string]$guide.Path
                Url = $guide.Url
            })
        $guideOrdinal++
    }

    $programmesForOutput = [System.Collections.Generic.List[object]]::new()
    $rawXmltv = [System.Collections.Generic.List[object]]::new()
    $bindingResults = [System.Collections.Generic.List[object]]::new()
    $bindingByGuide = @{}
    foreach ($binding in @($Bindings)) { $bindingByGuide[[string]$binding.GuideId] = $binding }
    $playlistLogicalIdsBySourceId = @{}
    foreach ($sourceRecord in @($sourceList)) {
        $playlistLogicalIdsBySourceId[[string]$sourceRecord.SourceId] = [string]$sourceRecord.LogicalSourceId
    }

    foreach ($guide in @($guideRecords.ToArray())) {
        $xmlPath = [System.IO.Path]::GetFullPath([string]$guide.Path)
        Assert-ChannelForgeReadPath -Path $xmlPath -AllowedRoot $rootFull
        $xmlStatus = [ordered]@{}
        $guideProgrammes = @(Import-ChannelForgeXmltvSource `
                -Path $xmlPath `
                -SourceId ([string]$guide.LogicalSourceId) `
                -AcquisitionStatus $xmlStatus `
                -CandidateContractVersion $CandidateContractVersion)
        foreach ($raw in @(Get-ChannelForgeRawXmltvProjection `
                    -Programme $guideProgrammes `
                    -CandidateContractVersion $CandidateContractVersion)) {
            [void]$rawXmltv.Add($raw)
        }
        [void]$inputArtifactHashes.Add([pscustomobject][ordered]@{
                LogicalSourceId = [string]$guide.LogicalSourceId
                ArtifactKind = 'XMLTV'
                ArtifactHash = [string]$xmlStatus.InputArtifactHash
            })

        $binding = if ($bindingByGuide.ContainsKey([string]$guide.SourceId)) {
            $bindingByGuide[[string]$guide.SourceId]
        }
        else {
            $null
        }
        $allowedLogicalSourceIds = if ($null -eq $binding) {
            @()
        }
        elseif ([bool]$binding.AppliesToAll) {
            @($sourceList | ForEach-Object LogicalSourceId)
        }
        else {
            @($binding.PlaylistIds | ForEach-Object {
                    if ($playlistLogicalIdsBySourceId.ContainsKey([string]$_)) {
                        $playlistLogicalIdsBySourceId[[string]$_]
                    }
                })
        }
        $allowedChannels = @($merge.AllChannels | Where-Object {
                [string]$_.LogicalSourceId -in $allowedLogicalSourceIds
            })
        $allowedChannelSet = [System.Collections.Generic.HashSet[object]]::new()
        foreach ($channel in $allowedChannels) { [void]$allowedChannelSet.Add($channel) }
        $allowedCollisions = @($merge.IdentityCollisions | Where-Object {
                @($_.Channels | Where-Object { $allowedChannelSet.Contains($_) }).Count -gt 0
            })
        $bindingResult = Resolve-ChannelForgeM3UXmltvBinding `
            -Channel $allowedChannels `
            -Programme $guideProgrammes `
            -M3UIdentityCollisions $allowedCollisions
        [void]$bindingResults.Add($bindingResult)
        if ($null -ne $binding) {
            foreach ($programme in $guideProgrammes) { [void]$programmesForOutput.Add($programme) }
        }
    }

    $bindingResult = [pscustomobject][ordered]@{
        Status = if (@($bindingResults | Where-Object { $_.HasReviewNeeded }).Count -gt 0) {
            'EVALUATED_WITH_REVIEW'
        }
        elseif (@($bindingResults | Where-Object { $_.Status -eq 'EVALUATED_WITH_UNBOUND' }).Count -gt 0) {
            'EVALUATED_WITH_UNBOUND'
        }
        elseif ($bindingResults.Count -gt 0) {
            'EXACT_ONLY'
        }
        else {
            'NOT_EVALUATED'
        }
        ExactBindings = @($bindingResults | ForEach-Object { @($_.ExactBindings) })
        PublishableBindings = @($bindingResults | ForEach-Object { @($_.PublishableBindings) })
        UnboundChannels = @($bindingResults | ForEach-Object { @($_.UnboundChannels) })
        ReviewNeeded = @($bindingResults | ForEach-Object { @($_.ReviewNeeded) })
        OrphanedXmltvChannels = @($bindingResults | ForEach-Object { @($_.OrphanedXmltvChannels) })
        ExactBindingCount = [int]@($bindingResults | ForEach-Object { @($_.ExactBindings) }).Count
        UnboundChannelCount = [int]@($bindingResults | ForEach-Object { @($_.UnboundChannels) }).Count
        ReviewNeededCount = [int]@($bindingResults | ForEach-Object { @($_.ReviewNeeded) }).Count
        OrphanedXmltvChannelCount = [int]@($bindingResults | ForEach-Object { @($_.OrphanedXmltvChannels) }).Count
        HasReviewNeeded = @($bindingResults | Where-Object { $_.HasReviewNeeded }).Count -gt 0
    }

    $txRoot = Join-Path (Join-Path $outputRoot 'candidates\.staging') $TransactionId
    New-Item -ItemType Directory -Force -Path $txRoot | Out-Null
    $m3uTemp = Join-Path $txRoot 'merged.m3u'
    $merge.Channels | Export-ChannelForgeM3UPlaylist -Path $m3uTemp
    $m3uBytes = [System.IO.File]::ReadAllBytes($m3uTemp)
    Remove-Item -LiteralPath $m3uTemp -Force

    $xmltvBytes = $null
    if ($programmesForOutput.Count -gt 0) {
        $xmlMerge = Merge-ChannelForgeXmltvProgrammes -Programme @($programmesForOutput.ToArray())
        $xmlTemp = Join-Path $txRoot 'merged.xml'
        Export-ChannelForgeXmltv -MergeResult $xmlMerge -Path $xmlTemp -AllowedRoot $txRoot
        $xmltvBytes = [System.IO.File]::ReadAllBytes($xmlTemp)
        Remove-Item -LiteralPath $xmlTemp -Force
    }

    $serializedM3UEntryOrder = @($merge.Channels | ForEach-Object {
            $channel = $_
            @($rawAll | Where-Object { $_.Channel -eq $channel } | Select-Object -First 1 | ForEach-Object EntryId)
        })
    $selectedLogicalSourceIds = @(
        @($sourceList) + @($guideRecords.ToArray()) |
            ForEach-Object LogicalSourceId |
            Sort-Object -Unique
    )
    $manifestArguments = @{
        RawM3UOccurrences = $rawAll
        M3UIdentityCollisions = @($merge.IdentityCollisions)
        RawXmltvOccurrences = @($rawXmltv.ToArray())
        IdentityBindingResult = $bindingResult
        M3UBytes = $m3uBytes
        XMLTVBytes = $xmltvBytes
        InputArtifactHashes = @($inputArtifactHashes.ToArray())
        SerializedM3UEntryOrder = $serializedM3UEntryOrder
        CandidateContractVersion = $CandidateContractVersion
        SelectedSourceIds = $selectedLogicalSourceIds
    }
    $manifestResult = ConvertTo-ChannelForgeCandidateManifest @manifestArguments
    $counts = Get-ChannelForgeCandidateReviewCounts `
        -RawM3UOccurrences $rawAll `
        -RawXmltvOccurrences @($rawXmltv.ToArray()) `
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
    foreach ($property in @($manifestResult.Manifest.PSObject.Properties)) { $manifest[$property.Name] = $property.Value }
    $manifestHash = [string]$manifestResult.CandidateManifestHash
    $manifest.CandidateManifestHash = $manifestHash
    $manifestBytes = $utf8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $manifest))

    try {
        Write-ChannelForgeCandidateArtifact `
            -Path (Join-Path $txRoot 'merged.m3u') `
            -Bytes $m3uBytes `
            -HookPrefix 'CandidateStageWrite.M3U' `
            -FaultHook $FaultHook | Out-Null
        if ($null -ne $xmltvBytes) {
            Write-ChannelForgeCandidateArtifact `
                -Path (Join-Path $txRoot 'merged.xml') `
                -Bytes $xmltvBytes `
                -HookPrefix 'CandidateStageWrite.XMLTV' `
                -FaultHook $FaultHook | Out-Null
        }
        Write-ChannelForgeCandidateArtifact `
            -Path (Join-Path $txRoot 'lineup-change-review.json') `
            -Bytes $reviewBytes `
            -HookPrefix 'CandidateStageWrite.ReviewJSON' `
            -FaultHook $FaultHook | Out-Null
        Write-ChannelForgeCandidateArtifact `
            -Path (Join-Path $txRoot 'lineup-change-review.md') `
            -Bytes $reviewMdBytes `
            -HookPrefix 'CandidateStageWrite.ReviewMarkdown' `
            -FaultHook $FaultHook | Out-Null
        Write-ChannelForgeCandidateArtifact `
            -Path (Join-Path $txRoot 'manifest.json') `
            -Bytes $manifestBytes `
            -HookPrefix 'CandidateStageWrite.Manifest' `
            -FaultHook $FaultHook | Out-Null
        $finalPath = Publish-ChannelForgeCandidateNamespace `
            -OutputRoot $outputRoot `
            -StagingPath $txRoot `
            -CandidateManifestHash $manifestHash `
            -FaultHook $FaultHook
        return [pscustomobject][ordered]@{
            CandidateManifestHash = $manifestHash
            BuildIdentity = $manifestResult.BuildIdentity
            CandidateDirectory = $finalPath
            Manifest = [pscustomobject]$manifest
        }
    }
    catch {
        if (Test-Path -LiteralPath $txRoot) {
            Remove-Item -LiteralPath $txRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}
