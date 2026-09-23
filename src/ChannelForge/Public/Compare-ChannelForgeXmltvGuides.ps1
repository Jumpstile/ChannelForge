function Compare-ChannelForgeXmltvGuides {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PlaylistId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Observations,
        [Parameter(Mandatory)][datetimeoffset]$EvaluationTimeUtc,
        [ValidateScript({ $_ -gt [timespan]::Zero -and $_ -le [timespan]::FromDays(30) })]
        [timespan]$FreshnessTtl = ([timespan]::FromHours(24)),
        [ValidateScript({ $_ -ge [timespan]::Zero -and $_ -le [timespan]::FromHours(2) })]
        [timespan]$NearTimeWindow = ([timespan]::FromMinutes(15)),
        [AllowEmptyCollection()][object[]]$ExpectedCoverageWindows = @(),
        [AllowEmptyCollection()][object[]]$DurableChannelBindings = @(),
        [AllowEmptyCollection()][object[]]$AcceptedKnowledge = @()
    )

    $contractVersion = 'ChannelForgeExternalEvidenceObservation/v1'
    $safeIdentifierPattern = '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
    $evaluation = $EvaluationTimeUtc.ToUniversalTime()
    $observedRows = [System.Collections.Generic.List[object]]::new()
    $unboundRows = [System.Collections.Generic.List[object]]::new()
    $provenanceRows = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $correlations = [System.Collections.Generic.List[object]]::new()
    $freshnessRows = [System.Collections.Generic.List[object]]::new()
    $coverageRows = [System.Collections.Generic.List[object]]::new()

    function Get-PropertyValue {
        param([AllowNull()][object]$InputObject, [Parameter(Mandatory)][string]$Name)
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.IDictionary]) {
            if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
            return $null
        }
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
        return $null
    }

    function Normalize-ComparisonText {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { return '' }
        return [regex]::Replace(([string]$Value).Trim().ToLowerInvariant(), '\s+', ' ')
    }

    function ConvertTo-OptionalUtcInstant {
        param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
        $parsed = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse(
                [string]$Value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
                [ref]$parsed)) {
            throw "$Name must be an ISO-8601 instant."
        }
        return $parsed.ToUniversalTime()
    }

    function Get-SafeIdentifier {
        param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
        $text = ([string]$Value).Trim()
        if ($text -notmatch $safeIdentifierPattern) { throw "$Name must be a safe logical identifier." }
        return $text
    }

    function Get-RowField {
        param([Parameter(Mandatory)][object]$Row, [Parameter(Mandatory)][string]$Name)
        if ($Row.Fields.Contains($Name)) { return $Row.Fields[$Name] }
        return $null
    }

    function Add-ComparisonFinding {
        param(
            [Parameter(Mandatory)][string]$Kind,
            [Parameter(Mandatory)][string]$Status,
            [AllowEmptyCollection()][string[]]$SourceIds = @(),
            [AllowEmptyCollection()][string[]]$ObservationIds = @(),
            [AllowNull()][string]$ChannelId = $null,
            [AllowNull()][object]$Details = $null
        )
        $orderedSources = @($SourceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $orderedObservationIds = @($ObservationIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $identity = [ordered]@{
            Kind = $Kind
            SourceIds = $orderedSources
            ObservationIds = $orderedObservationIds
            ChannelId = $ChannelId
            Details = $Details
        }
        $identityBytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $identity))
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $findingId = ([BitConverter]::ToString($sha.ComputeHash($identityBytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        [void]$findings.Add([pscustomobject][ordered]@{
            FindingId = $findingId
            Kind = $Kind
            Status = $Status
            SourceIds = $orderedSources
            ObservationIds = $orderedObservationIds
            ChannelId = $ChannelId
            Details = $Details
            ReviewRequired = ($Status -in @('Contradiction', 'NeedsReview', 'StaleSource', 'SourceUnavailable'))
        })
    }

    function Test-IntervalsOverlap {
        param([AllowNull()][datetimeoffset]$LeftStart, [AllowNull()][datetimeoffset]$LeftStop, [AllowNull()][datetimeoffset]$RightStart, [AllowNull()][datetimeoffset]$RightStop)
        if ($null -eq $LeftStart -or $null -eq $LeftStop -or $null -eq $RightStart -or $null -eq $RightStop) { return $false }
        return ($LeftStart -lt $RightStop -and $RightStart -lt $LeftStop)
    }

    function Test-IntervalsNear {
        param([Parameter(Mandatory)][object]$Left, [Parameter(Mandatory)][object]$Right)
        if ($null -eq $Left.StartUtc -or $null -eq $Left.StopUtc -or $null -eq $Right.StartUtc -or $null -eq $Right.StopUtc) { return $false }
        if (Test-IntervalsOverlap -LeftStart $Left.StartUtc -LeftStop $Left.StopUtc -RightStart $Right.StartUtc -RightStop $Right.StopUtc) { return $true }
        $gap = if ($Left.StopUtc -le $Right.StartUtc) { $Right.StartUtc - $Left.StopUtc } else { $Left.StartUtc - $Right.StopUtc }
        return ($gap -le $NearTimeWindow)
    }

    function Test-EqualStringSets {
        param([AllowEmptyCollection()][string[]]$Left, [AllowEmptyCollection()][string[]]$Right)
        $leftValues = @($Left | ForEach-Object { Normalize-ComparisonText $_ } | Where-Object { $_ } | Sort-Object -Unique)
        $rightValues = @($Right | ForEach-Object { Normalize-ComparisonText $_ } | Where-Object { $_ } | Sort-Object -Unique)
        return (($leftValues -join "`n") -ceq ($rightValues -join "`n"))
    }

    function Get-CorrelationCandidate {
        param([Parameter(Mandatory)][object]$Left, [Parameter(Mandatory)][object]$Right)
        if ([string]::IsNullOrWhiteSpace([string]$Left.ScopeKey) -or [string]$Left.ScopeKey -cne [string]$Right.ScopeKey) { return $null }
        if ([string]$Left.SourceId -ceq [string]$Right.SourceId) { return $null }

        $basis = [System.Collections.Generic.List[string]]::new()
        $sameFamily = -not [string]::IsNullOrWhiteSpace([string]$Left.SourceFamily) -and [string]$Left.SourceFamily -ceq [string]$Right.SourceFamily
        $sameRecord = $sameFamily -and -not [string]::IsNullOrWhiteSpace([string]$Left.SourceRecordReference) -and [string]$Left.SourceRecordReference -ceq [string]$Right.SourceRecordReference
        $sameProvisional = $sameFamily -and -not [string]::IsNullOrWhiteSpace([string]$Left.ProvisionalSubjectKey) -and [string]$Left.ProvisionalSubjectKey -ceq [string]$Right.ProvisionalSubjectKey
        $leftTitle = Normalize-ComparisonText $Left.Title
        $rightTitle = Normalize-ComparisonText $Right.Title
        $sameTitle = $leftTitle.Length -gt 0 -and $leftTitle -ceq $rightTitle
        $sameParticipants = Test-EqualStringSets -Left $Left.Participants -Right $Right.Participants
        $hasParticipants = @($Left.Participants).Count -gt 0 -and @($Right.Participants).Count -gt 0
        $nearTime = Test-IntervalsNear -Left $Left -Right $Right
        $sameSubtitle = (Normalize-ComparisonText $Left.Subtitle).Length -gt 0 -and (Normalize-ComparisonText $Left.Subtitle) -ceq (Normalize-ComparisonText $Right.Subtitle)

        if ($sameRecord) { [void]$basis.Add('SharedSourceRecordReference') }
        if ($sameProvisional) { [void]$basis.Add('SharedProvisionalSubjectKey') }
        if ($sameTitle) { [void]$basis.Add('NormalizedTitle') }
        if ($sameParticipants) { [void]$basis.Add('NormalizedParticipants') }
        if ($sameSubtitle) { [void]$basis.Add('NormalizedSubtitle') }
        if ($nearTime) { [void]$basis.Add('OverlappingOrNearIntervals') }
        if ($sameFamily) { [void]$basis.Add('SourceFamilyContext') }

        $identityHint = $sameRecord -or $sameProvisional
        $semanticAndTime = $nearTime -and ($sameTitle -or ($hasParticipants -and $sameParticipants))
        if (-not ($identityHint -or $semanticAndTime)) { return $null }
        return [pscustomobject][ordered]@{ Left = $Left; Right = $Right; Basis = @($basis | Sort-Object -Unique) }
    }

    if ([string]::IsNullOrWhiteSpace($PlaylistId)) { throw 'PlaylistId is required.' }
    if ($FreshnessTtl -le [timespan]::Zero -or $FreshnessTtl -gt [timespan]::FromDays(30)) { throw 'FreshnessTtl must be positive and no longer than 30 days.' }
    if ($NearTimeWindow -lt [timespan]::Zero -or $NearTimeWindow -gt [timespan]::FromHours(2)) { throw 'NearTimeWindow must be between zero and two hours.' }

    $windows = [System.Collections.Generic.List[object]]::new()
    foreach ($window in @($ExpectedCoverageWindows)) {
        if ($null -eq $window) { throw 'ExpectedCoverageWindows cannot contain null entries.' }
        $sourceId = Get-SafeIdentifier (Get-PropertyValue $window 'SourceId') 'ExpectedCoverageWindow.SourceId'
        $channelId = Get-SafeIdentifier (Get-PropertyValue $window 'ChannelId') 'ExpectedCoverageWindow.ChannelId'
        $channelReference = Get-SafeIdentifier (Get-PropertyValue $window 'SourceChannelReference') 'ExpectedCoverageWindow.SourceChannelReference'
        if ([string]::IsNullOrWhiteSpace($sourceId) -or ([string]::IsNullOrWhiteSpace($channelId) -and [string]::IsNullOrWhiteSpace($channelReference))) {
            throw 'Each expected coverage window requires a SourceId and ChannelId or SourceChannelReference.'
        }
        $start = ConvertTo-OptionalUtcInstant (Get-PropertyValue $window 'StartUtc') 'ExpectedCoverageWindow.StartUtc'
        $stop = ConvertTo-OptionalUtcInstant (Get-PropertyValue $window 'StopUtc') 'ExpectedCoverageWindow.StopUtc'
        if ($null -eq $start -or $null -eq $stop -or $stop -le $start) { throw 'Expected coverage windows require a positive explicit UTC interval.' }
        $scopeKey = if ($channelId) { "channel:$channelId" } else { "reference:$channelReference" }
        [void]$windows.Add([pscustomobject][ordered]@{ SourceId = $sourceId; ChannelId = $channelId; SourceChannelReference = $channelReference; ScopeKey = $scopeKey; StartUtc = $start; StopUtc = $stop })
    }

    $seenObservations = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($observation in @($Observations | Sort-Object @{Expression={ [string](Get-PropertyValue $_ 'SourceId') }}, @{Expression={ [string](Get-PropertyValue $_ 'ObservationId') }})) {
        if ($null -eq $observation) { throw 'Observations cannot contain null entries.' }
        $version = [string](Get-PropertyValue $observation 'ContractVersion')
        if ($version -cne $contractVersion) { throw "Observations must use $contractVersion." }
        if ((Get-PropertyValue $observation 'ReadOnly') -ne $true) { throw 'External evidence observations must be read-only.' }
        $observationId = [string](Get-PropertyValue $observation 'ObservationId')
        if ($observationId -notmatch '^[a-f0-9]{64}$') { throw 'ObservationId must be a lowercase SHA-256 identifier.' }
        $sourceId = Get-SafeIdentifier (Get-PropertyValue $observation 'SourceId') 'Observation.SourceId'
        $sourceFamily = Get-SafeIdentifier (Get-PropertyValue $observation 'SourceFamily') 'Observation.SourceFamily'
        $uniqueKey = "$sourceId|$observationId"
        if (-not $seenObservations.Add($uniqueKey)) { continue }

        $fieldMap = @{}
        foreach ($field in @(Get-PropertyValue $observation 'FieldObservations')) {
            if ($null -eq $field) { throw 'FieldObservations cannot contain null entries.' }
            $name = [string](Get-PropertyValue $field 'FieldName')
            if ([string]::IsNullOrWhiteSpace($name)) { throw 'Every field observation requires FieldName.' }
            $value = Get-PropertyValue $field 'NormalizedValue'
            if (-not $fieldMap.ContainsKey($name)) { $fieldMap[$name] = [System.Collections.Generic.List[string]]::new() }
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                foreach ($item in $value) { if ($null -ne $item) { [void]$fieldMap[$name].Add(([string]$item).Trim()) } }
            }
            elseif ($null -ne $value) { [void]$fieldMap[$name].Add(([string]$value).Trim()) }
        }
        $fields = @{}
        foreach ($name in $fieldMap.Keys) {
            $values = @($fieldMap[$name] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            if ($name -eq 'Participant') { $fields[$name] = $values }
            elseif ($values.Count -le 1) { $fields[$name] = if ($values.Count -eq 1) { $values[0] } else { $null } }
            else {
                $fields[$name] = $null
                Add-ComparisonFinding -Kind 'AmbiguousFieldObservation' -Status 'NeedsReview' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ FieldName = $name; Values = $values })
            }
        }

        $bindingContext = Get-PropertyValue $observation 'BindingContext'
        $bindingKind = [string](Get-PropertyValue $bindingContext 'BindingKind')
        $boundPlaylistId = [string](Get-PropertyValue $bindingContext 'PlaylistId')
        $channelReference = [string](Get-PropertyValue $bindingContext 'ChannelReference')
        if ([string]::IsNullOrWhiteSpace($channelReference)) { $channelReference = [string](Get-PropertyValue $observation 'SourceChannelReference') }
        if ([string]::IsNullOrWhiteSpace($channelReference)) { $channelReference = [string](Get-PropertyValue $bindingContext 'StationReference') }
        $channelReference = Get-SafeIdentifier $channelReference 'Observation.ChannelReference'
        $isBound = ($bindingKind -eq 'Shared') -or ($bindingKind -eq 'SourceScoped' -and $boundPlaylistId -ceq $PlaylistId)
        $isOutOfScope = ($bindingKind -eq 'SourceScoped' -and -not [string]::IsNullOrWhiteSpace($boundPlaylistId) -and $boundPlaylistId -cne $PlaylistId)
        $freshnessInstant = ConvertTo-OptionalUtcInstant (Get-PropertyValue $observation 'SourceDataTimeUtc') 'Observation.SourceDataTimeUtc'
        if ($null -eq $freshnessInstant) { $freshnessInstant = ConvertTo-OptionalUtcInstant (Get-PropertyValue $observation 'FetchTimeUtc') 'Observation.FetchTimeUtc' }
        $freshnessState = if ($null -eq $freshnessInstant) { 'Unknown' } elseif ($freshnessInstant -gt $evaluation) { 'FutureDated' } elseif (($evaluation - $freshnessInstant) -gt $FreshnessTtl) { 'Stale' } else { 'Fresh' }
        $freshnessAssessment = [pscustomobject][ordered]@{
            ObservationId = $observationId
            SourceId = $sourceId
            SourceDataTimeUtc = Get-PropertyValue $observation 'SourceDataTimeUtc'
            FetchTimeUtc = Get-PropertyValue $observation 'FetchTimeUtc'
            EvaluationTimeUtc = $evaluation.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
            FreshnessTtl = $FreshnessTtl.ToString('c', [Globalization.CultureInfo]::InvariantCulture)
            FreshnessState = $freshnessState
        }
        [void]$freshnessRows.Add($freshnessAssessment)
        $status = [string](Get-PropertyValue $observation 'ObservationStatus')
        $provenance = [pscustomobject][ordered]@{
            ObservationId = $observationId
            SourceId = $sourceId
            SourceFamily = $sourceFamily
            AdapterId = Get-PropertyValue $observation 'AdapterId'
            AdapterVersion = Get-PropertyValue $observation 'AdapterVersion'
            ParserVersion = Get-PropertyValue $observation 'ParserVersion'
            EvidenceClass = Get-PropertyValue $observation 'EvidenceClass'
            SourceRelationship = Get-PropertyValue $observation 'SourceRelationship'
            SourceRecordReference = Get-PropertyValue $observation 'SourceRecordReference'
            ProvisionalSubjectKey = Get-PropertyValue $observation 'ProvisionalSubjectKey'
            BindingKind = $bindingKind
            PlaylistId = $boundPlaylistId
            ChannelReference = $channelReference
            SourceDataTimeUtc = Get-PropertyValue $observation 'SourceDataTimeUtc'
            ObservationTimeUtc = Get-PropertyValue $observation 'ObservationTimeUtc'
            FetchTimeUtc = Get-PropertyValue $observation 'FetchTimeUtc'
            ObservationStatus = $status
            FreshnessState = $freshnessState
        }
        [void]$provenanceRows.Add($provenance)

        if ($status -eq 'SourceUnavailable') {
            Add-ComparisonFinding -Kind 'SourceUnavailable' -Status 'SourceUnavailable' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ ReasonCodes = @(Get-PropertyValue $observation 'ReasonCodes') })
            continue
        }
        if ($status -eq 'Rejected') {
            Add-ComparisonFinding -Kind 'RejectedObservation' -Status 'NeedsReview' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ ReasonCodes = @(Get-PropertyValue $observation 'ReasonCodes') })
            continue
        }
        if ($freshnessState -eq 'Stale') {
            Add-ComparisonFinding -Kind 'StaleObservation' -Status 'StaleSource' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ FreshnessReferenceUtc = $freshnessInstant.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture); EvaluationTimeUtc = $freshnessAssessment.EvaluationTimeUtc })
        }
        elseif ($freshnessState -eq 'FutureDated') {
            Add-ComparisonFinding -Kind 'FutureDatedObservation' -Status 'NeedsReview' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ FreshnessReferenceUtc = $freshnessInstant.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture); EvaluationTimeUtc = $freshnessAssessment.EvaluationTimeUtc })
        }

        if ($isOutOfScope) {
            Add-ComparisonFinding -Kind 'OutOfScopeEvidence' -Status 'Informational' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ BoundPlaylistId = $boundPlaylistId; RequestedPlaylistId = $PlaylistId })
            continue
        }
        if (-not $isBound) {
            [void]$unboundRows.Add($provenance)
            Add-ComparisonFinding -Kind 'UnboundEvidence' -Status 'NeedsReview' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ BindingKind = $bindingKind; ChannelReference = $channelReference; Applied = $false })
            continue
        }

        $channelId = ''
        $mappingMatches = @($DurableChannelBindings | Where-Object {
                ([string](Get-PropertyValue $_ 'PlaylistId') -ceq $PlaylistId) -and
                ([string](Get-PropertyValue $_ 'SourceId') -ceq $sourceId) -and
                ([string](Get-PropertyValue $_ 'SourceChannelReference') -ceq $channelReference)
            })
        if ($mappingMatches.Count -gt 1) {
            Add-ComparisonFinding -Kind 'AmbiguousDurableBinding' -Status 'NeedsReview' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ ChannelReference = $channelReference; BindingCount = $mappingMatches.Count })
        }
        elseif ($mappingMatches.Count -eq 1) {
            $channelId = Get-SafeIdentifier (Get-PropertyValue $mappingMatches[0] 'ChannelId') 'DurableChannelBinding.ChannelId'
            if ([string]::IsNullOrWhiteSpace($channelId)) { throw 'DurableChannelBindings require ChannelId.' }
            $expectedAssignments = @(
                (Get-PropertyValue $mappingMatches[0] 'Network'),
                (Get-PropertyValue $mappingMatches[0] 'ChannelAssignment'),
                $channelId
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { Normalize-ComparisonText $_ } | Sort-Object -Unique
            $observedAssignments = @((Get-RowField -Row ([pscustomobject]@{ Fields = $fields }) -Name 'Network'), (Get-RowField -Row ([pscustomobject]@{ Fields = $fields }) -Name 'ChannelAssignment')) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { Normalize-ComparisonText $_ } | Sort-Object -Unique
            if ($observedAssignments.Count -gt 0 -and @($observedAssignments | Where-Object { $_ -in $expectedAssignments }).Count -eq 0) {
                Add-ComparisonFinding -Kind 'SuspiciousAssignment' -Status 'NeedsReview' -SourceIds @($sourceId) -ObservationIds @($observationId) -ChannelId $channelId -Details ([ordered]@{ ObservedAssignments = $observedAssignments; ExistingAssignments = $expectedAssignments; Retargeted = $false })
            }
        }
        $scopeKey = if ($channelId) { "channel:$channelId" } elseif ($channelReference) { "reference:$channelReference" } else { '' }
        if ([string]::IsNullOrWhiteSpace($scopeKey)) {
            Add-ComparisonFinding -Kind 'UnscopedEvidence' -Status 'NeedsReview' -SourceIds @($sourceId) -ObservationIds @($observationId) -Details ([ordered]@{ Applied = $false })
            continue
        }

        $startUtc = ConvertTo-OptionalUtcInstant (Get-RowField -Row ([pscustomobject]@{ Fields = $fields }) -Name 'UpdatedStartUtc') 'FieldObservations.UpdatedStartUtc'
        if ($null -eq $startUtc) { $startUtc = ConvertTo-OptionalUtcInstant (Get-RowField -Row ([pscustomobject]@{ Fields = $fields }) -Name 'ScheduledStartUtc') 'FieldObservations.ScheduledStartUtc' }
        $stopUtc = ConvertTo-OptionalUtcInstant (Get-RowField -Row ([pscustomobject]@{ Fields = $fields }) -Name 'StopUtc') 'FieldObservations.StopUtc'
        if ($null -ne $startUtc -and $null -ne $stopUtc -and $stopUtc -le $startUtc) { throw 'Observed StopUtc must be later than the effective start time.' }
        $participants = @()
        if ($fields.ContainsKey('Participant')) { $participants = @($fields.Participant | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique) }
        $row = [pscustomobject][ordered]@{
            ObservationId = $observationId
            SourceId = $sourceId
            SourceFamily = $sourceFamily
            SourceRecordReference = [string](Get-PropertyValue $observation 'SourceRecordReference')
            ProvisionalSubjectKey = [string](Get-PropertyValue $observation 'ProvisionalSubjectKey')
            SourceRelationship = [string](Get-PropertyValue $observation 'SourceRelationship')
            EvidenceClass = [string](Get-PropertyValue $observation 'EvidenceClass')
            ScopeKey = $scopeKey
            ChannelId = if ($channelId) { $channelId } else { $null }
            ChannelReference = $channelReference
            Title = [string]$fields.Title
            Subtitle = [string]$fields.Subtitle
            Description = [string]$fields.Description
            Competition = [string]$fields.Competition
            Venue = [string]$fields.Venue
            EventStatus = [string]$fields.EventStatus
            Participants = $participants
            ScheduledStartUtc = ConvertTo-OptionalUtcInstant $fields.ScheduledStartUtc 'FieldObservations.ScheduledStartUtc'
            UpdatedStartUtc = ConvertTo-OptionalUtcInstant $fields.UpdatedStartUtc 'FieldObservations.UpdatedStartUtc'
            StartUtc = $startUtc
            StopUtc = $stopUtc
            Fields = $fields
            FreshnessState = $freshnessState
        }
        [void]$observedRows.Add($row)
    }

    $candidateEdges = [System.Collections.Generic.List[object]]::new()
    for ($leftIndex = 0; $leftIndex -lt $observedRows.Count; $leftIndex++) {
        for ($rightIndex = $leftIndex + 1; $rightIndex -lt $observedRows.Count; $rightIndex++) {
            $candidate = Get-CorrelationCandidate -Left $observedRows[$leftIndex] -Right $observedRows[$rightIndex]
            if ($null -ne $candidate) { [void]$candidateEdges.Add($candidate) }
        }
    }

    $uniqueEdges = [System.Collections.Generic.List[object]]::new()
    $ambiguousEdgeKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($edge in $candidateEdges) {
        $leftAlternatives = @($candidateEdges | Where-Object { $_.Left.ObservationId -ceq $edge.Left.ObservationId -and $_.Right.SourceId -ceq $edge.Right.SourceId })
        $rightAlternatives = @($candidateEdges | Where-Object { $_.Right.ObservationId -ceq $edge.Right.ObservationId -and $_.Left.SourceId -ceq $edge.Left.SourceId })
        if ($leftAlternatives.Count -gt 1 -or $rightAlternatives.Count -gt 1) {
            $key = "$($edge.Left.ObservationId)|$($edge.Right.ObservationId)"
            if ($ambiguousEdgeKeys.Add($key)) {
                $leftCandidates = @($leftAlternatives | ForEach-Object { $_.Right.ObservationId } | Sort-Object -Unique)
                $rightCandidates = @($rightAlternatives | ForEach-Object { $_.Left.ObservationId } | Sort-Object -Unique)
                Add-ComparisonFinding -Kind 'AmbiguousCorrelation' -Status 'NeedsReview' -SourceIds @($edge.Left.SourceId, $edge.Right.SourceId) -ObservationIds @($edge.Left.ObservationId, $edge.Right.ObservationId) -ChannelId $edge.Left.ChannelId -Details ([ordered]@{ LeftCandidates = $leftCandidates; RightCandidates = $rightCandidates; CorrelationBasis = $edge.Basis; WinnerSelected = $false })
            }
            continue
        }
        [void]$uniqueEdges.Add($edge)
    }

    $matchedObservationSources = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $uniqueEdgeLookup = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($edge in $uniqueEdges) {
        $pairKey = (@($edge.Left.ObservationId, $edge.Right.ObservationId) | Sort-Object) -join '|'
        [void]$uniqueEdgeLookup.Add($pairKey)
        [void]$matchedObservationSources.Add("$($edge.Left.ObservationId)|$($edge.Right.SourceId)")
        [void]$matchedObservationSources.Add("$($edge.Right.ObservationId)|$($edge.Left.SourceId)")

        $leftTitle = Normalize-ComparisonText $edge.Left.Title
        $rightTitle = Normalize-ComparisonText $edge.Right.Title
        $leftParticipants = @($edge.Left.Participants | ForEach-Object { Normalize-ComparisonText $_ } | Sort-Object -Unique)
        $rightParticipants = @($edge.Right.Participants | ForEach-Object { Normalize-ComparisonText $_ } | Sort-Object -Unique)
        $materialConflict = $false
        if ($leftTitle -and $rightTitle -and $leftTitle -cne $rightTitle) {
            $materialConflict = $true
            Add-ComparisonFinding -Kind 'TitleConflict' -Status 'Contradiction' -SourceIds @($edge.Left.SourceId, $edge.Right.SourceId) -ObservationIds @($edge.Left.ObservationId, $edge.Right.ObservationId) -ChannelId $edge.Left.ChannelId -Details ([ordered]@{ Values = @([ordered]@{ SourceId = $edge.Left.SourceId; Title = $edge.Left.Title }, [ordered]@{ SourceId = $edge.Right.SourceId; Title = $edge.Right.Title }) })
        }
        if ($leftParticipants.Count -gt 0 -and $rightParticipants.Count -gt 0 -and -not (Test-EqualStringSets -Left $edge.Left.Participants -Right $edge.Right.Participants)) {
            $materialConflict = $true
            Add-ComparisonFinding -Kind 'ParticipantConflict' -Status 'Contradiction' -SourceIds @($edge.Left.SourceId, $edge.Right.SourceId) -ObservationIds @($edge.Left.ObservationId, $edge.Right.ObservationId) -ChannelId $edge.Left.ChannelId -Details ([ordered]@{ Values = @([ordered]@{ SourceId = $edge.Left.SourceId; Participants = $edge.Left.Participants }, [ordered]@{ SourceId = $edge.Right.SourceId; Participants = $edge.Right.Participants }) })
        }
        $startShift = $null -ne $edge.Left.StartUtc -and $null -ne $edge.Right.StartUtc -and $edge.Left.StartUtc -ne $edge.Right.StartUtc
        $stopShift = $null -ne $edge.Left.StopUtc -and $null -ne $edge.Right.StopUtc -and $edge.Left.StopUtc -ne $edge.Right.StopUtc
        if ($startShift -or $stopShift) {
            $shift = if ($startShift -and $stopShift) { 'StartAndStopTimeShift' } elseif ($startShift) { 'StartTimeShift' } else { 'StopTimeShift' }
            $materialConflict = $true
            Add-ComparisonFinding -Kind 'TimeConflict' -Status 'Contradiction' -SourceIds @($edge.Left.SourceId, $edge.Right.SourceId) -ObservationIds @($edge.Left.ObservationId, $edge.Right.ObservationId) -ChannelId $edge.Left.ChannelId -Details ([ordered]@{ Shift = $shift; Values = @([ordered]@{ SourceId = $edge.Left.SourceId; StartUtc = if ($null -ne $edge.Left.StartUtc) { $edge.Left.StartUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) }; StopUtc = if ($null -ne $edge.Left.StopUtc) { $edge.Left.StopUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) } }, [ordered]@{ SourceId = $edge.Right.SourceId; StartUtc = if ($null -ne $edge.Right.StartUtc) { $edge.Right.StartUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) }; StopUtc = if ($null -ne $edge.Right.StopUtc) { $edge.Right.StopUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) } }) })
        }
        $metadataVariations = [System.Collections.Generic.List[object]]::new()
        foreach ($fieldName in @('Subtitle', 'Description', 'Competition', 'Venue', 'EventStatus')) {
            $leftValue = [string]$edge.Left.$fieldName
            $rightValue = [string]$edge.Right.$fieldName
            if ((Normalize-ComparisonText $leftValue) -cne (Normalize-ComparisonText $rightValue) -and ($leftValue -or $rightValue)) {
                [void]$metadataVariations.Add([ordered]@{ FieldName = $fieldName; Values = @([ordered]@{ SourceId = $edge.Left.SourceId; Value = $leftValue }, [ordered]@{ SourceId = $edge.Right.SourceId; Value = $rightValue }) })
            }
        }
        if ($metadataVariations.Count -gt 0) {
            Add-ComparisonFinding -Kind 'HarmlessMetadataVariation' -Status 'Informational' -SourceIds @($edge.Left.SourceId, $edge.Right.SourceId) -ObservationIds @($edge.Left.ObservationId, $edge.Right.ObservationId) -ChannelId $edge.Left.ChannelId -Details ([ordered]@{ Variations = @($metadataVariations) })
        }
        if (-not $materialConflict -and $metadataVariations.Count -eq 0) {
            Add-ComparisonFinding -Kind 'ExactAgreement' -Status 'Informational' -SourceIds @($edge.Left.SourceId, $edge.Right.SourceId) -ObservationIds @($edge.Left.ObservationId, $edge.Right.ObservationId) -ChannelId $edge.Left.ChannelId -Details ([ordered]@{ CorrelationBasis = $edge.Basis; SourceRelationships = @($edge.Left.SourceRelationship, $edge.Right.SourceRelationship) })
        }
        [void]$correlations.Add([pscustomobject][ordered]@{
            CorrelationId = $edge.Left.ObservationId + ':' + $edge.Right.ObservationId
            ObservationIds = @(@($edge.Left.ObservationId, $edge.Right.ObservationId) | Sort-Object)
            SourceIds = @(@($edge.Left.SourceId, $edge.Right.SourceId) | Sort-Object -Unique)
            ChannelId = $edge.Left.ChannelId
            CorrelationBasis = $edge.Basis
            SourceRelationships = @($edge.Left.SourceRelationship, $edge.Right.SourceRelationship)
            Ambiguous = $false
        })
    }

    foreach ($row in $observedRows) {
        if ($null -eq $row.StartUtc -or $null -eq $row.StopUtc) { continue }
        foreach ($window in @($windows | Where-Object { $_.SourceId -cne $row.SourceId -and $_.ScopeKey -ceq $row.ScopeKey -and $_.StartUtc -le $row.StartUtc -and $_.StopUtc -ge $row.StopUtc })) {
            if (-not $matchedObservationSources.Contains("$($row.ObservationId)|$($window.SourceId)")) {
                Add-ComparisonFinding -Kind 'ProgrammeMissing' -Status 'NeedsReview' -SourceIds @($row.SourceId, $window.SourceId) -ObservationIds @($row.ObservationId) -ChannelId $row.ChannelId -Details ([ordered]@{ MissingFromSourceId = $window.SourceId; ExpectedWindowStartUtc = $window.StartUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture); ExpectedWindowStopUtc = $window.StopUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture); Title = $row.Title })
            }
        }
    }

    foreach ($window in $windows) {
        $intervals = @($observedRows | Where-Object { $_.SourceId -ceq $window.SourceId -and $_.ScopeKey -ceq $window.ScopeKey -and $null -ne $_.StartUtc -and $null -ne $_.StopUtc -and $_.StartUtc -lt $window.StopUtc -and $_.StopUtc -gt $window.StartUtc } | Sort-Object @{Expression={$_.StartUtc}}, @{Expression={$_.StopUtc}}, @{Expression={$_.ObservationId}})
        $cursor = $window.StartUtc
        foreach ($interval in $intervals) {
            $intervalStart = if ($interval.StartUtc -lt $window.StartUtc) { $window.StartUtc } else { $interval.StartUtc }
            $intervalStop = if ($interval.StopUtc -gt $window.StopUtc) { $window.StopUtc } else { $interval.StopUtc }
            if ($intervalStart -gt $cursor) {
                $gap = [pscustomobject][ordered]@{ SourceId = $window.SourceId; ChannelId = $window.ChannelId; SourceChannelReference = $window.SourceChannelReference; StartUtc = $cursor.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture); StopUtc = $intervalStart.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) }
                [void]$coverageRows.Add($gap)
                Add-ComparisonFinding -Kind 'CoverageGap' -Status 'NeedsReview' -SourceIds @($window.SourceId) -ChannelId $window.ChannelId -Details ([ordered]@{ SourceChannelReference = $window.SourceChannelReference; StartUtc = $cursor.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture); StopUtc = $intervalStart.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) })
            }
            if ($intervalStop -gt $cursor) { $cursor = $intervalStop }
        }
        if ($cursor -lt $window.StopUtc) {
            $gap = [pscustomobject][ordered]@{ SourceId = $window.SourceId; ChannelId = $window.ChannelId; SourceChannelReference = $window.SourceChannelReference; StartUtc = $cursor.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture); StopUtc = $window.StopUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) }
            [void]$coverageRows.Add($gap)
            Add-ComparisonFinding -Kind 'CoverageGap' -Status 'NeedsReview' -SourceIds @($window.SourceId) -ChannelId $window.ChannelId -Details ([ordered]@{ SourceChannelReference = $window.SourceChannelReference; StartUtc = $cursor.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture); StopUtc = $window.StopUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) })
        }
    }

    for ($leftIndex = 0; $leftIndex -lt $observedRows.Count; $leftIndex++) {
        for ($rightIndex = $leftIndex + 1; $rightIndex -lt $observedRows.Count; $rightIndex++) {
            $left = $observedRows[$leftIndex]
            $right = $observedRows[$rightIndex]
            if ($left.ScopeKey -cne $right.ScopeKey -or -not (Test-IntervalsOverlap -LeftStart $left.StartUtc -LeftStop $left.StopUtc -RightStart $right.StartUtc -RightStop $right.StopUtc)) { continue }
            $edgeKey = (@($left.ObservationId, $right.ObservationId) | Sort-Object) -join '|'
            $isCorrelated = $uniqueEdgeLookup.Contains($edgeKey)
            $sameEvent = (Normalize-ComparisonText $left.Title) -ceq (Normalize-ComparisonText $right.Title) -and (Test-EqualStringSets -Left $left.Participants -Right $right.Participants)
            $exactInterval = $left.StartUtc -eq $right.StartUtc -and $left.StopUtc -eq $right.StopUtc
            $overlapKind = if ($sameEvent -and $exactInterval) { 'BenignExactDuplicateOverlap' } elseif ($isCorrelated) { 'CorrelatedTimeShiftOverlap' } else { 'MaterialOverlap' }
            $overlapStatus = if ($overlapKind -eq 'MaterialOverlap') { 'Contradiction' } else { 'Informational' }
            $overlapStart = if ($left.StartUtc -ge $right.StartUtc) { $left.StartUtc } else { $right.StartUtc }
            $overlapStop = if ($left.StopUtc -le $right.StopUtc) { $left.StopUtc } else { $right.StopUtc }
            Add-ComparisonFinding -Kind $overlapKind -Status $overlapStatus -SourceIds @($left.SourceId, $right.SourceId) -ObservationIds @($left.ObservationId, $right.ObservationId) -ChannelId $left.ChannelId -Details ([ordered]@{
                OverlapType = if ($left.SourceId -ceq $right.SourceId) { 'SameSource' } else { 'CrossSource' }
                StartUtc = $overlapStart.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
                StopUtc = $overlapStop.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
                Retargeted = $false
            })
        }
    }

    $acceptedRows = [System.Collections.Generic.List[object]]::new()
    foreach ($knowledge in @($AcceptedKnowledge)) {
        if ($null -eq $knowledge) { throw 'AcceptedKnowledge cannot contain null entries.' }
        $channelId = Get-SafeIdentifier (Get-PropertyValue $knowledge 'ChannelId') 'AcceptedKnowledge.ChannelId'
        if ([string]::IsNullOrWhiteSpace($channelId)) { throw 'AcceptedKnowledge requires an existing ChannelId.' }
        $knowledgeId = Get-SafeIdentifier (Get-PropertyValue $knowledge 'KnowledgeId') 'AcceptedKnowledge.KnowledgeId'
        if ([string]::IsNullOrWhiteSpace($knowledgeId)) {
            $knowledgeProjection = [ordered]@{ ChannelId = $channelId; Title = Get-PropertyValue $knowledge 'Title'; StartUtc = Get-PropertyValue $knowledge 'StartUtc'; StopUtc = Get-PropertyValue $knowledge 'StopUtc' }
            $knowledgeBytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $knowledgeProjection))
            $knowledgeSha = [Security.Cryptography.SHA256]::Create()
            try { $knowledgeId = ([BitConverter]::ToString($knowledgeSha.ComputeHash($knowledgeBytes))).Replace('-', '').ToLowerInvariant() }
            finally { $knowledgeSha.Dispose() }
        }
        $participantsValue = Get-PropertyValue $knowledge 'Participants'
        $participants = @($participantsValue | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        [void]$acceptedRows.Add([pscustomobject][ordered]@{
            ObservationId = "accepted:$knowledgeId"
            SourceId = 'accepted-knowledge'
            SourceFamily = 'accepted-knowledge'
            SourceRecordReference = $knowledgeId
            ProvisionalSubjectKey = ''
            SourceRelationship = 'AcceptedKnowledge'
            EvidenceClass = 'AcceptedKnowledge'
            ScopeKey = "channel:$channelId"
            ChannelId = $channelId
            ChannelReference = ''
            Title = [string](Get-PropertyValue $knowledge 'Title')
            Subtitle = [string](Get-PropertyValue $knowledge 'Subtitle')
            Description = ''
            Competition = ''
            Venue = ''
            EventStatus = ''
            Participants = $participants
            ScheduledStartUtc = $null
            UpdatedStartUtc = $null
            StartUtc = ConvertTo-OptionalUtcInstant (Get-PropertyValue $knowledge 'StartUtc') 'AcceptedKnowledge.StartUtc'
            StopUtc = ConvertTo-OptionalUtcInstant (Get-PropertyValue $knowledge 'StopUtc') 'AcceptedKnowledge.StopUtc'
            Fields = @{}
            FreshnessState = 'Accepted'
        })
    }
    foreach ($row in $observedRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.ChannelId) }) {
        $acceptedCandidates = [System.Collections.Generic.List[object]]::new()
        foreach ($knowledge in $acceptedRows | Where-Object { $_.ChannelId -ceq $row.ChannelId }) {
            $candidate = Get-CorrelationCandidate -Left $row -Right $knowledge
            if ($null -ne $candidate) { [void]$acceptedCandidates.Add($candidate) }
        }
        if ($acceptedCandidates.Count -gt 1) {
            Add-ComparisonFinding -Kind 'AmbiguousAcceptedKnowledgeMatch' -Status 'NeedsReview' -SourceIds @($row.SourceId, 'accepted-knowledge') -ObservationIds @($row.ObservationId, ($acceptedCandidates | ForEach-Object { $_.Right.ObservationId })) -ChannelId $row.ChannelId -Details ([ordered]@{ CandidateKnowledgeIds = @($acceptedCandidates | ForEach-Object { $_.Right.ObservationId } | Sort-Object -Unique); WinnerSelected = $false })
            continue
        }
        if ($acceptedCandidates.Count -eq 0) { continue }
        $knowledge = $acceptedCandidates[0].Right
        $differences = [System.Collections.Generic.List[string]]::new()
        if ((Normalize-ComparisonText $row.Title) -cne (Normalize-ComparisonText $knowledge.Title)) { [void]$differences.Add('Title') }
        if (@($row.Participants).Count -gt 0 -and @($knowledge.Participants).Count -gt 0 -and -not (Test-EqualStringSets -Left $row.Participants -Right $knowledge.Participants)) { [void]$differences.Add('Participants') }
        if ($null -ne $row.StartUtc -and $null -ne $knowledge.StartUtc -and $row.StartUtc -ne $knowledge.StartUtc) { [void]$differences.Add('StartUtc') }
        if ($null -ne $row.StopUtc -and $null -ne $knowledge.StopUtc -and $row.StopUtc -ne $knowledge.StopUtc) { [void]$differences.Add('StopUtc') }
        $kind = if ($differences.Count -gt 0) { 'AcceptedKnowledgeConflict' } else { 'AcceptedKnowledgeAgreement' }
        $status = if ($differences.Count -gt 0) { 'Contradiction' } else { 'Informational' }
        Add-ComparisonFinding -Kind $kind -Status $status -SourceIds @($row.SourceId, 'accepted-knowledge') -ObservationIds @($row.ObservationId, $knowledge.ObservationId) -ChannelId $row.ChannelId -Details ([ordered]@{ Differences = @($differences | Sort-Object -Unique); AcceptedKnowledgeReadOnly = $true; AcceptedKnowledgeChanged = $false })
    }

    $orderedFindings = @($findings | Sort-Object FindingId -Unique)
    $orderedCorrelations = @($correlations | Sort-Object CorrelationId)
    $orderedFreshness = @($freshnessRows | Sort-Object SourceId, ObservationId)
    $orderedProvenance = @($provenanceRows | Sort-Object SourceId, ObservationId)
    $orderedUnbound = @($unboundRows | Sort-Object SourceId, ObservationId)
    $orderedCoverage = @($coverageRows | Sort-Object SourceId, StartUtc, StopUtc)
    $report = [ordered]@{
        ContractVersion = 'guide-intelligence/comparison/v2'
        EvidenceContractVersion = $contractVersion
        PlaylistId = $PlaylistId
        EvaluationTimeUtc = $evaluation.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        FreshnessTtl = $FreshnessTtl.ToString('c', [Globalization.CultureInfo]::InvariantCulture)
        NearTimeWindow = $NearTimeWindow.ToString('c', [Globalization.CultureInfo]::InvariantCulture)
        ObservationCount = $provenanceRows.Count
        AppliedObservationCount = $observedRows.Count
        UnboundObservationCount = $unboundRows.Count
        Summary = [ordered]@{
            FindingCount = $orderedFindings.Count
            CorrelationCount = $orderedCorrelations.Count
            ContradictionCount = @($orderedFindings | Where-Object Status -eq 'Contradiction').Count
            ReviewRequiredCount = @($orderedFindings | Where-Object ReviewRequired).Count
            StaleObservationCount = @($orderedFreshness | Where-Object FreshnessState -eq 'Stale').Count
            CoverageGapCount = @($orderedCoverage).Count
        }
        Correlations = $orderedCorrelations
        FreshnessAssessments = $orderedFreshness
        CoverageGaps = $orderedCoverage
        UnboundEvidence = $orderedUnbound
        Provenance = $orderedProvenance
        Findings = $orderedFindings
        ReportOnly = 'REPORT_ONLY'
        ReadOnly = $true
        CanPublish = $false
        AcceptedStateMutation = 'None'
        AcceptedKnowledgeMutation = 'None'
    }
    $json = ConvertTo-ChannelForgeCanonicalJson -InputObject $report
    $markdown = @(
        '# ChannelForge guide comparison',
        '',
        ('**Playlist:** {0}' -f $PlaylistId),
        ('**Evaluation time (UTC):** {0}' -f $report.EvaluationTimeUtc),
        ('**Observations:** {0}' -f $report.ObservationCount),
        ('**Correlations:** {0}' -f $report.Summary.CorrelationCount),
        ('**Findings:** {0}' -f $report.Summary.FindingCount),
        '',
        '## Findings',
        ''
    ) + @($orderedFindings | ForEach-Object { '- **{0}** ({1}) — {2}' -f $_.Kind, $_.Status, (ConvertTo-ChannelForgeCanonicalJson -InputObject $_.Details) })
    $report['Json'] = $json
    $report['Markdown'] = [string]::Join("`n", $markdown)
    return [pscustomobject]$report
}
