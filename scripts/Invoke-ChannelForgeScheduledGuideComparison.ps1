[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$EpgConfigPath,
    [Parameter(Mandatory)][string]$CacheRoot,
    [Parameter(Mandatory)][string]$SourceResultPath,
    [Parameter(Mandatory)][string]$PlaylistId,
    [Parameter(Mandatory)][datetimeoffset]$EvaluationTimeUtc
)
$ErrorActionPreference = 'Stop'
function Get-ScheduledComparisonSourceId([string]$Kind,[string]$Name) {
    $module = Get-Module ChannelForge | Select-Object -First 1
    if ($null -eq $module) { throw 'ComparisonModuleUnavailable' }
    return & $module {
        param($sourceKind, $sourceName)
        $json = ConvertTo-ChannelForgeCanonicalJson -InputObject ([ordered]@{ Kind = $sourceKind; Name = $sourceName })
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        'source-' + ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant().Substring(0,16)
    } $Kind $Name
}
function ConvertTo-ScheduledSafeText([string]$Value,[int]$MaximumLength) {
    $module = Get-Module ChannelForge | Select-Object -First 1
    if ($null -eq $module) { throw 'ComparisonModuleUnavailable' }
    return & $module {
        param($text,$maximum)
        ConvertTo-ChannelForgeGuideSafeText -Value $text -MaximumLength $maximum
    } $Value $MaximumLength
}

function Read-ScheduledRemoteXmltvCache([string]$CacheRoot,[string]$SourceId,[string]$Url,[datetimeoffset]$EvaluationTimeUtc) {
    $module = Get-Module ChannelForge | Select-Object -First 1
    if ($null -eq $module) { throw 'ComparisonModuleUnavailable' }
    return & $module {
        param($root, $sourceId, $url, $evaluation)
        Read-ChannelForgeRemoteXmltvFetchCache -CacheRoot $root -SourceId $sourceId -Url $url -EvaluationTimeUtc $evaluation
    } $CacheRoot $SourceId $Url $EvaluationTimeUtc
}
function Test-ScheduledAliasContextMatch([string]$ContextKey,[object[]]$Sides) {
    $module = Get-Module ChannelForge | Select-Object -First 1
    if ($null -eq $module) { throw 'ComparisonModuleUnavailable' }
    return & $module {
        param($expectedContextKey,$aliasSides)
        $projection = Get-ChannelForgeKnowledgeAliasContextProjection -Sides $aliasSides
        [string]::Equals((Get-ChannelForgeDomainHash -Domain 'contextual-programme-alias-context/v1' -InputObject $projection),$expectedContextKey,[StringComparison]::Ordinal)
    } $ContextKey $Sides
}

function Get-ActiveAt($Entry,[datetimeoffset]$At) {
    if ($Entry.EffectiveFromUtc -and $At -lt [datetimeoffset]$Entry.EffectiveFromUtc) { return $false }
    if ($Entry.EffectiveToUtc -and $At -ge [datetimeoffset]$Entry.EffectiveToUtc) { return $false }
    return $true
}
function Test-OrdinalEqual([string]$Left,[string]$Right) {
    [string]::Equals($Left, $Right, [StringComparison]::Ordinal)
}

function ConvertFrom-ScheduledXmltvTimestamp([string]$Value) {
    $raw = $Value.Trim()
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $styles = [Globalization.DateTimeStyles]::AllowWhiteSpaces
    if ($raw -match '^(?<stamp>\d{14})\s*(?<offset>[+-]\d{4})$') {
        $normalized = "{0} {1}:{2}" -f $Matches.stamp, $Matches.offset.Substring(0, 3), $Matches.offset.Substring(3, 2)
        return [datetimeoffset]::ParseExact($normalized, 'yyyyMMddHHmmss zzz', $culture, $styles)
    }
    if ($raw -match '^\d{14}$') {
        return [datetimeoffset]::ParseExact($raw, 'yyyyMMddHHmmss', $culture, ($styles -bor [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal))
    }
    return [datetimeoffset]::Parse($raw, $culture, $styles)
}

function ConvertTo-ScheduledDisplayTime([string]$RawValue) {
    $instant = ConvertFrom-ScheduledXmltvTimestamp -Value $RawValue
    if ($RawValue.Trim() -match '(?i)(?:Z|[+-]\d{4}|[+-]\d{2}:\d{2})$') {
        if ($RawValue.Trim() -match '(?i)Z$') { return $instant.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) }
        return $instant.ToString("yyyy-MM-dd'T'HH:mm:sszzz", [Globalization.CultureInfo]::InvariantCulture)
    }
    return $instant.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
}

function Get-ScheduledProgrammeDisplayTimes($Programme) {
    if ($null -eq $Programme.Evidence -or $null -eq $Programme.Evidence.PSObject.Properties['RawProgrammeOccurrences']) { return $null }
    $rawChannel = [string]$Programme.RawChannelId
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($occurrence in @($Programme.Evidence.RawProgrammeOccurrences)) {
        if (-not (Test-OrdinalEqual ([string]$occurrence.RawProgrammeChannelId) $rawChannel)) { continue }
        if (@($occurrence.TitleNodes | Where-Object { Test-OrdinalEqual ([string]$_) ([string]$Programme.Title) }).Count -ne 1) { continue }
        try {
            $start = ConvertFrom-ScheduledXmltvTimestamp -Value ([string]$occurrence.StartRaw)
            $stop = ConvertFrom-ScheduledXmltvTimestamp -Value ([string]$occurrence.StopRaw)
            if ($start.ToUniversalTime() -ne ([datetimeoffset]$Programme.Start).ToUniversalTime() -or
                $stop.ToUniversalTime() -ne ([datetimeoffset]$Programme.End).ToUniversalTime()) { continue }
            [void]$candidates.Add([pscustomobject]@{
                Start = ConvertTo-ScheduledDisplayTime -RawValue ([string]$occurrence.StartRaw)
                Stop = ConvertTo-ScheduledDisplayTime -RawValue ([string]$occurrence.StopRaw)
            })
        }
        catch { continue }
    }
    $distinct = @($candidates.ToArray() | Sort-Object Start, Stop -Unique)
    if ($distinct.Count -ne 1) { return $null }
    return $distinct[0]
}

function New-ScheduledObservation($Programme,[string]$SourceId,[string]$RawReference,[string]$ChannelId,[string]$Playlist,[string]$Fingerprint,[AllowNull()][string]$FetchAt,[datetimeoffset]$ObservedAt,[Parameter(Mandatory)]$DisplayTimes) {
    $fields = [System.Collections.Generic.List[object]]::new()
    $addString = { param($name,$value) if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $fields.Add([ordered]@{ FieldName=$name; ValueType='String'; NormalizedValue=[string]$value; OriginalValueOrFingerprint=[string]$value; SourceDataTimeUtc=$null; ObservationTimeUtc=$null; ReasonCodes=@(); Redacted=$false }) } }
    & $addString 'Title' $Programme.Title
    & $addString 'Subtitle' $Programme.Subtitle
    & $addString 'Description' $Programme.Description
    if (@($Programme.Categories).Count -gt 0) { $fields.Add([ordered]@{ FieldName='Category'; ValueType='StringArray'; NormalizedValue=@($Programme.Categories); OriginalValueOrFingerprint=$null; SourceDataTimeUtc=$null; ObservationTimeUtc=$null; ReasonCodes=@(); Redacted=$false }) }
    foreach ($timeField in @('ScheduledStartUtc','StopUtc')) {
        $value = if ($timeField -eq 'ScheduledStartUtc') { $Programme.Start } else { $Programme.End }
        $display = if ($timeField -eq 'ScheduledStartUtc') { [string]$DisplayTimes.Start } else { [string]$DisplayTimes.Stop }
        $instant = ([datetimeoffset]$value).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'",[Globalization.CultureInfo]::InvariantCulture)
        $fields.Add([ordered]@{ FieldName=$timeField; ValueType='Instant'; NormalizedValue=$instant; OriginalValueOrFingerprint=$display; SourceDataTimeUtc=$null; ObservationTimeUtc=$null; ReasonCodes=@(); Redacted=$false })
    }
    $fields.Add([ordered]@{ FieldName='EventStatus'; ValueType='String'; NormalizedValue=$(if ($Programme.IsLive) { 'Live' } else { $null }); OriginalValueOrFingerprint=$(if ($Programme.IsLive) { 'Live' } else { $null }); SourceDataTimeUtc=$null; ObservationTimeUtc=$null; ReasonCodes=@(); Redacted=$false })
    $input = [ordered]@{ ObservationStatus='Observed'; ObservationKind='ScheduleEvent'; EntityType='Programme'; AdapterId='channelforge-xmltv'; AdapterVersion='1'; ParserVersion='xmltv/v1'; SourceId=$SourceId; SourceFamily='XMLTV'; EvidenceClass='ConfiguredTrustedXMLTV'; SourceRelationship='Unknown'; SourceRecordReference=$null; ProvisionalSubjectKey=$null; SourceChannelReference=$RawReference; BindingContext=[ordered]@{ PlaylistId=$Playlist; ChannelReference=$RawReference; StationReference=$null; BindingKind='SourceScoped' }; FieldObservations=@($fields.ToArray()); SourceDataTimeUtc=$null; ObservationTimeUtc=$ObservedAt.ToUniversalTime().ToString('o'); FetchTimeUtc=$FetchAt; InputArtifactFingerprint=$Fingerprint; ReasonCodes=@(); RedactedFields=@() }
    ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject $input
}
    $comparison = [ordered]@{ SchemaVersion='scheduled-guide-comparison/v1'; Status='FAILED'; PlaylistId=$PlaylistId; EvaluationTimeUtc=$EvaluationTimeUtc.ToUniversalTime().ToString('o'); SourceResultDigest=$null; KnowledgeStateRevision=$null; SourceAssessments=@(); ObservationCount=0; UnresolvedReferenceCount=0; UnresolvedReasonCounts=@(); UnresolvedReferences=@(); Comparer=$null; KnowledgeChangePlan=$null; FailureCode='ComparisonFailed' }
$jsonPath = Join-Path $OutputRoot 'scheduled-guide-comparison.json'
$mdPath = Join-Path $OutputRoot 'scheduled-guide-comparison.md'
try {
    $comparison.SourceResultDigest = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($SourceResultPath)))).ToLowerInvariant()
    $sourceSchemaPath = Join-Path $Root 'schemas/source-refresh-result.schema.json'
    if (-not (Test-Json -Path $SourceResultPath -SchemaFile $sourceSchemaPath -ErrorAction Stop)) { throw 'SourceResultSchemaInvalid' }
    $sourceResult = Get-Content -LiteralPath $SourceResultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (([datetimeoffset]$sourceResult.EvaluationTimeUtc).ToUniversalTime() -ne $EvaluationTimeUtc.ToUniversalTime()) { throw 'SourceResultEvaluationMismatch' }
    $programmeCount = 0
    $config = @(Read-ChannelForgeEpgSource -Path $EpgConfigPath)
    $state = Get-ChannelForgeKnowledgeState -RepositoryRoot $Root
    $comparison.KnowledgeStateRevision = [int]$state.Revision
    $at = $EvaluationTimeUtc.ToUniversalTime()
    $activeIdentities = @($state.Entries | Where-Object { $_.Kind -eq 'ChannelIdentity' -and $_.ApprovalStatus -eq 'Approved' -and (Get-ActiveAt $_ $at) })
    $bindings = @($state.Entries | Where-Object { $_.Kind -eq 'ChannelBinding' -and $_.ApprovalStatus -eq 'Approved' -and (Test-OrdinalEqual ([string]$_.PlaylistId) $PlaylistId) -and (Get-ActiveAt $_ $at) })
    $aliases = @($state.Entries | Where-Object { $_.Kind -eq 'ProgrammeAlias' })
    $observations = [System.Collections.Generic.List[object]]::new()
    $unresolved = [System.Collections.Generic.List[object]]::new()
    $assessments = [System.Collections.Generic.List[object]]::new()
    foreach ($source in @($config | Sort-Object Name)) {
        $kind = [string]$source.SourceKind
        $name = ([string]$source.Name).Trim()
        $mappedId = Get-ScheduledComparisonSourceId -Kind $kind -Name $name
        $safeName = ConvertTo-ScheduledSafeText -Value $name -MaximumLength 256
        if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = $mappedId }
        $assessment = [ordered]@{ Name=$safeName; Kind=$kind; SourceId=$mappedId; GateStatus='Excluded'; ReasonCode='SourceResultMissing' }
        $configCount = @($config | Where-Object { (Test-OrdinalEqual ([string]$_.Name).Trim() $name) -and (Test-OrdinalEqual ([string]$_.SourceKind) $kind) }).Count
        if ($configCount -ne 1) { $assessment.ReasonCode='AmbiguousConfiguredSource'; $assessments.Add([pscustomobject]$assessment); continue }
        $row = @($sourceResult.Sources | Where-Object { (Test-OrdinalEqual ([string]$_.Name) $name) -and (Test-OrdinalEqual ([string]$_.Kind) $kind) })
        if (-not $source.Enabled) { $assessment.ReasonCode='Disabled'; $assessments.Add([pscustomobject]$assessment); continue }
        if ($row.Count -ne 1) { $assessments.Add([pscustomobject]$assessment); continue }
        if ($kind -eq 'remote' -and [string]$row[0].Classification -cne 'AutoHandled') { $assessment.ReasonCode='RemoteSourceNotAutoHandled'; $assessments.Add([pscustomobject]$assessment); continue }
        if ($row[0].Classification -in @('ReviewNeeded','Degraded') -or ($kind -eq 'remote' -and $row[0].Result -in @('REFRESH_FAILED','REVIEW_REQUIRED','NOT_ATTEMPTED'))) { $assessment.ReasonCode='SourceNotSuccessful'; $assessments.Add([pscustomobject]$assessment); continue }
        $fingerprint=$null; $fetchAt=$null; $programmes=@()
        if ($kind -eq 'local') {
            try {
                if (-not [IO.File]::Exists([string]$source.Path)) { $assessment.ReasonCode='LocalSourceUnavailable'; $assessments.Add([pscustomobject]$assessment); continue }
                $importStatus=[ordered]@{}
                $programmes=@(Import-ChannelForgeXmltvSource -Path ([string]$source.Path) -SourceId $mappedId -AcquisitionStatus $importStatus -MaximumProgrammeCount (256 - $programmeCount))
                $fingerprint=[string]$importStatus.InputArtifactHash
                $assessment.GateStatus='Included'; $assessment.ReasonCode='LocalFreshnessUnknown'
            } catch { if ($_.Exception.Message -eq 'ComparisonProgrammeLimitExceeded') { throw }; $assessment.ReasonCode='XmltvParseFailure'; $assessments.Add([pscustomobject]$assessment); continue }
        }
        else {
            try {
                if ($row[0].Result -notin @('REUSED_VALID_CACHE','CONDITIONAL_REFRESHED','FULL_REFRESHED')) { $assessment.ReasonCode='RemoteResultNotAccepted'; $assessments.Add([pscustomobject]$assessment); continue }
                $cache=Read-ScheduledRemoteXmltvCache -CacheRoot $CacheRoot -SourceId $name -Url ([string]$source.Url) -EvaluationTimeUtc $EvaluationTimeUtc
                if (-not $cache.MetadataValid -or -not $cache.PayloadValid -or -not $cache.IsFresh) { $assessment.ReasonCode='FreshCacheUnavailable'; $assessments.Add([pscustomobject]$assessment); continue }
                $fetchAt=([datetimeoffset]$cache.Metadata.FetchedAtUtc).ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
                $fingerprint=[string]$cache.Metadata.PayloadSha256
                $programmes=@(Import-ChannelForgeXmltvSource -Path ([string]$cache.PayloadPath) -SourceId $mappedId -MaximumProgrammeCount (256 - $programmeCount))
                $assessment.GateStatus='Included'; $assessment.ReasonCode='FreshCache'
            } catch { if ($_.Exception.Message -eq 'ComparisonProgrammeLimitExceeded') { throw }; $assessment.ReasonCode='FreshCacheUnavailable'; $assessments.Add([pscustomobject]$assessment); continue }
        }
        $programmeCount += $programmes.Count
        if ($programmeCount -gt 256) { throw 'ComparisonObservationLimitExceeded' }
        $assessments.Add([pscustomobject]$assessment)
        foreach ($programme in $programmes) {
            $raw = if ($null -ne $programme.PSObject.Properties['RawChannelId']) { [string]$programme.RawChannelId } else { [string]$programme.ChannelId }
            $parsed = [string]$programme.ChannelId
            if ([string]::IsNullOrWhiteSpace($raw) -or -not (Test-OrdinalEqual $raw $parsed) -or $raw -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') { $unresolved.Add([pscustomobject]@{ SourceId=$mappedId; RawReference=$null; Reason='UnsafeOrMismatchedReference' }); continue }
            $matches=@($bindings | Where-Object { (Test-OrdinalEqual ([string]$_.SourceId) $mappedId) -and (Test-OrdinalEqual ([string]$_.SourceChannelReference) $raw) })
            if ($matches.Count -ne 1) { $unresolved.Add([pscustomobject]@{ SourceId=$mappedId; RawReference=$raw; Reason=if($matches.Count -gt 1){'AmbiguousBinding'}else{'UnmatchedBinding'} }); continue }
            $identity=@($activeIdentities | Where-Object { Test-OrdinalEqual ([string]$_.ChannelId) ([string]$matches[0].ChannelId) })
            if ($identity.Count -ne 1) { $unresolved.Add([pscustomobject]@{ SourceId=$mappedId; RawReference=$raw; Reason='InactiveOrAmbiguousIdentity' }); continue }
            $displayTimes=Get-ScheduledProgrammeDisplayTimes -Programme $programme
            if ($null -eq $displayTimes) { $unresolved.Add([pscustomobject]@{ SourceId=$mappedId; RawReference=$raw; Reason='ProgrammeTimeEvidenceUnavailable' }); continue }
            $observation=New-ScheduledObservation -Programme $programme -SourceId $mappedId -RawReference $raw -ChannelId ([string]$matches[0].ChannelId) -Playlist $PlaylistId -Fingerprint $fingerprint -FetchAt $fetchAt -ObservedAt $EvaluationTimeUtc -DisplayTimes $displayTimes
            if (-not (Test-OrdinalEqual ([string]$observation.SourceChannelReference) $raw)) { $unresolved.Add([pscustomobject]@{ SourceId=$mappedId; RawReference=$null; Reason='ObservationReferenceMismatch' }); continue }
            $observations.Add($observation)
        }
    }
    $bindingsForComparer = @($bindings | Where-Object { @($activeIdentities | Where-Object ChannelId -CEQ $_.ChannelId).Count -eq 1 } | ForEach-Object { [pscustomobject]@{ PlaylistId=$_.PlaylistId; SourceId=$_.SourceId; SourceChannelReference=$_.SourceChannelReference; ChannelId=$_.ChannelId; ApprovalStatus=$_.ApprovalStatus } })
    $comparison.Comparer = Compare-ChannelForgeXmltvGuides -PlaylistId $PlaylistId -Observations @($observations.ToArray()) -EvaluationTimeUtc $EvaluationTimeUtc -DurableChannelBindings $bindingsForComparer -AcceptedKnowledge @() -ContextualProgrammeAliases $aliases
    $actions=[System.Collections.Generic.List[object]]::new()
    foreach ($proposalGroup in @($comparison.Comparer.ContextualAliasProposals | Group-Object ContextKey)) {
        $proposal = $proposalGroup.Group[0]
        $persistable = $true
        foreach ($proposalItem in @($proposalGroup.Group)) {
            if (-not (Test-ScheduledAliasContextMatch -ContextKey ([string]$proposal.ContextKey) -Sides @($proposalItem.Sides))) { $persistable = $false; break }
            foreach ($evidenceRecord in @($proposalItem.EvidenceRecords)) {
                if (-not (Test-ScheduledAliasContextMatch -ContextKey ([string]$proposal.ContextKey) -Sides @($evidenceRecord.Sides))) { $persistable = $false; break }
            }
            if (-not $persistable) { break }
        }
        if (-not $persistable) { continue }
        $contextMatches=@($aliases | Where-Object ContextKey -CEQ $proposal.ContextKey)
        if ($contextMatches.Count -eq 1) {
            $records=@($proposalGroup.Group | ForEach-Object { $_.EvidenceRecords } | Group-Object { @($_.ObservationIds | Sort-Object) -join '|' } | ForEach-Object { $_.Group[0] })
            $seenRecordKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($existingRecord in @($contextMatches[0].EvidenceRecords)) { [void]$seenRecordKeys.Add(@($existingRecord.ObservationIds | Sort-Object) -join '|') }
            $newRecords = [System.Collections.Generic.List[object]]::new()
            foreach ($record in $records) {
                $pairIds = @($record.ObservationIds | Sort-Object -Unique)
                if ($pairIds.Count -eq 2 -and $seenRecordKeys.Add($pairIds -join '|')) { $newRecords.Add($record) }
            }
            if ($newRecords.Count -gt 0) {
                $newIds=@($newRecords.ToArray() | ForEach-Object { $_.ObservationIds } | Sort-Object -Unique)
                $actions.Add([ordered]@{ Action='AppendAliasEvidence'; EntryId=[string]$contextMatches[0].EntryId; ObservationIds=$newIds; EvidenceRecords=@($newRecords.ToArray()); Reason='Scheduled contextual XMLTV comparison evidence.' })
            }
            continue
        }
        $records = @($proposalGroup.Group | ForEach-Object { $_.EvidenceRecords } | Group-Object { @($_.ObservationIds | Sort-Object -Unique) -join '|' } | ForEach-Object { $_.Group[0] })
        $actions.Add([ordered]@{ Action='ProposeAlias'; Entry=[ordered]@{ Sides=@($proposal.Sides); ConfidenceScore=[int]$proposal.ConfidenceScore; CorrelationBasis=@($proposal.CorrelationBasis); EvidenceRecords=$records }; Reason='Scheduled contextual XMLTV comparison proposal.' })
    }
    if ($actions.Count -gt 0) { $comparison.KnowledgeChangePlan=New-ChannelForgeKnowledgeChangePlan -Actions @($actions.ToArray()) -RepositoryRoot $Root -CreatedAtUtc $EvaluationTimeUtc }
    $comparison.SourceAssessments=@($assessments.ToArray() | Sort-Object Kind,Name)
    $comparison.ObservationCount=$observations.Count
    $comparison.UnresolvedReferenceCount=$unresolved.Count
    $comparison.UnresolvedReasonCounts=@($unresolved | Group-Object Reason | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Reason=[string]$_.Name; Count=[int]$_.Count } })
    $comparison.UnresolvedReferences=@($unresolved.ToArray() | Sort-Object SourceId,RawReference,Reason)
    $comparison.Status='SUCCEEDED'; $comparison.FailureCode='None'
}
catch {
    $comparison.Status='FAILED'; $comparison.FailureCode='ComparisonFailed'; $comparison.Comparer=$null; $comparison.KnowledgeChangePlan=$null
}
[IO.File]::WriteAllText($jsonPath, (($comparison | ConvertTo-Json -Depth 30) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$md=@('# Scheduled guide comparison','','- Status: '+$comparison.Status,'- Playlist: '+$comparison.PlaylistId,'- Source result digest: '+$comparison.SourceResultDigest,'- Knowledge revision: '+$comparison.KnowledgeStateRevision,'- Observations: '+$comparison.ObservationCount,'- Unresolved references: '+$comparison.UnresolvedReferenceCount,'- Failure code: '+$comparison.FailureCode,'','This report is read-only. Any knowledge change plan is proposal/evidence-only and is never applied.')
[IO.File]::WriteAllText($mdPath, (($md -join [Environment]::NewLine) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
