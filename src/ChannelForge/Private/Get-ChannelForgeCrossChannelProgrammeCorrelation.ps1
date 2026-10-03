function Get-ChannelForgeCrossChannelProgrammeCorrelation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][timespan]$NearTimeWindow,
        [Parameter(Mandatory)][datetimeoffset]$EvaluationTimeUtc,
        [AllowEmptyCollection()][object[]]$ContextualProgrammeAliases = @()
    )

    $contextualAliasesByKey = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($alias in @($ContextualProgrammeAliases)) {
        if ($null -eq $alias) { continue }
        $key = [string]$alias.ContextKey
        if ([string]::IsNullOrEmpty($key)) { continue }
        if (-not $contextualAliasesByKey.ContainsKey($key)) {
            $contextualAliasesByKey[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $contextualAliasesByKey[$key].Add($alias)
    }

    function Normalize-ProgrammeText {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { return '' }
        $text = ([string]$Value).Normalize([Text.NormalizationForm]::FormD).ToLowerInvariant()
        $text = [regex]::Replace($text, '\p{Mn}', '')
        return [regex]::Replace($text, '[^\p{L}\p{N}]+', ' ').Trim()
    }

    function Get-ProgrammeTitleSimilarity {
        param([string]$Left, [string]$Right)
        $leftText = Normalize-ProgrammeText $Left
        $rightText = Normalize-ProgrammeText $Right
        if (-not $leftText -or -not $rightText) { return 0.0 }
        if ($leftText -ceq $rightText) { return 1.0 }
        if ($leftText.Length -lt 8 -or $rightText.Length -lt 8) { return 0.0 }
        $leftTokens = @($leftText.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Sort-Object -Unique)
        $rightTokens = @($rightText.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Sort-Object -Unique)
        if ($leftTokens.Count -lt 2 -or $rightTokens.Count -lt 2) { return 0.0 }
        $intersection = @($leftTokens | Where-Object { $_ -in $rightTokens }).Count
        return (2.0 * $intersection) / ($leftTokens.Count + $rightTokens.Count)
    }


    function Test-ProgrammeIntervalsNear {
        param([object]$Left, [object]$Right)
        if ($null -eq $Left.StartUtc -or $null -eq $Left.StopUtc -or $null -eq $Right.StartUtc -or $null -eq $Right.StopUtc) { return $false }
        if ($Left.StartUtc -lt $Right.StopUtc -and $Right.StartUtc -lt $Left.StopUtc) { return $true }
        $gap = if ($Left.StopUtc -le $Right.StartUtc) { $Right.StartUtc - $Left.StopUtc } else { $Left.StartUtc - $Right.StopUtc }
        return $gap -le $NearTimeWindow
    }
    function Test-ExplicitTimezone {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { return $false }
        return ([string]$Value).Trim() -match '(?i)(?:Z|[+-]\d{2}:?\d{2})$'
    }
    function Get-ContextualAliasSides {
        param([Parameter(Mandatory)][object]$Left,[Parameter(Mandatory)][object]$Right)
        $orderedRows = if ([string]::CompareOrdinal([string]$Left.ChannelId,[string]$Right.ChannelId) -lt 0) { @($Left,$Right) } else { @($Right,$Left) }
        return @($orderedRows | ForEach-Object {
            [pscustomobject][ordered]@{
                ChannelId = [string]$_.ChannelId
                Title = [string]$_.Title
                Subtitle = if ($_.Subtitle) { [string]$_.Subtitle } else { $null }
                EventStatus = if ($_.EventStatus) { [string]$_.EventStatus } else { $null }
                ObservationId = [string]$_.ObservationId
                SourceId = [string]$_.SourceId
                SourceFamily = [string]$_.SourceFamily
                SourceRelationship = [string]$_.SourceRelationship
                EvidenceClass = [string]$_.EvidenceClass
                ChannelReference = if ($_.ChannelReference) { [string]$_.ChannelReference } else { $null }
                Description = if ($_.Description) { ConvertTo-ChannelForgeGuideSafeText -Value $_.Description -MaximumLength 512 } else { $null }
                CategoryKeys = @($_.CategoryKeys)
                Participants = @($_.Participants)
                EpisodeNumber = if ($_.EpisodeNumber) { [string]$_.EpisodeNumber } else { $null }
                Competition = if ($_.Competition) { [string]$_.Competition } else { $null }
                StartUtc = $_.StartUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",[Globalization.CultureInfo]::InvariantCulture)
                StopUtc = $_.StopUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",[Globalization.CultureInfo]::InvariantCulture)
                SourceRecordReference = if ($_.SourceRecordReference) { [string]$_.SourceRecordReference } else { $null }
                SourceDataTimeUtc = if ($_.SourceDataTimeUtc) { [string]$_.SourceDataTimeUtc } else { $null }
                ObservationTimeUtc = if ($_.ObservationTimeUtc) { [string]$_.ObservationTimeUtc } else { $null }
                FetchTimeUtc = if ($_.FetchTimeUtc) { [string]$_.FetchTimeUtc } else { $null }
            }
        })
    }
    function Get-ContextualAliasContextKey {
        param([Parameter(Mandatory)][object[]]$Sides)
        $projectionSides = @($Sides | ForEach-Object {
            [ordered]@{
                ChannelId = [string]$_.ChannelId
                Title = Normalize-ProgrammeText $_.Title
                Subtitle = Normalize-ProgrammeText $_.Subtitle
                EventStatus = Normalize-ProgrammeText $_.EventStatus
                CategoryKeys = @($_.CategoryKeys | ForEach-Object { Normalize-ProgrammeText $_ } | Where-Object { $_ } | Sort-Object -Unique)
                Participants = @($_.Participants | ForEach-Object { Normalize-ProgrammeText $_ } | Where-Object { $_ } | Sort-Object -Unique)
                EpisodeNumber = Normalize-ProgrammeText $_.EpisodeNumber
                Competition = Normalize-ProgrammeText $_.Competition
                StartUtc = $_.StartUtc
                StopUtc = $_.StopUtc
            }
        })
        return Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject ([ordered]@{ Sides = $projectionSides })
    }

    function Get-ContextualAliasMatch {
        param([Parameter(Mandatory)][object]$Left,[Parameter(Mandatory)][object]$Right)
        $sides = @(Get-ContextualAliasSides -Left $Left -Right $Right)
        $key = Get-ContextualAliasContextKey -Sides $sides
        if (-not $contextualAliasesByKey.ContainsKey($key)) { return $null }
        $matches = $contextualAliasesByKey[$key]
        if ($matches.Count -gt 1) { throw 'FAIL_CLOSED: duplicate contextual programme alias keys were supplied.' }
        $alias = $matches[0]
        if ([string]$alias.EntryId -cne $key -or [string]$alias.ScopeKind -cne 'Contextual') { throw 'FAIL_CLOSED: contextual programme alias identity is inconsistent.' }
        if ([string]$alias.ApprovalStatus -notin @('Proposed','Probationary','Approved','Rejected','Revoked')) { throw 'FAIL_CLOSED: contextual programme alias status is invalid.' }
        $from = if ($alias.EffectiveFromUtc) { [datetimeoffset]$alias.EffectiveFromUtc } else { [datetimeoffset]::MinValue }
        $to = if ($alias.EffectiveToUtc) { [datetimeoffset]$alias.EffectiveToUtc } else { [datetimeoffset]::MaxValue }
        if ($EvaluationTimeUtc.ToUniversalTime() -lt $from -or $EvaluationTimeUtc.ToUniversalTime() -ge $to) { return $null }
        return $alias
    }


    function Get-ProgrammeCandidate {
        param([object]$Left, [object]$Right)
        if (-not $Left.ChannelId -or -not $Right.ChannelId -or $Left.ChannelId -ceq $Right.ChannelId) { return $null }
        if ($Left.FreshnessState -in @('Stale', 'FutureDated') -or $Right.FreshnessState -in @('Stale', 'FutureDated')) { return $null }
        if (-not (Test-ProgrammeIntervalsNear -Left $Left -Right $Right)) { return $null }
        if (-not (Test-ExplicitTimezone $Left.DisplayStartValue) -or -not (Test-ExplicitTimezone $Left.DisplayStopValue) -or -not (Test-ExplicitTimezone $Right.DisplayStartValue) -or -not (Test-ExplicitTimezone $Right.DisplayStopValue)) { return $null }

        $leftEpisode = Normalize-ProgrammeText $Left.EpisodeNumber
        $rightEpisode = Normalize-ProgrammeText $Right.EpisodeNumber
        if ($leftEpisode -and $rightEpisode -and $leftEpisode -cne $rightEpisode) { return $null }
        $leftSubtitle = Normalize-ProgrammeText $Left.Subtitle
        $rightSubtitle = Normalize-ProgrammeText $Right.Subtitle
        if ($leftSubtitle -and $rightSubtitle -and $leftSubtitle -cne $rightSubtitle) { return $null }
        $leftParticipants = @($Left.Participants | ForEach-Object { Normalize-ProgrammeText $_ } | Where-Object { $_ } | Sort-Object -Unique)
        $rightParticipants = @($Right.Participants | ForEach-Object { Normalize-ProgrammeText $_ } | Where-Object { $_ } | Sort-Object -Unique)
        if ($leftParticipants.Count -gt 0 -and $rightParticipants.Count -gt 0 -and (($leftParticipants -join "`n") -cne ($rightParticipants -join "`n"))) { return $null }

        $leftStatus = Normalize-ProgrammeText $Left.EventStatus
        $rightStatus = Normalize-ProgrammeText $Right.EventStatus
        $leftLive = $leftStatus -match '(^| )live($| )'
        $rightLive = $rightStatus -match '(^| )live($| )'
        $leftReplay = $leftStatus -match 'replay|repeat|rerun'
        $rightReplay = $rightStatus -match 'replay|repeat|rerun'
        if (($leftLive -and $rightReplay) -or ($rightLive -and $leftReplay)) { return $null }
        $contextualAlias = Get-ContextualAliasMatch -Left $Left -Right $Right
        if ($null -ne $contextualAlias -and $contextualAlias.ApprovalStatus -eq 'Rejected') { return [pscustomobject]@{ Left = $Left; Right = $Right; RejectedAliasContext = $contextualAlias } }
        $similarity = Get-ProgrammeTitleSimilarity -Left $Left.Title -Right $Right.Title
        $basis = [System.Collections.Generic.List[string]]::new()
        $score = 0
        $leftCompetition = Normalize-ProgrammeText $Left.Competition
        $rightCompetition = Normalize-ProgrammeText $Right.Competition
        $sameCompetition = $leftCompetition -and $leftCompetition -ceq $rightCompetition
        $participantsMatch = $leftParticipants.Count -gt 0 -and $rightParticipants.Count -gt 0
        $startShift = [Math]::Abs(($Left.StartUtc - $Right.StartUtc).TotalMinutes)
        $leftDescription = Normalize-ProgrammeText $Left.Description
        $rightDescription = Normalize-ProgrammeText $Right.Description
        $descriptionSimilarity = Get-ProgrammeTitleSimilarity -Left $leftDescription -Right $rightDescription
        $matchingDescription = $leftDescription.Length -ge 40 -and $rightDescription.Length -ge 40 -and $descriptionSimilarity -ge 0.90
        $lowTitleStrongContext = $participantsMatch -and $sameCompetition -and $startShift -le 3
        if ($similarity -lt 0.72 -and -not $lowTitleStrongContext -and -not $matchingDescription) { return $null }
        if ($similarity -ge 0.98) { $score += 38; [void]$basis.Add('ExactNormalizedTitle') }
        elseif ($similarity -ge 0.72) { $score += 30; [void]$basis.Add('FuzzyTitle') }
        else { $score += 20; [void]$basis.Add('CorroboratedDifferentTitle') }
        if ($participantsMatch) { $score += 25; [void]$basis.Add('MatchingParticipants') }
        if ($sameCompetition) { $score += 18; [void]$basis.Add('MatchingCompetition') }
        $matchingSpecificSubtitle = $leftSubtitle -and $leftSubtitle -ceq $rightSubtitle -and $leftSubtitle.Length -ge 7 -and $leftSubtitle -notin @('live', 'replay', 'repeat', 'premiere', 'new')
        if ($matchingSpecificSubtitle) { $score += 15; [void]$basis.Add('MatchingSubtitle') }
        if ($leftEpisode -and $leftEpisode -ceq $rightEpisode) { $score += 18; [void]$basis.Add('MatchingEpisode') }
        $leftCategory = @($Left.CategoryKeys | ForEach-Object { Normalize-ProgrammeText $_ } | Where-Object { $_ } | Sort-Object -Unique)
        $rightCategory = @($Right.CategoryKeys | ForEach-Object { Normalize-ProgrammeText $_ } | Where-Object { $_ } | Sort-Object -Unique)
        $categoryMatch = $leftCategory.Count -gt 0 -and $rightCategory.Count -gt 0 -and @($leftCategory | Where-Object { $_ -in $rightCategory }).Count -gt 0
        if ($categoryMatch) { $score += 8; [void]$basis.Add('MatchingCategory') }
        if ($startShift -le 3) { $score += 20; [void]$basis.Add('NearStartTime') }
        elseif ($startShift -le $NearTimeWindow.TotalMinutes) { $score += 15; [void]$basis.Add('NearStartTime') }
        else { $score += 10; [void]$basis.Add('OverlappingIntervals') }
        if ($matchingDescription) { $score += 20; [void]$basis.Add('MatchingDescription') }

        $movieCategory = @($leftCategory | Where-Object { $_ -in @('movie', 'movies', 'film', 'films') -and $_ -in $rightCategory }).Count -gt 0
        if ($similarity -ge 0.98 -and $movieCategory -and $startShift -le 3) { $score += 12; [void]$basis.Add('MovieTitleAndAiring') }
        $freshForLearning = $Left.FreshnessState -eq 'Fresh' -and $Right.FreshnessState -eq 'Fresh'

        $strongEvidence = $participantsMatch -or $matchingSpecificSubtitle -or
            ($leftEpisode -and $leftEpisode -ceq $rightEpisode) -or
            $matchingDescription -or $lowTitleStrongContext -or
            ($similarity -ge 0.98 -and $movieCategory -and $startShift -le 3)
        if (-not $strongEvidence -or $score -lt 70) { return $null }
        if ($null -ne $contextualAlias -and $contextualAlias.ApprovalStatus -eq 'Approved') { $score += 10; [void]$basis.Add('ApprovedContextualAlias') }
        elseif ($null -ne $contextualAlias -and $contextualAlias.ApprovalStatus -eq 'Probationary') { $score += 5; [void]$basis.Add('ProbationaryContextualAlias') }
        return [pscustomobject][ordered]@{
            Left = $Left
            Right = $Right
            ConfidenceScore = [Math]::Min(100, $score)
            TitleSimilarity = $similarity
            FreshForLearning = $freshForLearning
            ContextualAlias = $contextualAlias
            Basis = @($basis | Sort-Object -Unique)
        }
    }

    $orderedRows = @($Rows | Where-Object { $null -ne $_.StartUtc -and $null -ne $_.StopUtc } | Sort-Object @{Expression={$_.StartUtc}}, @{Expression={$_.StopUtc}}, @{Expression={$_.ObservationId}})
    $edges = [System.Collections.Generic.List[object]]::new()
    $candidateCount = 0
    $rejectedAliases = [System.Collections.Generic.List[object]]::new()
    for ($leftIndex = 0; $leftIndex -lt $orderedRows.Count; $leftIndex++) {
        $left = $orderedRows[$leftIndex]
        for ($rightIndex = $leftIndex + 1; $rightIndex -lt $orderedRows.Count; $rightIndex++) {
            $right = $orderedRows[$rightIndex]
            if ($right.StartUtc -gt ($left.StopUtc + $NearTimeWindow)) { break }
            $candidate = Get-ProgrammeCandidate -Left $left -Right $right
            if ($null -ne $candidate) {
                if ($candidateCount -ge 256) { throw 'ComparisonCandidateLimitExceeded: cross-channel candidate limit exceeded.' }
                $candidateCount++
                if ($candidate.PSObject.Properties['RejectedAliasContext']) {
                    $pairIds = @(@($left.ObservationId,$right.ObservationId) | Sort-Object -Unique)
                    $channelIds = @(@($left.ChannelId,$right.ChannelId) | Sort-Object -Unique)
                    $titles = @(@($left.Title,$right.Title) | Sort-Object -Unique)
                    $sourceIds = @(@($left.SourceId,$right.SourceId) | Sort-Object -Unique)
                    [void]$rejectedAliases.Add([pscustomobject][ordered]@{ EntryId = [string]$candidate.RejectedAliasContext.EntryId; ContextKey = [string]$candidate.RejectedAliasContext.ContextKey; ObservationIds = $pairIds; SourceIds = $sourceIds; ChannelIds = $channelIds; Titles = $titles })
                } else { [void]$edges.Add($candidate) }
            }
        }
    }

    $edgeCounts = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($edge in $edges) {
        foreach ($key in @(
            "$($edge.Left.ObservationId)|$($edge.Right.ChannelId)"
            "$($edge.Right.ObservationId)|$($edge.Left.ChannelId)"
        )) {
            if ($edgeCounts.ContainsKey($key)) { $edgeCounts[$key]++ } else { $edgeCounts[$key] = 1 }
        }
    }
    $correlations = [System.Collections.Generic.List[object]]::new()
    $aliases = [System.Collections.Generic.List[object]]::new()
    $handled = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($edge in $edges) {
        $observationIds = @(@($edge.Left.ObservationId, $edge.Right.ObservationId) | Sort-Object)
        $edgeKey = $observationIds -join '|'
        if (-not $handled.Add($edgeKey)) { continue }
        $leftAlternatives = $edgeCounts["$($edge.Left.ObservationId)|$($edge.Right.ChannelId)"]
        $rightAlternatives = $edgeCounts["$($edge.Right.ObservationId)|$($edge.Left.ChannelId)"]
        $ambiguous = $leftAlternatives -gt 1 -or $rightAlternatives -gt 1
        $sources = @(@($edge.Left.SourceId, $edge.Right.SourceId) | Sort-Object -Unique)
        $provenance = @(
            [pscustomobject][ordered]@{ ObservationId = $edge.Left.ObservationId; SourceId = $edge.Left.SourceId; SourceRecordReference = $edge.Left.SourceRecordReference; ChannelId = $edge.Left.ChannelId; ChannelReference = $edge.Left.ChannelReference }
            [pscustomobject][ordered]@{ ObservationId = $edge.Right.ObservationId; SourceId = $edge.Right.SourceId; SourceRecordReference = $edge.Right.SourceRecordReference; ChannelId = $edge.Right.ChannelId; ChannelReference = $edge.Right.ChannelReference }
        )
        $timeEvidence = @(
            [ordered]@{
                ObservationId = $edge.Left.ObservationId
                DisplayStart = $edge.Left.DisplayStartValue
                DisplayStop = $edge.Left.DisplayStopValue
                CanonicalStartUtc = $edge.Left.StartUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
                CanonicalStopUtc = $edge.Left.StopUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
            }
            [ordered]@{
                ObservationId = $edge.Right.ObservationId
                DisplayStart = $edge.Right.DisplayStartValue
                DisplayStop = $edge.Right.DisplayStopValue
                CanonicalStartUtc = $edge.Right.StartUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
                CanonicalStopUtc = $edge.Right.StopUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
            }
        )

        $correlations.Add([pscustomobject][ordered]@{
            CorrelationId = Get-ChannelForgeDomainHash -Domain 'cross-channel-programme-correlation/v1' -InputObject ([ordered]@{ ObservationIds = $observationIds })
            ObservationIds = $observationIds
            SourceIds = $sources
            TitleSimilarityPercent = [int][Math]::Round($edge.TitleSimilarity * 100)
            ChannelIds = @(@($edge.Left.ChannelId, $edge.Right.ChannelId) | Sort-Object -Unique)
            Titles = @(@($edge.Left.Title, $edge.Right.Title) | Sort-Object -Unique)
            ConfidenceScore = $edge.ConfidenceScore
            ConfidenceState = if ($ambiguous -or -not $edge.FreshForLearning) { 'NeedsReview' } elseif ($edge.ConfidenceScore -ge 85) { 'High' } else { 'Corroborated' }
            CorrelationBasis = $edge.Basis
            Ambiguous = $ambiguous
            ReviewRequired = ($ambiguous -or -not $edge.FreshForLearning)
            CanMerge = $false
            Provenance = $provenance
            TimeEvidence = $timeEvidence
        }) | Out-Null
        if (-not $ambiguous -and $edge.FreshForLearning -and $edge.TitleSimilarity -lt 0.98 -and ($null -eq $edge.ContextualAlias -or $edge.ContextualAlias.ApprovalStatus -eq 'Proposed')) {
            $sides = @(Get-ContextualAliasSides -Left $edge.Left -Right $edge.Right)
            $contextKey = Get-ContextualAliasContextKey -Sides $sides
            if ($null -eq $edge.ContextualAlias -and $contextualAliasesByKey.ContainsKey($contextKey)) { continue }
            $aliasProjection = [ordered]@{
                Titles = @($sides | ForEach-Object Title | Sort-Object -Unique)
                ChannelIds = @($sides | ForEach-Object ChannelId | Sort-Object -Unique)
                CategoryKeys = @($sides | ForEach-Object CategoryKeys | Sort-Object -Unique)
                Participants = @($sides | ForEach-Object Participants | Sort-Object -Unique)
                EpisodeNumbers = @($sides | ForEach-Object EpisodeNumber | Where-Object { $_ } | Sort-Object -Unique)
                Competitions = @($sides | ForEach-Object Competition | Where-Object { $_ } | Sort-Object -Unique)
            }
            $observedTimes = @(@($edge.Left.ObservationTimeUtc, $edge.Right.ObservationTimeUtc) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object)
            $sourceDataTimes = @(@($edge.Left.SourceDataTimeUtc, $edge.Right.SourceDataTimeUtc) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object)
            $evidenceRecord = [pscustomobject][ordered]@{ ObservationIds = $observationIds; Sides = $sides; ConfidenceScore = $edge.ConfidenceScore; CorrelationBasis = $edge.Basis }
            $aliases.Add([pscustomobject][ordered]@{
                AliasId = $contextKey
                ContextKey = $contextKey
                Version = 2
                Status = 'Proposed'
                ApprovalStatus = 'Proposed'
                ApprovalState = 'Pending'
                ScopeKind = 'Contextual'
                EvidenceCount = $observationIds.Count
                FirstSeenAtUtc = if ($observedTimes.Count -gt 0) { $observedTimes[0] } else { $null }
                LastSeenAtUtc = if ($observedTimes.Count -gt 0) { $observedTimes[$observedTimes.Count - 1] } else { $null }
                FirstSourceDataTimeUtc = if ($sourceDataTimes.Count -gt 0) { $sourceDataTimes[0] } else { $null }
                LastSourceDataTimeUtc = if ($sourceDataTimes.Count -gt 0) { $sourceDataTimes[$sourceDataTimes.Count - 1] } else { $null }
                CanonicalTitle = $null
                Aliases = $aliasProjection.Titles
                Sides = $sides
                EvidenceRecords = @($evidenceRecord)
                Context = [ordered]@{
                    ChannelIds = $aliasProjection.ChannelIds
                    CategoryKeys = $aliasProjection.CategoryKeys
                    Participants = $aliasProjection.Participants
                    EpisodeNumbers = $aliasProjection.EpisodeNumbers
                    Competitions = $aliasProjection.Competitions
                    EventStartUtc = @($sides | Sort-Object StartUtc | Select-Object -First 1).StartUtc
                    EventStopUtc = @($sides | Sort-Object StopUtc -Descending | Select-Object -First 1).StopUtc
                }
                ConfidenceScore = $edge.ConfidenceScore
                CorrelationBasis = $edge.Basis
                EvidenceObservationIds = $observationIds
                Provenance = $provenance
                Reversible = $true
                History = @([ordered]@{ Version = 1; Action = 'Proposed'; PreviousStatus = $null; Status = 'Proposed'; EvidenceObservationIds = $observationIds })
                Accepted = $false
                CanMerge = $false
            }) | Out-Null
        }
    }

    return [pscustomobject][ordered]@{
        Correlations = @($correlations | Sort-Object CorrelationId)
        ContextualAliasProposals = @($aliases | Sort-Object AliasId)
        RejectedAliasMatches = @($rejectedAliases | Sort-Object EntryId, ContextKey, @{Expression={ $_.ObservationIds -join '|' }})
    }
}
