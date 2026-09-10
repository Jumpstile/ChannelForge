function Get-ChannelForgeGuideReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [GuideEvidenceRecord[]]$Evidence
    )

    $stateNames = @(
        'Confirmed'
        'SafeCandidate'
        'NeedsReview'
        'Unresolved'
        'Contradiction'
        'StaleSource'
        'SourceUnavailable'
    )
    $stateCounts = [ordered]@{}
    foreach ($stateName in $stateNames) { $stateCounts[$stateName] = 0 }

    $groups = [ordered]@{}
    $unresolvedOrdinal = 0
    foreach ($record in @($Evidence)) {
        if ($null -eq $record) { continue }
        $channel = [string]$record.ChannelReference
        $eventType = [string]$record.EventType
        $title = [string]$record.Title
        if ([string]::IsNullOrEmpty($channel) -and [string]::IsNullOrEmpty($title)) {
            $key = "unresolved:$unresolvedOrdinal"
            $unresolvedOrdinal++
        }
        else {
            $key = @($channel, $eventType, $title) -join [char]31
        }
        if (-not $groups.Contains($key)) {
            $groups[$key] = [System.Collections.Generic.List[GuideEvidenceRecord]]::new()
        }
        [void]$groups[$key].Add($record)
    }

    $readinessRecords = [System.Collections.Generic.List[GuideReadinessRecord]]::new()
    foreach ($key in @($groups.Keys | Sort-Object)) {
        $items = @($groups[$key].ToArray())
        $timings = @(
            $items |
                Where-Object { -not [string]::IsNullOrEmpty($_.StartUtc) -or -not [string]::IsNullOrEmpty($_.EndUtc) } |
                ForEach-Object { @([string]$_.StartUtc, [string]$_.EndUtc) -join '|' } |
                Sort-Object -Unique
        )
        $hasContradiction = $timings.Count -gt 1 -or @($items | Where-Object { $_.ConfidenceState -eq 'Contradiction' }).Count -gt 0
        $hasUnavailable = @($items | Where-Object { $_.ConfidenceState -eq 'SourceUnavailable' -or $_.FreshnessState -eq 'Unavailable' }).Count -gt 0
        $hasStale = @($items | Where-Object { $_.ConfidenceState -eq 'StaleSource' -or $_.FreshnessState -eq 'Stale' }).Count -gt 0
        $hasNeedsReview = @($items | Where-Object { $_.ConfidenceState -eq 'NeedsReview' }).Count -gt 0
        $hasSafeCandidate = @($items | Where-Object { $_.ConfidenceState -eq 'SafeCandidate' }).Count -gt 0
        $hasMissingIdentity = @($items | Where-Object { [string]::IsNullOrEmpty($_.ChannelReference) -or [string]::IsNullOrEmpty($_.Title) }).Count -gt 0
        $hasAcceptedKnowledge = @($items | Where-Object { $_.EvidenceType -eq 'AcceptedKnowledge' }).Count -gt 0
        $independentEvidence = @($items | Where-Object { $_.SourceRelationship -in @('Authoritative', 'Independent') }).Count
        $allMirrorEvidence = $items.Count -gt 1 -and $independentEvidence -eq 0
        $reasons = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $items) {
            foreach ($reason in @($item.ReasonCodes)) {
                if (-not $reasons.Contains([string]$reason)) { [void]$reasons.Add([string]$reason) }
            }
        }

        $state = 'Unresolved'
        if ($hasContradiction) {
            $state = 'Contradiction'
            if (-not $reasons.Contains('EvidenceContradicts')) { [void]$reasons.Add('EvidenceContradicts') }
        }
        elseif ($hasUnavailable) {
            $state = 'SourceUnavailable'
            if (-not $reasons.Contains('SourceUnavailable')) { [void]$reasons.Add('SourceUnavailable') }
        }
        elseif ($hasStale) {
            $state = 'StaleSource'
            if (-not $reasons.Contains('SourceStale')) { [void]$reasons.Add('SourceStale') }
        }
        elseif ($hasMissingIdentity) {
            $state = 'Unresolved'
            if (-not $reasons.Contains('EvidenceMissing')) { [void]$reasons.Add('EvidenceMissing') }
        }
        elseif ($hasNeedsReview -or $allMirrorEvidence) {
            $state = 'NeedsReview'
            if ($allMirrorEvidence -and -not $reasons.Contains('EvidenceMissing')) { [void]$reasons.Add('EvidenceMissing') }
        }
        elseif ($hasSafeCandidate) {
            $state = 'SafeCandidate'
        }
        elseif (@($items | Where-Object { $_.ConfidenceState -eq 'Confirmed' }).Count -eq $items.Count) {
            $state = 'Confirmed'
        }

        $channelReference = @($items | Where-Object { -not [string]::IsNullOrEmpty($_.ChannelReference) } | Select-Object -First 1).ChannelReference
        $eventType = @($items | Where-Object { $_.EventType -ne 'Unknown' } | Select-Object -First 1).EventType
        $title = @($items | Where-Object { -not [string]::IsNullOrEmpty($_.Title) } | Select-Object -First 1).Title
        if ([string]::IsNullOrEmpty([string]$title)) {
            $title = @($items | Where-Object { -not [string]::IsNullOrEmpty($_.DisplayName) } | Select-Object -First 1).DisplayName
        }

        $readiness = [GuideReadinessRecord]::new()
        $readiness.ChannelReference = if ($null -eq $channelReference) { '' } else { [string]$channelReference }
        $readiness.EventType = if ([string]::IsNullOrEmpty([string]$eventType)) { 'Unknown' } else { [string]$eventType }
        $readiness.Title = if ($null -eq $title) { '' } else { [string]$title }
        $readiness.ReadinessState = $state
        $readiness.RequiresReview = $state -ne 'Confirmed'
        $readiness.AcceptedStatePreserved = $hasAcceptedKnowledge
        $readiness.Evidence = @($items)
        $readiness.ReasonCodes = @($reasons | Sort-Object -Unique)
        [void]$readinessRecords.Add($readiness)
        $stateCounts[$state] = [int]$stateCounts[$state] + 1
    }

    $overallState = 'Unresolved'
    foreach ($priorityState in @('Contradiction', 'SourceUnavailable', 'StaleSource', 'Unresolved', 'NeedsReview', 'SafeCandidate', 'Confirmed')) {
        if ($stateCounts[$priorityState] -gt 0) {
            $overallState = $priorityState
            break
        }
    }

    $acceptedStatePreserved = @($Evidence | Where-Object { $_.EvidenceType -eq 'AcceptedKnowledge' }).Count -gt 0
    return [pscustomobject][ordered]@{
        ContractVersion = 'guide-intelligence/v1'
        InferenceStatus = 'EvidenceOnly'
        OverallState = $overallState
        Records = @($readinessRecords.ToArray())
        StateCounts = [pscustomobject]$stateCounts
        ActionableCount = @($readinessRecords | Where-Object { $_.RequiresReview }).Count
        ReadOnly = $true
        PublicationState = 'CandidateOnly'
        PromotionRequired = 'ExplicitAcceptance'
        CanPublish = $false
        AcceptedStatePreserved = $acceptedStatePreserved
        AcceptedStateMutation = 'None'
        RedactedFields = @(
            'Url'
            'StreamUrl'
            'Credential'
            'Token'
            'PrivatePath'
            'ParserError'
            'CandidateHash'
            'GenerationId'
        )
    }
}
