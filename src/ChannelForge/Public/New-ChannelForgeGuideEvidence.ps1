function New-ChannelForgeGuideEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'ProviderDisplayText',
            'ProviderM3UMetadata',
            'XMLTV',
            'AEDDerivedXMLTV',
            'AEDDerivedM3U',
            'ScheduleSource',
            'AcceptedKnowledge'
        )]
        [string]$EvidenceType,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [string]$SourceFamily = '',

        [ValidateSet('Authoritative', 'Independent', 'Mirror', 'Unknown')]
        [string]$SourceRelationship = 'Unknown',

        [string]$ChannelReference = '',
        [string]$DisplayName = '',
        [string]$Group = '',
        [string]$Title = '',

        [ValidateSet('Fight', 'PPV', 'TemporaryEvent', 'League', 'SingleTeam', 'StreamingEvent', 'Sports', 'Other', 'Unknown')]
        [string]$EventType = 'Unknown',

        [string]$League = '',
        [string]$Sport = '',
        [string]$HomeParticipant = '',
        [string]$AwayParticipant = '',
        [string]$StartUtc = '',
        [string]$EndUtc = '',
        [string]$SourceTimezone = '',

        [ValidateSet('Scheduled', 'Live', 'Postponed', 'Cancelled', 'Rescheduled', 'Delayed', 'Completed', 'Idle', 'Unknown')]
        [string]$EventStatus = 'Unknown',

        [ValidateSet('Confirmed', 'SafeCandidate', 'NeedsReview', 'Unresolved', 'Contradiction', 'StaleSource', 'SourceUnavailable')]
        [string]$ConfidenceState = 'Unresolved',

        [ValidateRange(0, 100)]
        [int]$ConfidenceScore = 0,

        [ValidateSet('Current', 'Stale', 'Unavailable', 'Unknown')]
        [string]$FreshnessState = 'Unknown',

        [AllowEmptyCollection()]
        [string[]]$ReasonCodes = @(),

        [AllowNull()]
        [object]$Metadata = $null
    )

    $allowedReasonCodes = @(
        'AcceptedKnowledge'
        'AmbiguousTime'
        'AmbiguousTitle'
        'ConfidenceBelowThreshold'
        'EvidenceAgrees'
        'EvidenceContradicts'
        'EvidenceMissing'
        'InvalidGuideId'
        'MetadataOnly'
        'NoEventData'
        'Postponed'
        'Cancelled'
        'Rescheduled'
        'ScheduleChanged'
        'SourceStale'
        'SourceUnavailable'
    )

    function Get-MetadataValue {
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

    function Get-TextValue {
        param(
            [string]$Explicit,
            [AllowNull()][object]$InputObject,
            [Parameter(Mandatory)][string[]]$Names
        )
        if (-not [string]::IsNullOrWhiteSpace($Explicit)) { return $Explicit }
        $metadataValue = Get-MetadataValue -InputObject $InputObject -Names $Names
        if ($null -eq $metadataValue) { return '' }
        return [string]$metadataValue
    }

    function ConvertTo-GuideIdentifier {
        param(
            [AllowEmptyString()][string]$Value,
            [Parameter(Mandatory)][string]$Name
        )
        if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
        $trimmed = $Value.Trim()
        if ($trimmed -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
            throw "Guide evidence $Name must be a logical identifier."
        }
        return $trimmed
    }

    function ConvertTo-GuideUtc {
        param(
            [AllowEmptyString()][string]$Value,
            [Parameter(Mandatory)][string]$Name
        )
        if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
        $text = $Value.Trim()
        if ($text -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,7})?(Z|[+-][0-9]{2}:[0-9]{2})$') {
            throw "Guide evidence $Name must be an ISO-8601 instant."
        }
        $parsed = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse(
                $text,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
                [ref]$parsed)) {
            throw "Guide evidence $Name must be canonical UTC."
        }
        return $parsed.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    }

    $safeSourceId = ConvertTo-GuideIdentifier -Value $SourceId -Name 'SourceId'
    $safeSourceFamily = ConvertTo-GuideIdentifier -Value (Get-TextValue -Explicit $SourceFamily -InputObject $Metadata -Names @('SourceFamily')) -Name 'SourceFamily'
    if ([string]::IsNullOrWhiteSpace($safeSourceFamily)) { $safeSourceFamily = $safeSourceId }

    $safeChannelReference = ConvertTo-GuideIdentifier -Value (Get-TextValue -Explicit $ChannelReference -InputObject $Metadata -Names @('ChannelReference', 'TvgId', 'ChannelId')) -Name 'ChannelReference'
    $safeDisplayName = ConvertTo-ChannelForgeGuideSafeText (Get-TextValue -Explicit $DisplayName -InputObject $Metadata -Names @('DisplayName', 'TvgName'))
    $safeGroup = ConvertTo-ChannelForgeGuideSafeText (Get-TextValue -Explicit $Group -InputObject $Metadata -Names @('GroupTitle', 'Group'))
    $safeTitle = ConvertTo-ChannelForgeGuideSafeText (Get-TextValue -Explicit $Title -InputObject $Metadata -Names @('Title'))
    $safeLeague = ConvertTo-ChannelForgeGuideSafeText (Get-TextValue -Explicit $League -InputObject $Metadata -Names @('League'))
    $safeSport = ConvertTo-ChannelForgeGuideSafeText (Get-TextValue -Explicit $Sport -InputObject $Metadata -Names @('Sport'))
    $safeHome = ConvertTo-ChannelForgeGuideSafeText (Get-TextValue -Explicit $HomeParticipant -InputObject $Metadata -Names @('HomeParticipant', 'HomeTeam'))
    $safeAway = ConvertTo-ChannelForgeGuideSafeText (Get-TextValue -Explicit $AwayParticipant -InputObject $Metadata -Names @('AwayParticipant', 'AwayTeam'))
    $safeTimezone = ConvertTo-ChannelForgeGuideSafeText (Get-TextValue -Explicit $SourceTimezone -InputObject $Metadata -Names @('SourceTimezone', 'Timezone'))
    $safeStart = ConvertTo-GuideUtc -Value (Get-TextValue -Explicit $StartUtc -InputObject $Metadata -Names @('StartUtc', 'Start')) -Name 'StartUtc'
    $safeEnd = ConvertTo-GuideUtc -Value (Get-TextValue -Explicit $EndUtc -InputObject $Metadata -Names @('EndUtc', 'End')) -Name 'EndUtc'

    if (-not [string]::IsNullOrEmpty($safeStart) -and -not [string]::IsNullOrEmpty($safeEnd)) {
        $startValue = [datetimeoffset]::Parse($safeStart, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
        $endValue = [datetimeoffset]::Parse($safeEnd, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
        if ($endValue -le $startValue) { throw 'Guide evidence EndUtc must be later than StartUtc.' }
    }

    $safeEventStatus = if ($EventStatus -ne 'Unknown') {
        $EventStatus
    }
    else {
        Get-TextValue -Explicit '' -InputObject $Metadata -Names @('EventStatus', 'Status')
    }
    if ([string]::IsNullOrWhiteSpace($safeEventStatus)) { $safeEventStatus = 'Unknown' }
    if ($safeEventStatus -notin @('Scheduled', 'Live', 'Postponed', 'Cancelled', 'Rescheduled', 'Delayed', 'Completed', 'Idle', 'Unknown')) {
        throw 'Guide evidence EventStatus is invalid.'
    }

    $metadataEventType = if ($EventType -ne 'Unknown') {
        $EventType
    }
    else {
        Get-TextValue -Explicit '' -InputObject $Metadata -Names @('EventType')
    }
    if ([string]::IsNullOrWhiteSpace($metadataEventType)) { $metadataEventType = 'Unknown' }
    if ($metadataEventType -notin @('Fight', 'PPV', 'TemporaryEvent', 'League', 'SingleTeam', 'StreamingEvent', 'Sports', 'Other', 'Unknown')) {
        throw 'Guide evidence EventType is invalid.'
    }

    $metadataConfidence = Get-MetadataValue -InputObject $Metadata -Names @('ConfidenceScore')
    if ($ConfidenceScore -eq 0 -and $null -ne $metadataConfidence) {
        $parsedConfidence = 0
        if (-not [int]::TryParse([string]$metadataConfidence, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedConfidence) -or $parsedConfidence -lt 0 -or $parsedConfidence -gt 100) {
            throw 'Guide evidence ConfidenceScore is invalid.'
        }
        $ConfidenceScore = $parsedConfidence
    }

    $metadataFreshness = if ($FreshnessState -ne 'Unknown') {
        $FreshnessState
    }
    else {
        Get-TextValue -Explicit '' -InputObject $Metadata -Names @('FreshnessState', 'Freshness')
    }
    if ([string]::IsNullOrWhiteSpace($metadataFreshness)) { $metadataFreshness = 'Unknown' }
    if ($metadataFreshness -notin @('Current', 'Stale', 'Unavailable', 'Unknown')) {
        throw 'Guide evidence FreshnessState is invalid.'
    }

    $metadataConfidenceState = if ($ConfidenceState -ne 'Unresolved') {
        $ConfidenceState
    }
    else {
        Get-TextValue -Explicit '' -InputObject $Metadata -Names @('ConfidenceState')
    }
    if ([string]::IsNullOrWhiteSpace($metadataConfidenceState)) { $metadataConfidenceState = 'Unresolved' }
    if ($metadataConfidenceState -notin @('Confirmed', 'SafeCandidate', 'NeedsReview', 'Unresolved', 'Contradiction', 'StaleSource', 'SourceUnavailable')) {
        throw 'Guide evidence ConfidenceState is invalid.'
    }

    $reasons = [System.Collections.Generic.List[string]]::new()
    foreach ($reason in @($ReasonCodes)) {
        if ($null -eq $reason -or [string]::IsNullOrWhiteSpace([string]$reason)) { continue }
        $safeReason = [string]$reason
        if ($safeReason -notin $allowedReasonCodes) { throw 'Guide evidence contains an invalid reason code.' }
        if (-not $reasons.Contains($safeReason)) { [void]$reasons.Add($safeReason) }
    }
    $metadataReasons = Get-MetadataValue -InputObject $Metadata -Names @('ReasonCodes')
    if ($null -ne $metadataReasons) {
        foreach ($reason in @($metadataReasons)) {
            if ($null -eq $reason -or [string]::IsNullOrWhiteSpace([string]$reason)) { continue }
            $safeReason = [string]$reason
            if ($safeReason -notin $allowedReasonCodes) { throw 'Guide evidence contains an invalid reason code.' }
            if (-not $reasons.Contains($safeReason)) { [void]$reasons.Add($safeReason) }
        }
    }
    if ($EvidenceType -eq 'AcceptedKnowledge' -and -not $reasons.Contains('AcceptedKnowledge')) { [void]$reasons.Add('AcceptedKnowledge') }
    if ([string]::IsNullOrEmpty($safeTitle) -and [string]::IsNullOrEmpty($safeChannelReference)) { [void]$reasons.Add('EvidenceMissing') }

    $resolvedState = $metadataConfidenceState
    if ($metadataFreshness -eq 'Stale') {
        $resolvedState = 'StaleSource'
        if (-not $reasons.Contains('SourceStale')) { [void]$reasons.Add('SourceStale') }
    }
    elseif ($metadataFreshness -eq 'Unavailable') {
        $resolvedState = 'SourceUnavailable'
        if (-not $reasons.Contains('SourceUnavailable')) { [void]$reasons.Add('SourceUnavailable') }
    }
    elseif ($reasons.Contains('EvidenceContradicts')) {
        $resolvedState = 'Contradiction'
    }
    elseif (($resolvedState -eq 'Confirmed' -and $ConfidenceScore -lt 90) -or
        ($resolvedState -eq 'SafeCandidate' -and $ConfidenceScore -lt 70)) {
        $resolvedState = 'NeedsReview'
        if (-not $reasons.Contains('ConfidenceBelowThreshold')) { [void]$reasons.Add('ConfidenceBelowThreshold') }
    }

    $record = [GuideEvidenceRecord]::new()
    $record.EvidenceType = $EvidenceType
    $record.SourceId = $safeSourceId
    $record.SourceFamily = $safeSourceFamily
    $record.SourceRelationship = $SourceRelationship
    $record.ChannelReference = $safeChannelReference
    $record.DisplayName = $safeDisplayName
    $record.Group = $safeGroup
    $record.Title = $safeTitle
    $record.EventType = $metadataEventType
    $record.League = $safeLeague
    $record.Sport = $safeSport
    $record.HomeParticipant = $safeHome
    $record.AwayParticipant = $safeAway
    $record.StartUtc = $safeStart
    $record.EndUtc = $safeEnd
    $record.SourceTimezone = $safeTimezone
    $record.EventStatus = $safeEventStatus
    $record.ConfidenceState = $resolvedState
    $record.ConfidenceScore = $ConfidenceScore
    $record.FreshnessState = $metadataFreshness
    $record.ReasonCodes = @($reasons | Sort-Object)
    return $record
}
