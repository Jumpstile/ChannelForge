function ConvertTo-ChannelForgeExternalEvidenceObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$InputObject)

    $contract = 'ChannelForgeExternalEvidenceObservation/v1'
    $statusValues = @('Observed','SourceUnavailable','Rejected')
    $kindValues = @('ScheduleEvent','ChannelSchedule','ProgrammeMetadata','EventStatus','Availability','Other')
    $entityValues = @('Programme','Event','Channel','Source','Other')
    $classValues = @('OfficialBroadcaster','OfficialOrganizer','ProviderXMLTV','ConfiguredTrustedXMLTV','TrustedSecondarySchedule','AEDDerived','Heuristic','Other')
    $relationshipValues = @('Authoritative','Independent','Mirror','Unknown')
    $fieldValues = @('Title','Subtitle','Description','Category','ScheduledStartUtc','UpdatedStartUtc','StopUtc','EventStatus','Participant','Competition','Venue','Network','ChannelAssignment')
    $required = @('ObservationStatus','ObservationKind','EntityType','AdapterId','AdapterVersion','ParserVersion','SourceId','SourceFamily','EvidenceClass','SourceRelationship','FieldObservations','ReasonCodes','RedactedFields')
    foreach ($name in $required) { if (-not $InputObject.Contains($name)) { throw "External evidence observation is missing '$name'." } }
    function Text([object]$value, [string]$name, [bool]$nullable = $false) {
        if ($null -eq $value) { if ($nullable) { return $null }; throw "External evidence $name cannot be null." }
        $text = ([string]$value).Trim()
        if (-not $nullable -and [string]::IsNullOrWhiteSpace($text)) { throw "External evidence $name cannot be empty." }
        return $text
    }
    function Instant([object]$value, [string]$name) {
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $null }
        $parsed = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse([string]$value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) { throw "External evidence $name must be an ISO-8601 instant." }
        return $parsed.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    }
    function SortedStrings([object]$values, [string]$name) {
        $result = @($values | ForEach-Object { Text $_ $name } | Sort-Object -Unique)
        return $result
    }
    $status = Text $InputObject.ObservationStatus 'ObservationStatus'
    $kind = Text $InputObject.ObservationKind 'ObservationKind'
    $entity = Text $InputObject.EntityType 'EntityType'
    if ($status -notin $statusValues -or $kind -notin $kindValues -or $entity -notin $entityValues) { throw 'External evidence observation contains an unsupported vocabulary value.' }
    $adapter = Text $InputObject.AdapterId 'AdapterId'; $source = Text $InputObject.SourceId 'SourceId'; $family = Text $InputObject.SourceFamily 'SourceFamily'
    foreach ($value in @($adapter,$source,$family)) { if ($value -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') { throw 'External evidence identifiers must be safe logical identifiers.' } }
    $class = Text $InputObject.EvidenceClass 'EvidenceClass'; $relationship = Text $InputObject.SourceRelationship 'SourceRelationship'
    if ($class -notin $classValues -or $relationship -notin $relationshipValues) { throw 'External evidence class or relationship is invalid.' }
    $bindingInput = if ($InputObject.Contains('BindingContext')) { $InputObject.BindingContext } else { $null }
    $binding = $null
    if ($null -ne $bindingInput) {
        if ($bindingInput -isnot [System.Collections.IDictionary]) { throw 'BindingContext must be an object or null.' }
        $binding = [ordered]@{ PlaylistId=Text $bindingInput.PlaylistId 'BindingContext.PlaylistId' $true; ChannelReference=Text $bindingInput.ChannelReference 'BindingContext.ChannelReference' $true; StationReference=Text $bindingInput.StationReference 'BindingContext.StationReference' $true; BindingKind=Text $bindingInput.BindingKind 'BindingContext.BindingKind' $true }
        if ($binding.BindingKind -notin @($null,'SourceScoped','Shared','Unbound')) { throw 'BindingContext.BindingKind is invalid.' }
    }
    $fields = [System.Collections.Generic.List[object]]::new()
    foreach ($field in @($InputObject.FieldObservations)) {
        if ($field -isnot [System.Collections.IDictionary]) { throw 'FieldObservations entries must be objects.' }
        foreach ($name in @('FieldName','ValueType','NormalizedValue','ReasonCodes','Redacted')) { if (-not $field.Contains($name)) { throw "FieldObservation is missing '$name'." } }
        $fieldName = Text $field.FieldName 'FieldObservation.FieldName'; if ($fieldName -notin $fieldValues) { throw "Unsupported FieldObservation field '$fieldName'." }
        $valueType = Text $field.ValueType 'FieldObservation.ValueType'; if ($valueType -notin @('String','StringArray','Instant','Object')) { throw 'FieldObservation.ValueType is invalid.' }
        $value = $field.NormalizedValue
        if ($valueType -eq 'String' -and $null -ne $value) { $value = Text $value 'FieldObservation.NormalizedValue' }
        if ($valueType -eq 'StringArray') { $value = @(SortedStrings $value 'FieldObservation.NormalizedValue') }
        if ($valueType -eq 'Instant' -and $null -ne $value) { $value = Instant $value 'FieldObservation.NormalizedValue' }
        $original = if ($field.Contains('OriginalValueOrFingerprint')) { Text $field.OriginalValueOrFingerprint 'FieldObservation.OriginalValueOrFingerprint' $true } else { $null }
        $reasons = @(SortedStrings $field.ReasonCodes 'FieldObservation.ReasonCodes')
        [void]$fields.Add([ordered]@{ FieldName=$fieldName; ValueType=$valueType; NormalizedValue=$value; OriginalValueOrFingerprint=$original; SourceDataTimeUtc=Instant $field.SourceDataTimeUtc 'FieldObservation.SourceDataTimeUtc'; ObservationTimeUtc=Instant $field.ObservationTimeUtc 'FieldObservation.ObservationTimeUtc'; ReasonCodes=$reasons; Redacted=[bool]$field.Redacted })
    }
    $fields = @($fields | Sort-Object FieldName, ValueType, OriginalValueOrFingerprint)
    $reasons = @(SortedStrings $InputObject.ReasonCodes 'ReasonCodes'); $redacted = @(SortedStrings $InputObject.RedactedFields 'RedactedFields')
    $projection = [ordered]@{ ContractVersion=$contract; ObservationId=''; ObservationStatus=$status; ObservationKind=$kind; EntityType=$entity; AdapterId=$adapter; AdapterVersion=(Text $InputObject.AdapterVersion 'AdapterVersion'); ParserVersion=(Text $InputObject.ParserVersion 'ParserVersion'); SourceId=$source; SourceFamily=$family; EvidenceClass=$class; SourceRelationship=$relationship; SourceRecordReference=(Text $InputObject.SourceRecordReference 'SourceRecordReference' $true); ProvisionalSubjectKey=(Text $InputObject.ProvisionalSubjectKey 'ProvisionalSubjectKey' $true); SourceChannelReference=(Text $InputObject.SourceChannelReference 'SourceChannelReference' $true); BindingContext=$binding; FieldObservations=$fields; SourceDataTimeUtc=(Instant $InputObject.SourceDataTimeUtc 'SourceDataTimeUtc'); ObservationTimeUtc=(Instant $InputObject.ObservationTimeUtc 'ObservationTimeUtc'); FetchTimeUtc=(Instant $InputObject.FetchTimeUtc 'FetchTimeUtc'); InputArtifactFingerprint=(Text $InputObject.InputArtifactFingerprint 'InputArtifactFingerprint' $true); ReasonCodes=$reasons; RedactedFields=$redacted; ReadOnly=$true }
    $identity = [ordered]@{}; foreach ($entry in $projection.GetEnumerator()) { if ($entry.Key -notin @('ObservationId','FetchTimeUtc','ObservationTimeUtc')) { $identity[$entry.Key] = $entry.Value } }
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $identity)); $sha = [Security.Cryptography.SHA256]::Create(); try { $projection.ObservationId = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    return [pscustomobject]$projection
}
