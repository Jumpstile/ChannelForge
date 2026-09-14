function Get-ChannelForgeGuideVolatileProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string[]]$Names
    )

    if ($null -eq $InputObject) { return $null }
    foreach ($name in $Names) {
        if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($name)) {
            return $InputObject[$name]
        }
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property) { return $property.Value }
    }
    return $null
}

function ConvertTo-ChannelForgeGuideVolatileSafeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return ConvertTo-ChannelForgeGuidePatternSafeText -Value ([string]$Value)
}

function ConvertTo-ChannelForgeGuideVolatileUtc {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse(
            [string]$Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$parsed)) {
        return ''
    }
    return $parsed.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-ChannelForgeGuideVolatileFactRecord {
    param([AllowNull()][object]$InputObject)

    $factType = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('FactType', 'Kind', 'Type'))
    $subjectType = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('SubjectType'))
    $subjectId = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('SubjectId', 'Subject', 'PlayerId', 'TeamId'))
    $sourceId = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('SourceId'))
    $sourceType = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('SourceType', 'EvidenceType'))
    $sourceRelationship = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('SourceRelationship', 'Relationship'))
    if ($sourceRelationship -notin @('Authoritative', 'Independent', 'Mirror', 'Unknown')) { $sourceRelationship = 'Unknown' }

    $freshness = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('FreshnessState', 'Freshness'))
    if ($freshness -notin @('Current', 'Stale', 'Unavailable', 'Unknown')) { $freshness = 'Unknown' }
    $confidence = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('ConfidenceState', 'Confidence'))
    if ($confidence -notin @('Confirmed', 'SafeCandidate', 'NeedsReview', 'Contradiction', 'StaleSource', 'SourceUnavailable', 'Unknown')) { $confidence = 'Unknown' }
    $status = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('Status', 'FactStatus'))
    if ($status -notin @('Current', 'Stale', 'Unavailable', 'Contradictory', 'Unknown')) { $status = 'Unknown' }
    $value = Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('Value', 'FactValue', 'Summary')
    $valueText = ConvertTo-ChannelForgeGuideVolatileSafeText -Value $value
    $providedFingerprint = [string](Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('ValueFingerprint', 'FactFingerprint'))
    $valueFingerprint = if ($providedFingerprint -match '^[0-9a-fA-F]{64}$') { $providedFingerprint.ToLowerInvariant() } else { '' }
    if ($valueFingerprint -notmatch '^[0-9a-f]{64}$') {
        $valueFingerprint = if ([string]::IsNullOrWhiteSpace($valueText)) { '' } else { Get-ChannelForgeGuidePatternHash -Text $valueText }
    }

    $ttl = 0
    $ttlValue = Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('FreshnessTtlMinutes', 'TtlMinutes', 'TTLMinutes')
    if ($null -ne $ttlValue) { [void][int]::TryParse([string]$ttlValue, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$ttl) }

    return [ordered]@{
        FactId = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('FactId', 'Id'))
        FactType = $factType
        SubjectType = $subjectType
        SubjectId = $subjectId
        SourceId = $sourceId
        SourceType = $sourceType
        SourceRelationship = $sourceRelationship
        FetchedAtUtc = ConvertTo-ChannelForgeGuideVolatileUtc -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('FetchedAtUtc', 'FetchedUtc'))
        DataTimestampUtc = ConvertTo-ChannelForgeGuideVolatileUtc -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('DataTimestampUtc', 'SourceDataTimestampUtc', 'SourceDeclaredTimestampUtc'))
        EvaluationInstantUtc = ConvertTo-ChannelForgeGuideVolatileUtc -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('EvaluationInstantUtc', 'AsOfUtc'))
        EventStartUtc = ConvertTo-ChannelForgeGuideVolatileUtc -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('EventStartUtc', 'EventDateTimeUtc'))
        EventTimezone = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('EventTimezone', 'Timezone'))
        ValidFromUtc = ConvertTo-ChannelForgeGuideVolatileUtc -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('ValidFromUtc', 'RosterValidFromUtc', 'ValidityStartUtc'))
        ValidToUtc = ConvertTo-ChannelForgeGuideVolatileUtc -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('ValidToUtc', 'RosterValidToUtc', 'ValidityEndUtc'))
        League = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('League'))
        Sport = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('Sport'))
        Season = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('Season', 'SeasonId'))
        SeasonPhase = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('SeasonPhase', 'CompetitionPhase'))
        EventSeasonPhase = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('EventSeasonPhase', 'ExpectedSeasonPhase'))
        Week = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('Week', 'WeekNumber'))
        Round = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('Round', 'RoundName'))
        Competition = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('Competition', 'CompetitionId'))
        FreshnessState = $freshness
        FreshnessTtlMinutes = $ttl
        ConfidenceState = $confidence
        Status = $status
        ContradictionGroup = ConvertTo-ChannelForgeGuideVolatileSafeText -Value (Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('ContradictionGroup', 'ConflictGroup'))
        ExplicitContradiction = [bool](Get-ChannelForgeGuideVolatileProperty -InputObject $InputObject -Names @('Contradictory', 'Contradiction'))
        ValueFingerprint = $valueFingerprint
    }
}

function Resolve-ChannelForgeGuideVolatileFacts {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Facts = @(),
        [AllowEmptyString()][string]$EventStartUtc = '',
        [AllowEmptyString()][string]$EventTimezone = '',
        [AllowEmptyString()][string]$League = '',
        [AllowEmptyString()][string]$Sport = '',
        [AllowEmptyString()][string]$ExpectedSeason = '',
        [AllowEmptyString()][string]$ExpectedSeasonPhase = '',
        [AllowEmptyString()][string]$EvaluationInstantUtc = ''
    )
    $records = @($Facts | Where-Object { $null -ne $_ -and (-not ($_ -is [System.Collections.IDictionary]) -or $_.Count -gt 0) } | ForEach-Object { ConvertTo-ChannelForgeGuideVolatileFactRecord -InputObject $_ })
    if ($records.Count -eq 0) {
        return [ordered]@{
            Status = 'NotProvided'
            Explanation = 'No volatile facts were supplied. Stable title, time, and event-pattern identity remain separate from volatile enrichment.'
            Total = 0
            EligibleCount = 0
            OmittedCount = 0
            Facts = @()
            Omitted = @()
        }
    }

    $effectiveEvaluation = ConvertTo-ChannelForgeGuideVolatileUtc -Value $EvaluationInstantUtc
    if ([string]::IsNullOrWhiteSpace($effectiveEvaluation)) {
        $effectiveEvaluation = ConvertTo-ChannelForgeGuideVolatileUtc -Value $EventStartUtc
    }
    $expectedSeason = ConvertTo-ChannelForgeGuideVolatileSafeText -Value $ExpectedSeason
    $expectedPhase = ConvertTo-ChannelForgeGuideVolatileSafeText -Value $ExpectedSeasonPhase
    $expectedLeague = ConvertTo-ChannelForgeGuideVolatileSafeText -Value $League
    $expectedSport = ConvertTo-ChannelForgeGuideVolatileSafeText -Value $Sport

    $groups = @{}
    foreach ($record in $records) {
        if (-not [string]::IsNullOrWhiteSpace($record.ContradictionGroup)) {
            if (-not $groups.ContainsKey($record.ContradictionGroup)) { $groups[$record.ContradictionGroup] = [System.Collections.Generic.List[object]]::new() }
            [void]$groups[$record.ContradictionGroup].Add($record)
        }
    }
    $contradictoryGroups = @{}
    foreach ($key in $groups.Keys) {
        $fingerprints = @($groups[$key] | ForEach-Object { $_.ValueFingerprint } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        if ($fingerprints.Count -gt 1) { $contradictoryGroups[$key] = $true }
    }

    $assessed = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $records) {
        $reasons = [System.Collections.Generic.List[string]]::new()
        $decision = 'EligibleCurrent'

        if ($record.ExplicitContradiction -or $record.Status -eq 'Contradictory' -or $record.ConfidenceState -eq 'Contradiction' -or (-not [string]::IsNullOrWhiteSpace($record.ContradictionGroup) -and $contradictoryGroups.ContainsKey($record.ContradictionGroup))) {
            [void]$reasons.Add('ContradictoryVolatileFact')
            $decision = 'ReviewRequired'
        }
        elseif ($record.Status -eq 'Unavailable' -or $record.FreshnessState -eq 'Unavailable' -or $record.ConfidenceState -eq 'SourceUnavailable') {
            [void]$reasons.Add('VolatileSourceUnavailable')
            $decision = 'Omitted'
        }
        else {
            if ([string]::IsNullOrWhiteSpace($record.FactType) -or [string]::IsNullOrWhiteSpace($record.SubjectType) -or [string]::IsNullOrWhiteSpace($record.SubjectId)) { [void]$reasons.Add('MissingVolatileIdentity') }
            if ([string]::IsNullOrWhiteSpace($record.SourceId) -or [string]::IsNullOrWhiteSpace($record.SourceType) -or [string]::IsNullOrWhiteSpace($record.SourceRelationship) -or $record.SourceRelationship -eq 'Unknown' -or [string]::IsNullOrWhiteSpace($record.FetchedAtUtc) -or [string]::IsNullOrWhiteSpace($record.DataTimestampUtc) -or $record.FreshnessTtlMinutes -le 0) { [void]$reasons.Add('MissingVolatileProvenance') }
            if ([string]::IsNullOrWhiteSpace($effectiveEvaluation) -and [string]::IsNullOrWhiteSpace($record.EvaluationInstantUtc)) { [void]$reasons.Add('MissingEvaluationInstant') }
            if ([string]::IsNullOrWhiteSpace($EventStartUtc) -or [string]::IsNullOrWhiteSpace($EventTimezone)) { [void]$reasons.Add('MissingEventContext') }
            if ([string]::IsNullOrWhiteSpace($record.ValueFingerprint)) { [void]$reasons.Add('MissingVolatileValue') }
            if ([string]::IsNullOrWhiteSpace($record.Season) -or [string]::IsNullOrWhiteSpace($record.SeasonPhase)) { [void]$reasons.Add('MissingSeasonContext') }
            if (-not [string]::IsNullOrWhiteSpace($expectedLeague) -and $record.League -ne $expectedLeague) { [void]$reasons.Add('LeagueContextMismatch') }
            if (-not [string]::IsNullOrWhiteSpace($expectedSport) -and $record.Sport -ne $expectedSport) { [void]$reasons.Add('SportContextMismatch') }
            if (-not [string]::IsNullOrWhiteSpace($expectedSeason) -and $record.Season -ne $expectedSeason) { [void]$reasons.Add('SeasonContextMismatch') }
            if (-not [string]::IsNullOrWhiteSpace($expectedPhase) -and $record.SeasonPhase -ne $expectedPhase) { [void]$reasons.Add('SeasonPhaseMismatch') }
            if (-not [string]::IsNullOrWhiteSpace($record.EventSeasonPhase) -and $record.SeasonPhase -ne $record.EventSeasonPhase) { [void]$reasons.Add('SeasonPhaseMismatch') }
            if ($record.SourceRelationship -eq 'Mirror') { [void]$reasons.Add('MirrorSourceNeedsIndependentConfirmation') }

            $comparisonInstant = if (-not [string]::IsNullOrWhiteSpace($record.EvaluationInstantUtc)) { $record.EvaluationInstantUtc } else { $effectiveEvaluation }
            if (-not [string]::IsNullOrWhiteSpace($record.DataTimestampUtc) -and -not [string]::IsNullOrWhiteSpace($comparisonInstant) -and $record.FreshnessTtlMinutes -gt 0) {
                $dataTime = [datetimeoffset]::Parse($record.DataTimestampUtc)
                $evaluationTime = [datetimeoffset]::Parse($comparisonInstant)
                $ageMinutes = ($evaluationTime - $dataTime).TotalMinutes
                if ($ageMinutes -lt 0 -or $ageMinutes -ge $record.FreshnessTtlMinutes) { [void]$reasons.Add('VolatileFactStale') }
            }
            if ($record.FreshnessState -eq 'Stale' -or $record.Status -eq 'Stale' -or $record.ConfidenceState -eq 'StaleSource') { [void]$reasons.Add('VolatileFactStale') }
            if ($reasons.Count -gt 0) { $decision = if ($reasons -contains 'VolatileFactStale') { 'Omitted' } else { 'ReviewRequired' } }
        }

        $safeAssessment = [ordered]@{
            FactId = $record.FactId
            FactType = $record.FactType
            SubjectType = $record.SubjectType
            SubjectId = $record.SubjectId
            SourceId = $record.SourceId
            SourceType = $record.SourceType
            SourceRelationship = $record.SourceRelationship
            FetchedAtUtc = $record.FetchedAtUtc
            DataTimestampUtc = $record.DataTimestampUtc
            EvaluationInstantUtc = if (-not [string]::IsNullOrWhiteSpace($record.EvaluationInstantUtc)) { $record.EvaluationInstantUtc } else { $effectiveEvaluation }
            EventStartUtc = if (-not [string]::IsNullOrWhiteSpace($record.EventStartUtc)) { $record.EventStartUtc } else { $EventStartUtc }
            EventTimezone = if (-not [string]::IsNullOrWhiteSpace($record.EventTimezone)) { $record.EventTimezone } else { $EventTimezone }
            ValidFromUtc = $record.ValidFromUtc
            ValidToUtc = $record.ValidToUtc
            Season = $record.Season
            SeasonPhase = $record.SeasonPhase
            EventSeasonPhase = $record.EventSeasonPhase
            Week = $record.Week
            Round = $record.Round
            Competition = $record.Competition
            League = $record.League
            Sport = $record.Sport
            FreshnessState = $record.FreshnessState
            FreshnessTtlMinutes = $record.FreshnessTtlMinutes
            ConfidenceState = $record.ConfidenceState
            Status = $record.Status
            ContradictionGroup = $record.ContradictionGroup
            Decision = $decision
            ReasonCodes = [string[]]@($reasons | Sort-Object -Unique)
        }
        [void]$assessed.Add($safeAssessment)
    }

    $eligibleCount = @($assessed | Where-Object { $_.Decision -eq 'EligibleCurrent' }).Count
    $omittedCount = $assessed.Count - $eligibleCount
    $status = if ($eligibleCount -eq $assessed.Count) { 'Eligible' }
    elseif (@($assessed | Where-Object { $_.Decision -eq 'ReviewRequired' -and $_.ReasonCodes -contains 'ContradictoryVolatileFact' }).Count -gt 0) { 'Contradictory' }
    elseif (@($assessed | Where-Object { $_.ReasonCodes -contains 'VolatileSourceUnavailable' }).Count -gt 0) { 'SourceUnavailable' }
    elseif (@($assessed | Where-Object { $_.ReasonCodes -contains 'VolatileFactStale' }).Count -gt 0) { 'StaleOrReviewNeeded' }
    else { 'ReviewNeeded' }
    $explanation = switch ($status) {
        'Eligible' { 'Volatile facts have freshness, season context, provenance, and non-contradiction evidence.' }
        'Contradictory' { 'Contradictory volatile facts were preserved for review; no conflicting fact is planned as current.' }
        'SourceUnavailable' { 'Volatile source evidence is unavailable; volatile facts are omitted while stable event identity remains available.' }
        'StaleOrReviewNeeded' { 'Volatile facts are stale or lack sufficient freshness proof; they are omitted or marked for review while stable event identity remains available.' }
        default { 'Volatile facts lack sufficient freshness, season context, provenance, or review resolution; they are not planned as current.' }
    }

    return [ordered]@{
        Status = $status
        Explanation = $explanation
        Total = $assessed.Count
        EligibleCount = $eligibleCount
        OmittedCount = $omittedCount
        Facts = @($assessed | Sort-Object FactId, FactType, SubjectId, SourceId)
        Omitted = @($assessed | Where-Object { $_.Decision -ne 'EligibleCurrent' } | Sort-Object FactId, FactType, SubjectId, SourceId)
    }
}
