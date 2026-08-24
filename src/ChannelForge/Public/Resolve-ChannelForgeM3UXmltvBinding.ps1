function Resolve-ChannelForgeM3UXmltvBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [Channel[]]$Channel,

        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Programme
    )

    function Get-IdentityText {
        param(
            [AllowNull()]
            [object]$Value
        )

        if ($null -eq $Value) {
            return ''
        }

        return ([string]$Value).Trim()
    }

    function Get-EvidenceIdentityKey {
        param(
            [AllowNull()]
            [object]$Evidence,

            [Parameter(Mandatory)]
            [string]$SourceId,

            [Parameter(Mandatory)]
            [string]$ChannelId
        )

        if ($null -eq $Evidence) {
            return "no-evidence`u{001f}$SourceId`u{001f}$ChannelId"
        }

        $sourcePath = if ($null -ne $Evidence.PSObject.Properties['SourcePath']) {
            [string]$Evidence.SourcePath
        }
        else {
            ''
        }
        $sourceReference = if ($null -ne $Evidence.PSObject.Properties['SourceReference']) {
            [string]$Evidence.SourceReference
        }
        else {
            ''
        }
        $documentBytes = if ($null -ne $Evidence.PSObject.Properties['DocumentBytes']) {
            [string]$Evidence.DocumentBytes
        }
        else {
            ''
        }

        return "evidence`u{001f}$SourceId`u{001f}$sourcePath`u{001f}$sourceReference`u{001f}$documentBytes"
    }

    function Get-EvidenceSortKey {
        param(
            [AllowNull()]
            [object]$Evidence
        )

        if ($null -eq $Evidence) {
            return ''
        }

        $sourceId = if ($null -ne $Evidence.PSObject.Properties['SourceId']) {
            Get-IdentityText $Evidence.SourceId
        }
        else {
            ''
        }
        $sourceKind = if ($null -ne $Evidence.PSObject.Properties['SourceKind']) {
            Get-IdentityText $Evidence.SourceKind
        }
        else {
            'local'
        }
        $sourceReference = if ($null -ne $Evidence.PSObject.Properties['SourceReference']) {
            Get-IdentityText $Evidence.SourceReference
        }
        else {
            ''
        }
        $sourcePath = if ($null -ne $Evidence.PSObject.Properties['SourcePath']) {
            Get-IdentityText $Evidence.SourcePath
        }
        else {
            ''
        }

        return @(
            $sourceId
            $sourceKind
            $sourceReference
            $sourcePath
            [string]$Evidence.ProgrammeCount
            [string]$Evidence.ChannelCount
            [string]$Evidence.DocumentBytes
        ) -join [char]31
    }

    function ConvertTo-CandidateRecord {
        param(
            [Parameter(Mandatory)]
            [object]$Candidate
        )

        $orderedEvidence = [System.Collections.Generic.List[object]]::new()
        foreach ($evidence in @($Candidate.Evidence)) {
            [void]$orderedEvidence.Add($evidence)
        }
        $orderedEvidence.Sort([System.Comparison[object]]{
                param($left, $right)
                return [System.StringComparer]::Ordinal.Compare(
                    (Get-EvidenceSortKey -Evidence $left),
                    (Get-EvidenceSortKey -Evidence $right))
            })

        return [pscustomobject][ordered]@{
            SourceId          = $Candidate.SourceId
            XmltvChannelId    = $Candidate.XmltvChannelId
            DeclarationCount  = [int]$Candidate.DeclarationCount
            ProgrammeCount    = [int]$Candidate.ProgrammeCount
            Evidence          = @($orderedEvidence.ToArray())
        }
    }

    function ConvertTo-CandidateRecords {
        param(
            [AllowNull()]
            [AllowEmptyCollection()]
            [object[]]$Candidates
        )

        $orderedCandidates = [System.Collections.Generic.List[object]]::new()
        foreach ($candidate in @($Candidates)) {
            if ($null -eq $candidate) {
                continue
            }
            [void]$orderedCandidates.Add((ConvertTo-CandidateRecord -Candidate $candidate))
        }
        $orderedCandidates.Sort([System.Comparison[object]]{
                param($left, $right)
                $comparison = [System.StringComparer]::Ordinal.Compare(
                    [string]$left.XmltvChannelId,
                    [string]$right.XmltvChannelId)
                if ($comparison -ne 0) {
                    return $comparison
                }

                return [System.StringComparer]::Ordinal.Compare(
                    [string]$left.SourceId,
                    [string]$right.SourceId)
            })

        return @($orderedCandidates.ToArray())
    }

    function Get-ChannelSortKey {
        param(
            [Parameter(Mandatory)]
            [object]$Record
        )

        return @(
            [string]$Record.TvgId
            [string]$Record.DisplayName
            [string]$Record.AssignedNumber
            [string]$Record.Channel.Provider
            [string]$Record.Channel.Playlist
            [string]$Record.Channel.OriginalName
        ) -join [char]31
    }

    $candidateByKey = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal)
    $programmeCountsByCandidateKey = [System.Collections.Generic.Dictionary[string, int]]::new(
        [System.StringComparer]::Ordinal)
    $processedEvidenceKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    function Add-CandidateOccurrence {
        param(
            [Parameter(Mandatory)]
            [string]$SourceId,

            [Parameter(Mandatory)]
            [string]$ChannelId,

            [Parameter(Mandatory)]
            [int]$OccurrenceCount,

            [AllowNull()]
            [object]$Evidence,

            [Parameter(Mandatory)]
            [string]$EvidenceKey
        )

        if ($OccurrenceCount -le 0) {
            throw 'XMLTV evidence channel identity occurrence must be positive.'
        }

        $candidateKey = "$SourceId`u{001f}$ChannelId"
        if (-not $candidateByKey.ContainsKey($candidateKey)) {
            $candidateByKey[$candidateKey] = [pscustomobject]@{
                SourceId          = $SourceId
                XmltvChannelId    = $ChannelId
                DeclarationCount  = 0
                ProgrammeCount    = 0
                Evidence          = [System.Collections.Generic.List[object]]::new()
                EvidenceKeys      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            }
        }

        $candidate = $candidateByKey[$candidateKey]
        if ($candidate.EvidenceKeys.Add($EvidenceKey)) {
            $candidate.DeclarationCount += $OccurrenceCount
            if ($null -ne $Evidence) {
                [void]$candidate.Evidence.Add($Evidence)
            }
        }
    }

    function Get-EvidenceOccurrences {
        param(
            [AllowNull()]
            [object]$Evidence,

            [Parameter(Mandatory)]
            [string]$FallbackChannelId
        )

        $occurrences = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $Evidence -and $null -ne $Evidence.PSObject.Properties['ChannelIdOccurrences'] -and
            @($Evidence.ChannelIdOccurrences).Count -gt 0) {
            foreach ($occurrence in @($Evidence.ChannelIdOccurrences)) {
                $occurrenceId = if ($null -ne $occurrence.PSObject.Properties['Id']) {
                    Get-IdentityText $occurrence.Id
                }
                else {
                    ''
                }
                $occurrenceCount = if ($null -ne $occurrence.PSObject.Properties['OccurrenceCount']) {
                    [int]$occurrence.OccurrenceCount
                }
                else {
                    0
                }

                if ([string]::IsNullOrWhiteSpace($occurrenceId) -or $occurrenceCount -le 0) {
                    throw 'XMLTV evidence contains an invalid channel identity occurrence.'
                }

                [void]$occurrences.Add([pscustomobject]@{
                        Id              = $occurrenceId
                        OccurrenceCount = $occurrenceCount
                    })
            }
        }
        elseif ($null -ne $Evidence -and $null -ne $Evidence.PSObject.Properties['ChannelIds'] -and
            @($Evidence.ChannelIds).Count -gt 0) {
            foreach ($channelId in @($Evidence.ChannelIds)) {
                $normalizedId = Get-IdentityText $channelId
                if (-not [string]::IsNullOrWhiteSpace($normalizedId)) {
                    [void]$occurrences.Add([pscustomobject]@{
                            Id              = $normalizedId
                            OccurrenceCount = 1
                        })
                }
            }
        }

        if ($occurrences.Count -eq 0) {
            [void]$occurrences.Add([pscustomobject]@{
                    Id              = $FallbackChannelId
                    OccurrenceCount = 1
                })
        }

        return @($occurrences.ToArray())
    }

    foreach ($programmeValue in @($Programme)) {
        if ($null -eq $programmeValue) {
            continue
        }
        if ($programmeValue -isnot [Programme]) {
            throw 'M3U/XMLTV binding requires Programme domain objects.'
        }

        $sourceId = Get-IdentityText $programmeValue.SourceId
        $programmeChannelId = Get-IdentityText $programmeValue.ChannelId
        if ([string]::IsNullOrWhiteSpace($sourceId) -or
            [string]::IsNullOrWhiteSpace($programmeChannelId)) {
            throw 'M3U/XMLTV binding requires non-empty Programme SourceId and ChannelId values.'
        }

        $evidence = $programmeValue.Evidence
        if ($null -ne $evidence -and $null -ne $evidence.PSObject.Properties['SourceId']) {
            $evidenceSourceId = Get-IdentityText $evidence.SourceId
            if (-not [string]::IsNullOrWhiteSpace($evidenceSourceId) -and
                -not [string]::Equals($sourceId, $evidenceSourceId, [System.StringComparison]::Ordinal)) {
                throw "Programme SourceId '$sourceId' does not match XMLTV evidence SourceId '$evidenceSourceId'."
            }
        }

        $evidenceKey = Get-EvidenceIdentityKey `
            -Evidence $evidence `
            -SourceId $sourceId `
            -ChannelId $programmeChannelId

        $hasEvidenceCatalog = $null -ne $evidence -and (
            ($null -ne $evidence.PSObject.Properties['ChannelIdOccurrences'] -and @($evidence.ChannelIdOccurrences).Count -gt 0) -or
            ($null -ne $evidence.PSObject.Properties['ChannelIds'] -and @($evidence.ChannelIds).Count -gt 0)
        )
        if (-not $hasEvidenceCatalog) {
            $evidenceKey = "$evidenceKey`u{001f}$programmeChannelId"
        }

        if ($processedEvidenceKeys.Add($evidenceKey)) {
            $occurrences = Get-EvidenceOccurrences `
                -Evidence $evidence `
                -FallbackChannelId $programmeChannelId
            foreach ($occurrence in @($occurrences)) {
                Add-CandidateOccurrence `
                    -SourceId $sourceId `
                    -ChannelId (Get-IdentityText $occurrence.Id) `
                    -OccurrenceCount ([int]$occurrence.OccurrenceCount) `
                    -Evidence $evidence `
                    -EvidenceKey $evidenceKey
            }
        }

        $programmeCandidateKey = "$sourceId`u{001f}$programmeChannelId"
        if ($programmeCountsByCandidateKey.ContainsKey($programmeCandidateKey)) {
            $programmeCountsByCandidateKey[$programmeCandidateKey]++
        }
        else {
            $programmeCountsByCandidateKey[$programmeCandidateKey] = 1
        }

        if ($hasEvidenceCatalog -and -not $candidateByKey.ContainsKey($programmeCandidateKey)) {
            throw "Programme ChannelId '$programmeChannelId' is absent from its XMLTV evidence channel catalog."
        }
    }

    foreach ($programmeCandidateKey in @($programmeCountsByCandidateKey.Keys)) {
        if ($candidateByKey.ContainsKey($programmeCandidateKey)) {
            $candidateByKey[$programmeCandidateKey].ProgrammeCount = $programmeCountsByCandidateKey[$programmeCandidateKey]
        }
    }

    $candidatesByChannelId = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($candidate in @($candidateByKey.Values)) {
        if (-not $candidatesByChannelId.ContainsKey($candidate.XmltvChannelId)) {
            $candidatesByChannelId[$candidate.XmltvChannelId] = [System.Collections.Generic.List[object]]::new()
        }

        [void]$candidatesByChannelId[$candidate.XmltvChannelId].Add($candidate)
    }

    $channelRecords = [System.Collections.Generic.List[object]]::new()
    $m3uChannelsById = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($channelValue in @($Channel)) {
        if ($null -eq $channelValue) {
            continue
        }
        if ($channelValue -isnot [Channel]) {
            throw 'M3U/XMLTV binding requires Channel domain objects.'
        }

        $record = [pscustomobject]@{
            Channel         = $channelValue
            TvgId           = Get-IdentityText $channelValue.TvgId
            DisplayName     = Get-IdentityText $channelValue.DisplayName
            AssignedNumber  = if ($null -eq $channelValue.AssignedNumber) { '' } else { [string]$channelValue.AssignedNumber }
        }
        [void]$channelRecords.Add($record)

        if (-not [string]::IsNullOrWhiteSpace($record.TvgId)) {
            if (-not $m3uChannelsById.ContainsKey($record.TvgId)) {
                $m3uChannelsById[$record.TvgId] = [System.Collections.Generic.List[object]]::new()
            }

            [void]$m3uChannelsById[$record.TvgId].Add($record)
        }
    }

    $channelRecords.Sort([System.Comparison[object]]{
            param($left, $right)
            return [System.StringComparer]::Ordinal.Compare(
                (Get-ChannelSortKey -Record $left),
                (Get-ChannelSortKey -Record $right))
        })

    $exactBindings = [System.Collections.Generic.List[object]]::new()
    $unboundChannels = [System.Collections.Generic.List[object]]::new()
    $reviewNeeded = [System.Collections.Generic.List[object]]::new()

    foreach ($channelRecord in @($channelRecords.ToArray())) {
        $tvgId = $channelRecord.TvgId
        if ([string]::IsNullOrWhiteSpace($tvgId)) {
            [void]$unboundChannels.Add([pscustomobject][ordered]@{
                    M3UChannel      = $channelRecord.Channel
                    TvgId           = ''
                    DisplayName     = $channelRecord.DisplayName
                    Status          = 'Unbound'
                    Publishable     = $false
                    Reason          = 'MissingTvgId'
                    Candidates      = @()
                    Evidence        = @()
                })
            continue
        }

        $xmltvCandidates = if ($candidatesByChannelId.ContainsKey($tvgId)) {
            @($candidatesByChannelId[$tvgId].ToArray())
        }
        else {
            @()
        }
        $candidateRecords = ConvertTo-CandidateRecords -Candidates $xmltvCandidates

        $m3uIdentityCount = $m3uChannelsById[$tvgId].Count
        if ($m3uIdentityCount -gt 1) {
            [void]$reviewNeeded.Add([pscustomobject][ordered]@{
                    M3UChannel      = $channelRecord.Channel
                    TvgId           = $tvgId
                    DisplayName     = $channelRecord.DisplayName
                    Status          = 'NeedsReview'
                    Publishable     = $false
                    Reason          = 'MultipleM3UChannelsShareTvgId'
                    Candidates      = $candidateRecords
                    Evidence        = @($candidateRecords | ForEach-Object { $_.Evidence })
                })
            continue
        }

        if ($xmltvCandidates.Count -eq 0) {
            [void]$unboundChannels.Add([pscustomobject][ordered]@{
                    M3UChannel      = $channelRecord.Channel
                    TvgId           = $tvgId
                    DisplayName     = $channelRecord.DisplayName
                    Status          = 'Unbound'
                    Publishable     = $false
                    Reason          = 'TvgIdNotFoundInXmltv'
                    Candidates      = @()
                    Evidence        = @()
                })
            continue
        }

        if ($xmltvCandidates.Count -gt 1) {
            [void]$reviewNeeded.Add([pscustomobject][ordered]@{
                    M3UChannel      = $channelRecord.Channel
                    TvgId           = $tvgId
                    DisplayName     = $channelRecord.DisplayName
                    Status          = 'NeedsReview'
                    Publishable     = $false
                    Reason          = 'AmbiguousXmltvChannelId'
                    Candidates      = $candidateRecords
                    Evidence        = @($candidateRecords | ForEach-Object { $_.Evidence })
                })
            continue
        }

        $candidate = $xmltvCandidates[0]
        if ([int]$candidate.DeclarationCount -ne 1) {
            [void]$reviewNeeded.Add([pscustomobject][ordered]@{
                    M3UChannel      = $channelRecord.Channel
                    TvgId           = $tvgId
                    DisplayName     = $channelRecord.DisplayName
                    Status          = 'NeedsReview'
                    Publishable     = $false
                    Reason          = 'DuplicateXmltvChannelIdDeclaration'
                    Candidates      = $candidateRecords
                    Evidence        = @($candidateRecords | ForEach-Object { $_.Evidence })
                })
            continue
        }

        [void]$exactBindings.Add([pscustomobject][ordered]@{
                M3UChannel       = $channelRecord.Channel
                TvgId            = $tvgId
                DisplayName      = $channelRecord.DisplayName
                XmltvChannelId   = $candidate.XmltvChannelId
                XmltvSourceId    = $candidate.SourceId
                Status           = 'Exact'
                Publishable      = $true
                Reason           = 'ExactOrdinalTvgIdMatch'
                Candidates       = $candidateRecords
                Evidence         = @($candidate.Evidence.ToArray())
            })
    }

    $m3uIdentityIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($channelRecord in @($channelRecords.ToArray())) {
        if (-not [string]::IsNullOrWhiteSpace($channelRecord.TvgId)) {
            [void]$m3uIdentityIds.Add($channelRecord.TvgId)
        }
    }

    $orderedXmltvIds = [System.Collections.Generic.List[string]]::new()
    foreach ($channelId in @($candidatesByChannelId.Keys)) {
        [void]$orderedXmltvIds.Add([string]$channelId)
    }
    $orderedXmltvIds.Sort([System.StringComparer]::Ordinal)

    $orphanedXmltvChannels = [System.Collections.Generic.List[object]]::new()
    foreach ($channelId in @($orderedXmltvIds.ToArray())) {
        if ($m3uIdentityIds.Contains($channelId)) {
            continue
        }

        $candidateRecords = ConvertTo-CandidateRecords `
            -Candidates @($candidatesByChannelId[$channelId].ToArray())
        [void]$orphanedXmltvChannels.Add([pscustomobject][ordered]@{
                XmltvChannelId = $channelId
                Status         = 'OrphanedXmltv'
                Publishable    = $false
                Reason         = 'NoM3UChannelWithTvgId'
                Candidates     = $candidateRecords
                Evidence       = @($candidateRecords | ForEach-Object { $_.Evidence })
            })
    }

    $status = if ($exactBindings.Count -eq 0 -and
        $unboundChannels.Count -eq 0 -and
        $reviewNeeded.Count -eq 0 -and
        $orphanedXmltvChannels.Count -eq 0) {
        'NOT_EVALUATED'
    }
    elseif ($reviewNeeded.Count -gt 0) {
        'EVALUATED_WITH_REVIEW'
    }
    elseif ($unboundChannels.Count -gt 0 -or $orphanedXmltvChannels.Count -gt 0) {
        'EVALUATED_WITH_UNBOUND'
    }
    else {
        'EXACT_ONLY'
    }

    return [pscustomobject][ordered]@{
        Status                    = $status
        ExactBindings             = @($exactBindings.ToArray())
        PublishableBindings       = @($exactBindings.ToArray())
        UnboundChannels            = @($unboundChannels.ToArray())
        ReviewNeeded              = @($reviewNeeded.ToArray())
        OrphanedXmltvChannels     = @($orphanedXmltvChannels.ToArray())
        ExactBindingCount         = $exactBindings.Count
        UnboundChannelCount       = $unboundChannels.Count
        ReviewNeededCount         = $reviewNeeded.Count
        OrphanedXmltvChannelCount = $orphanedXmltvChannels.Count
        HasReviewNeeded            = ($reviewNeeded.Count -gt 0)
    }
}
