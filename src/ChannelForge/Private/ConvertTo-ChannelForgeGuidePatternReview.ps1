function ConvertTo-ChannelForgeGuidePatternReviewSafeText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    return ConvertTo-ChannelForgeGuidePatternSafeText -Value $Value
}

function Get-ChannelForgeGuidePatternReviewProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($Name)) {
        return $InputObject[$Name]
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-ChannelForgeGuidePatternReviewSafeTextArray {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Values
    )

    return @(
        $Values |
            Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ConvertTo-ChannelForgePatternReviewSafeText -Value $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
}

function ConvertTo-ChannelForgePatternReviewSafeText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    return ConvertTo-ChannelForgeGuidePatternReviewSafeText -Value $Value
}

function ConvertTo-ChannelForgeGuidePatternReviewInteger {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [int]$Default = 0
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    try { return [int]$Value } catch { return $Default }
}

function Get-ChannelForgeGuidePatternReviewFriendlyFieldName {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$FieldName)

    switch ($FieldName) {
        'RepresentativeExampleOrdinal' { return 'Representative example' }
        'CanonicalStartUtc' { return 'Canonical UTC start' }
        'EventTitle' { return 'Event title' }
        'EventDate' { return 'Event date' }
        'EventTime' { return 'Event time' }
        'EventTimezone' { return 'Event timezone' }
        'EventDayOfWeek' { return 'Event day of week' }
        'HomeParticipant' { return 'Home participant' }
        'AwayParticipant' { return 'Away participant' }
        'League' { return 'League' }
        'Sport' { return 'Sport' }
        'EventFamily' { return 'Event family' }
        'EventStatus' { return 'Event status' }
        default {
            if ([string]::IsNullOrWhiteSpace($FieldName)) { return 'Unspecified field' }
            return (ConvertTo-ChannelForgePatternReviewSafeText -Value $FieldName)
        }
    }
}

function Get-ChannelForgeGuidePatternReviewReasonMessage {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Code)

    switch ($Code) {
        'EvidenceContradicts' { return 'The supplied evidence resolves to different event times. ChannelForge will not choose one.' }
        'PatternDrift' { return 'The observed naming structure differs from the supplied rule or sample majority.' }
        'InconsistentExamples' { return 'The examples do not all fit one stable event-channel pattern.' }
        'MissingTime' { return 'A critical event time is missing from one or more examples.' }
        'MissingDate' { return 'A critical event date is missing from one or more examples.' }
        'TimezoneUnresolved' { return 'A timezone label has no explicit safe mapping.' }
        'ReferenceInstantRequired' { return 'A yearless date needs an injected reference instant.' }
        'InsufficientExamples' { return 'More representative examples are required before this pattern can be trusted.' }
        'EventFamilyConflict' { return 'Event-family evidence disagrees across the supplied inputs.' }
        'LeagueConflict' { return 'League evidence disagrees across the supplied inputs.' }
        'SportConflict' { return 'Sport evidence disagrees across the supplied inputs.' }
        'EvidenceMissing' { return 'A required identity or event field is missing.' }
        'AmbiguousTime' { return 'The date or time interpretation is ambiguous.' }
        'AmbiguousTitle' { return 'The event title is ambiguous.' }
        'NoEventData' { return 'The source did not provide event data for this candidate.' }
        'ScheduleChanged' { return 'The source reports a schedule change that requires review.' }
        'Postponed' { return 'The event is postponed; schedule-derived inference requires review.' }
        'Cancelled' { return 'The event is cancelled; schedule-derived inference requires review.' }
        'Rescheduled' { return 'The event is rescheduled; schedule-derived inference requires review.' }
        'InvalidDate' { return 'One or more date values are malformed or out of range.' }
        'InvalidTime' { return 'One or more time values are malformed or out of range.' }
        'TimezoneCrossCheckUnavailable' { return 'Duplicate timezone evidence could not be compared safely.' }
        'ConfidenceBelowThreshold' { return 'The candidate confidence is below the automatic confirmation threshold.' }
        'MirrorNotIndependent' { return 'Mirror sources are retained as provenance but do not count as independent agreement.' }
        'SourceNeedsReview' { return 'A source marked its evidence as requiring review.' }
        'SourceUnavailable' { return 'The source is unavailable; no candidate can be trusted automatically.' }
        'SourceStale' { return 'The source reports stale evidence; review is required before use.' }
        'StaleSource' { return 'The source is stale; review is required before use.' }
        'InvalidBaselineRule' { return 'The supplied baseline rule identifier is not a safe ChannelForge pattern identifier.' }
        default { return 'The supplied evidence needs review before this candidate can be used.' }
    }
}

function Get-ChannelForgeGuidePatternReviewStateMessage {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$State)

    switch ($State) {
        'Confirmed' { return 'The supplied examples fit one consistent event-channel pattern.' }
        'SafeCandidate' { return 'The examples suggest a useful pattern, but it remains provisional.' }
        'NeedsReview' { return 'The pattern is understandable, but one or more details need a person to review.' }
        'Contradiction' { return 'The evidence conflicts. ChannelForge preserves the conflict instead of guessing.' }
        'StaleSource' { return 'The source is stale. Existing accepted knowledge remains protected.' }
        'SourceUnavailable' { return 'The source is unavailable. No new event pattern is trusted automatically.' }
        default { return 'ChannelForge could not establish a complete event pattern from the supplied evidence.' }
    }
}

function Get-ChannelForgeGuidePatternReviewPatternDescription {
    [CmdletBinding()]
    param([AllowNull()][object]$Grammar)

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $Grammar -Name 'Segments'))) {
        if ($null -eq $segment) { continue }
        $kind = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $segment -Name 'Kind')
        $name = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $segment -Name 'Name')
        if ($kind -eq 'StableLiteral') {
            $value = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $segment -Name 'Value')
            if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$parts.Add("the stable label '$value'") }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($name)) {
            [void]$parts.Add("the $(Get-ChannelForgeGuidePatternReviewFriendlyFieldName -FieldName $name) field")
        }
    }

    if ($parts.Count -eq 0) {
        return 'ChannelForge could not describe a stable naming pattern from the supplied examples.'
    }

    $separator = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $Grammar -Name 'Separator')
    $description = 'Channel names follow ' + ($parts -join ', then ') + '.'
    if (-not [string]::IsNullOrWhiteSpace($separator)) {
        $description += " The event timing section is separated by '$separator'."
    }
    return $description
}

function ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    $text = ConvertTo-ChannelForgePatternReviewSafeText -Value $Value
    $text = $text -replace '\r?\n', ' '
    return $text.Replace('|', '\|')
}

function ConvertTo-ChannelForgeGuidePatternReviewMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)][GuidePatternReviewReport]$Report)

    $lines = [System.Collections.Generic.List[string]]::new()
    $summary = $Report.Summary
    $pattern = $Report.Pattern
    $eventData = $Report.Event
    $confidence = $Report.Confidence
    $review = $Report.Review
    $drift = $Report.Drift
    $provenance = $Report.Provenance
    $safety = $Report.Safety
    $next = $Report.NextAction

    [void]$lines.Add('# ChannelForge event-pattern review')
    [void]$lines.Add('')
    [void]$lines.Add(('**Status:** {0}' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $summary.State)))
    [void]$lines.Add(('**Summary:** {0}' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $summary.PlainLanguage)))
    [void]$lines.Add('')
    [void]$lines.Add('## What ChannelForge found')
    [void]$lines.Add('')
    [void]$lines.Add((ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $pattern.Description))
    [void]$lines.Add('')
    [void]$lines.Add('| Scope | Value |')
    [void]$lines.Add('| --- | --- |')
    foreach ($scopeName in @('EventFamily', 'League', 'Sport', 'Group', 'SourceFamily', 'InputField')) {
        $label = Get-ChannelForgeGuidePatternReviewFriendlyFieldName -FieldName $scopeName
        $value = Get-ChannelForgeGuidePatternReviewProperty -InputObject $pattern.Scope -Name $scopeName
        if ([string]::IsNullOrWhiteSpace([string]$value)) { $value = 'Not specified' }
        [void]$lines.Add(('| {0} | {1} |' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $label), (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $value)))
    }
    [void]$lines.Add('')
    [void]$lines.Add('## Event preview (representative example)')
    [void]$lines.Add('')
    [void]$lines.Add('| Field | Detected value |')
    [void]$lines.Add('| --- | --- |')
    foreach ($eventName in @('RepresentativeExampleOrdinal', 'ChannelIdentifier', 'ChannelOrdinal', 'EventTitle', 'EventDate', 'EventTime', 'EventTimezone', 'CanonicalStartUtc', 'League', 'Sport', 'EventFamily', 'HomeParticipant', 'AwayParticipant', 'EventStatus')) {
        $label = Get-ChannelForgeGuidePatternReviewFriendlyFieldName -FieldName $eventName
        $value = Get-ChannelForgeGuidePatternReviewProperty -InputObject $eventData -Name $eventName
        if ($eventName -eq 'EventTimezone') { $value = @($value) -join ', ' }
        if ([string]::IsNullOrWhiteSpace([string]$value)) { $value = 'Not detected' }
        [void]$lines.Add(('| {0} | {1} |' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $label), (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $value)))
    }
    [void]$lines.Add('')
    [void]$lines.Add('## Detected fields')
    [void]$lines.Add('')
    [void]$lines.Add('| Field | Found | Confidence | Details |')
    [void]$lines.Add('| --- | --- | --- | --- |')
    foreach ($field in @($Report.Fields)) {
        $found = if ($field.Found) { 'Yes' } else { 'No' }
        $details = if ([string]::IsNullOrWhiteSpace([string]$field.Details)) { 'No additional detail.' } else { $field.Details }
        [void]$lines.Add(('| {0} | {1} | {2} ({3}) | {4} |' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $field.DisplayName), $found, (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $field.ConfidenceState), $field.ConfidenceScore, (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $details)))
    }
    [void]$lines.Add('')
    [void]$lines.Add('## Confidence and review')
    [void]$lines.Add('')
    [void]$lines.Add(('Confidence: **{0}** ({1}/100).' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $confidence.State), $confidence.Score))
    [void]$lines.Add((ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $confidence.Explanation))
    if (@($review.Reasons).Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('Review reasons:')
        foreach ($reason in @($review.Reasons)) {
            [void]$lines.Add(('- **{0}:** {1}' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $reason.Code), (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $reason.Message)))
        }
    }
    [void]$lines.Add('')
    [void]$lines.Add('## Drift and provenance')
    [void]$lines.Add('')
    [void]$lines.Add(('Drift status: **{0}**.' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $drift.Status)))
    [void]$lines.Add((ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $drift.Explanation))
    [void]$lines.Add(('Sources: {0}; independent sources: {1}; mirror sources: {2}.' -f $provenance.SourceCount, $provenance.IndependentSourceCount, $provenance.MirrorSourceCount))
    [void]$lines.Add((ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $provenance.Explanation))
    if (@($provenance.Sources).Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('| Source | Family | Relationship | Freshness |')
        [void]$lines.Add('| --- | --- | --- | --- |')
        foreach ($source in @($provenance.Sources)) {
            [void]$lines.Add(('| {0} | {1} | {2} | {3} |' -f `
                    (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $source.SourceId), `
                    (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $source.SourceFamily), `
                    (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $source.Relationship), `
                    (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $source.FreshnessState)))
        }
    }
    [void]$lines.Add('')
    [void]$lines.Add('## Safety boundary')
    [void]$lines.Add('')
    [void]$lines.Add(('- Publication state: `{0}`' -f $safety.PublicationState))
    [void]$lines.Add(('- Can publish: `{0}`' -f $safety.CanPublish.ToString().ToLowerInvariant()))
    [void]$lines.Add(('- Promotion required: `{0}`' -f $safety.PromotionRequired))
    [void]$lines.Add(('- Accepted-state mutation: `{0}`' -f $safety.AcceptedStateMutation))
    [void]$lines.Add(('- Accepted state preserved: `{0}`' -f $safety.AcceptedStatePreserved.ToString().ToLowerInvariant()))
    [void]$lines.Add(('- Read-only: `{0}`' -f $safety.ReadOnly.ToString().ToLowerInvariant()))
    [void]$lines.Add(('- Provider mutation: `{0}`' -f $safety.ProviderMutation.ToString().ToLowerInvariant()))
    [void]$lines.Add(('- Downstream mutation: `{0}`' -f $safety.DownstreamMutation.ToString().ToLowerInvariant()))
    [void]$lines.Add(('- Filesystem mutation: `{0}`' -f $safety.FilesystemMutation.ToString().ToLowerInvariant()))
    [void]$lines.Add(('- Redaction: `applied` to untrusted source values'))
    [void]$lines.Add('')
    [void]$lines.Add('## Next safe action')
    [void]$lines.Add('')
    [void]$lines.Add(('**{0}**' -f (ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $next.Status)))
    [void]$lines.Add((ConvertTo-ChannelForgeGuidePatternReviewMarkdownCell -Value $next.Action))
    [void]$lines.Add('')
    [void]$lines.Add('_This report is review evidence only. It does not publish a guide, change provider or downstream state, write files, or alter accepted state._')

    return ($lines -join "`n")
}

function ConvertTo-ChannelForgeGuidePatternReviewReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InferenceResult)

    $candidate = Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'SelectedCandidate'
    if ($null -eq $candidate) {
        $candidate = @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'Candidates')) | Where-Object { $null -ne $_ } | Select-Object -First 1
    }
    $grammar = Get-ChannelForgeGuidePatternReviewProperty -InputObject $candidate -Name 'Grammar'
    $scope = Get-ChannelForgeGuidePatternReviewProperty -InputObject $candidate -Name 'Scope'
    $preview = @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'ExtractionPreview')) | Where-Object { $null -ne $_ } | Sort-Object ExampleOrdinal, Fingerprint | Select-Object -First 1

    $knownStates = @('Confirmed', 'SafeCandidate', 'NeedsReview', 'Unresolved', 'Contradiction', 'StaleSource', 'SourceUnavailable')
    $rawState = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'OverallState')
    if ($rawState -notin $knownStates) { $rawState = 'Unresolved' }
    $confidenceState = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'ConfidenceState')
    if ($confidenceState -notin $knownStates) { $confidenceState = $rawState }
    $confidenceScore = ConvertTo-ChannelForgeGuidePatternReviewInteger -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'ConfidenceScore')
    $confidenceScore = [Math]::Max(0, [Math]::Min(100, $confidenceScore))
    $driftStatus = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'DriftStatus')
    if ($driftStatus -notin @('Detected', 'NotEvaluated')) { $driftStatus = 'NotEvaluated' }

    $reviewRows = [System.Collections.Generic.List[object]]::new()
    $reviewKeys = @{}
    foreach ($item in @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'ReviewItems'))) {
        if ($null -eq $item) { continue }
        $code = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $item -Name 'Code')
        if ([string]::IsNullOrWhiteSpace($code)) { continue }
        $message = Get-ChannelForgeGuidePatternReviewReasonMessage -Code $code
        $key = "$code`u{1F}" + $message
        if (-not $reviewKeys.ContainsKey($key)) {
            $reviewKeys[$key] = $true
            [void]$reviewRows.Add([ordered]@{ Code = $code; Message = $message })
        }
    }
    if ($rawState -eq 'Contradiction' -and @($reviewRows).Count -eq 0) {
        [void]$reviewRows.Add([ordered]@{ Code = 'EvidenceContradicts'; Message = Get-ChannelForgeGuidePatternReviewReasonMessage -Code 'EvidenceContradicts' })
    }
    if (@($reviewRows).Count -eq 0) {
        foreach ($reason in (ConvertTo-ChannelForgeGuidePatternReviewSafeTextArray -Values @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'ReasonCodes')))) {
            if ($reason -in @('EvidenceAgrees', 'AcceptedKnowledge', 'MetadataOnly')) { continue }
            $key = "$reason`u{1F}" + (Get-ChannelForgeGuidePatternReviewReasonMessage -Code $reason)
            if (-not $reviewKeys.ContainsKey($key)) {
                $reviewKeys[$key] = $true
                [void]$reviewRows.Add([ordered]@{ Code = $reason; Message = Get-ChannelForgeGuidePatternReviewReasonMessage -Code $reason })
            }
        }
    }
    $reviewRows = [System.Collections.Generic.List[object]]::new(@($reviewRows | Sort-Object Code, Message))

    $fieldRows = [System.Collections.Generic.List[object]]::new()
    foreach ($field in @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $candidate -Name 'FieldCandidates')) | Where-Object { $null -ne $_ } | Sort-Object FieldName) {
        $fieldName = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'FieldName')
        $displayName = Get-ChannelForgeGuidePatternReviewFriendlyFieldName -FieldName $fieldName
        $observedCount = [Math]::Max(0, (ConvertTo-ChannelForgeGuidePatternReviewInteger -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'ObservedCount')))
        $exampleCount = [Math]::Max(0, (ConvertTo-ChannelForgeGuidePatternReviewInteger -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'ExampleCount')))
        $fieldScore = [Math]::Max(0, [Math]::Min(100, (ConvertTo-ChannelForgeGuidePatternReviewInteger -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'ConfidenceScore'))))
        $fieldState = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'ConfidenceState')
        if ($fieldState -notin $knownStates) { $fieldState = if ($observedCount -gt 0) { 'SafeCandidate' } else { 'Unresolved' } }
        $format = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'Format')
        $timezoneLabel = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'TimezoneLabel')
        $details = if ($observedCount -gt 0) { "Found in $observedCount of $exampleCount example(s)." } else { 'Not detected consistently in the supplied examples.' }
        if (-not [string]::IsNullOrWhiteSpace($format)) { $details += " Observed format: $format." }
        if (-not [string]::IsNullOrWhiteSpace($timezoneLabel)) { $details += " Timezone label: $timezoneLabel." }
        [void]$fieldRows.Add([ordered]@{
                FieldName = $fieldName
                DisplayName = $displayName
                Found = $observedCount -gt 0
                Required = [bool](Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'Required')
                ObservedCount = $observedCount
                ExampleCount = $exampleCount
                ConfidenceState = $fieldState
                ConfidenceScore = $fieldScore
                Format = $format
                TimezoneLabel = $timezoneLabel
                Details = ConvertTo-ChannelForgePatternReviewSafeText -Value $details
                ReasonCodes = ConvertTo-ChannelForgeGuidePatternReviewSafeTextArray -Values @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $field -Name 'ReasonCodes'))
            })
    }

    $timezoneLabels = ConvertTo-ChannelForgeGuidePatternReviewSafeTextArray -Values @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'TimezoneLabels'))
    $eventData = [ordered]@{
        RepresentativeExampleOrdinal = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'ExampleOrdinal')
        ChannelIdentifier = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'ChannelIdentifier')
        ChannelOrdinal = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'ChannelOrdinalText')
        EventTitle = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'EventTitle')
        EventDate = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'EventDate')
        EventTime = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'EventTime')
        EventTimezone = $timezoneLabels
        CanonicalStartUtc = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'StartUtc')
        League = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'League')
        Sport = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'Sport')
        EventFamily = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'EventFamily')
        HomeParticipant = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'HomeParticipant')
        AwayParticipant = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'AwayParticipant')
        EventStatus = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $preview -Name 'EventStatus')
    }

    $sourceRows = [System.Collections.Generic.List[object]]::new()
    $sourceKeys = @{}
    $provenance = @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'Provenance'))
    if ($provenance.Count -eq 0) { $provenance = @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'Examples')) }
    foreach ($source in $provenance | Where-Object { $null -ne $_ }) {
        $sourceId = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $source -Name 'SourceId')
        $sourceFamily = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $source -Name 'SourceFamily')
        $relationship = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $source -Name 'SourceRelationship')
        $freshness = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $source -Name 'FreshnessState')
        $key = "$sourceId`u{1F}$sourceFamily`u{1F}$relationship"
        if (-not $sourceKeys.ContainsKey($key)) {
            $sourceKeys[$key] = $true
            [void]$sourceRows.Add([ordered]@{ SourceId = $sourceId; SourceFamily = $sourceFamily; Relationship = $relationship; FreshnessState = $freshness })
        }
    }
    $sourceRows = [System.Collections.Generic.List[object]]::new(@($sourceRows | Sort-Object SourceId, SourceFamily, Relationship))
    $crossSource = Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'CrossSourceAssessment'
    $independentSourceIds = ConvertTo-ChannelForgeGuidePatternReviewSafeTextArray -Values @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $crossSource -Name 'IndependentSourceIds'))
    $mirrorSourceIds = ConvertTo-ChannelForgeGuidePatternReviewSafeTextArray -Values @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $crossSource -Name 'MirrorSourceIds'))
    $assessmentState = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $crossSource -Name 'State')
    if ([string]::IsNullOrWhiteSpace($assessmentState)) { $assessmentState = 'NotAvailable' }

    $acceptedStatePreserved = $false
    $acceptedValue = Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'AcceptedStatePreserved'
    if ($null -ne $acceptedValue) { $acceptedStatePreserved = [bool]$acceptedValue }
    $reviewRequired = $rawState -ne 'Confirmed' -or @($reviewRows).Count -gt 0 -or $driftStatus -eq 'Detected'
    $stateMessage = Get-ChannelForgeGuidePatternReviewStateMessage -State $rawState
    $reviewLanguage = if (@($reviewRows).Count -gt 0) { [string]$reviewRows[0].Message } else { $stateMessage }
    $nextAction = if ($rawState -in @('Contradiction', 'StaleSource', 'SourceUnavailable')) {
        [ordered]@{
            Status = 'Blocked'
            Blocked = $true
            Action = if ($rawState -eq 'Contradiction') { 'Resolve the conflicting evidence before considering this candidate.' } else { 'Obtain fresh, available evidence before considering this candidate.' }
            Reason = $stateMessage
        }
    }
    elseif ($reviewRequired) {
        [ordered]@{
            Status = 'Review required'
            Blocked = $true
            Action = 'Review the listed reasons and examples before using the existing explicit acceptance boundary.'
            Reason = $reviewLanguage
        }
    }
    else {
        [ordered]@{
            Status = 'Candidate only'
            Blocked = $true
            Action = 'Review the candidate, then use the existing explicit acceptance boundary if it is correct.'
            Reason = 'This report never accepts or publishes a pattern.'
        }
    }

    $report = [GuidePatternReviewReport]::new()
    $report.Summary = [ordered]@{
        State = $rawState
        PlainLanguage = $stateMessage
        ReviewRequired = $reviewRequired
        Headline = if ($reviewRequired) { 'Event pattern needs review before use.' } else { 'Event pattern is internally consistent but remains a candidate.' }
    }
    $report.Pattern = [ordered]@{
        Description = Get-ChannelForgeGuidePatternReviewPatternDescription -Grammar $grammar
        Scope = [ordered]@{
            EventFamily = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $scope -Name 'EventFamily')
            League = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $scope -Name 'League')
            Sport = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $scope -Name 'Sport')
            Group = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $scope -Name 'Group')
            SourceFamily = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $scope -Name 'SourceFamily')
            InputField = ConvertTo-ChannelForgePatternReviewSafeText -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $scope -Name 'InputField')
        }
    }
    $report.Fields = @($fieldRows.ToArray())
    $report.Event = $eventData
    $report.Confidence = [ordered]@{
        State = $confidenceState
        Score = $confidenceScore
        Explanation = Get-ChannelForgeGuidePatternReviewStateMessage -State $confidenceState
    }
    $report.Review = [ordered]@{
        Required = $reviewRequired
        Reasons = @($reviewRows.ToArray())
        PlainLanguage = ConvertTo-ChannelForgePatternReviewSafeText -Value $reviewLanguage
    }
    $report.Drift = [ordered]@{
        Status = $driftStatus
        ReviewOnly = $true
        Adoption = 'NotApplied'
        Explanation = if ($driftStatus -eq 'Detected') { 'The naming pattern changed or differs from the baseline. Adoption was not applied.' } else { 'No baseline drift was detected by this review.' }
    }
    $report.Provenance = [ordered]@{
        SourceCount = @($sourceRows).Count
        Sources = @($sourceRows.ToArray())
        IndependentSourceCount = @($independentSourceIds).Count
        IndependentSourceIds = $independentSourceIds
        MirrorSourceCount = @($mirrorSourceIds).Count
        MirrorSourceIds = $mirrorSourceIds
        Assessment = $assessmentState
        Explanation = if (@($mirrorSourceIds).Count -gt 0) { 'Mirror sources remain visible as provenance and are not counted as independent confirmation.' } else { 'Source relationships and freshness remain visible without exposing raw source data.' }
    }
    $report.Safety = [ordered]@{
        PublicationState = 'CandidateOnly'
        CanPublish = $false
        PromotionRequired = 'ExplicitAcceptance'
        AcceptedStateMutation = 'None'
        AcceptedStatePreserved = $acceptedStatePreserved
        ReadOnly = $true
        ProviderMutation = $false
        DownstreamMutation = $false
        FilesystemMutation = $false
    }
    $report.NextAction = $nextAction
    $report.ExampleCount = [Math]::Max(0, (ConvertTo-ChannelForgeGuidePatternReviewInteger -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'ExampleCount')))
    $report.MatchedExampleCount = [Math]::Max(0, (ConvertTo-ChannelForgeGuidePatternReviewInteger -Value (Get-ChannelForgeGuidePatternReviewProperty -InputObject $InferenceResult -Name 'MatchedExampleCount')))
    return $report
}
