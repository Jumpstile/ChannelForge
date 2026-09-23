BeforeAll {
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $schema = Join-Path $repo 'schemas\external_evidence_observation.schema.json'
    Import-Module (Join-Path $repo 'src\ChannelForge\ChannelForge.psd1') -Force
    function New-ObservationInput {
        param([string]$FetchTime = '2026-01-01T12:00:00Z', [string]$SourceData = '2026-01-01T11:00:00Z')
        [ordered]@{
            ObservationStatus='Observed'; ObservationKind='ScheduleEvent'; EntityType='Event'; AdapterId='fixture.adapter'; AdapterVersion='1.0.0'; ParserVersion='parser-1'; SourceId='fixture-source'; SourceFamily='fixture-family'; EvidenceClass='OfficialOrganizer'; SourceRelationship='Authoritative'; SourceRecordReference='event-1'; ProvisionalSubjectKey='source:event-1'; SourceChannelReference='network-1'; BindingContext=[ordered]@{PlaylistId='playlist-1';ChannelReference='channel-1';StationReference=$null;BindingKind='SourceScoped'}; FieldObservations=@([ordered]@{FieldName='Title';ValueType='String';NormalizedValue='Example Event';OriginalValueOrFingerprint='Example Event';SourceDataTimeUtc=$SourceData;ObservationTimeUtc='2026-01-01T12:00:00Z';ReasonCodes=@();Redacted=$false},[ordered]@{FieldName='ScheduledStartUtc';ValueType='Instant';NormalizedValue='2026-01-01T20:00:00Z';OriginalValueOrFingerprint='2026-01-01 20:00 UTC';SourceDataTimeUtc=$SourceData;ObservationTimeUtc='2026-01-01T12:00:00Z';ReasonCodes=@();Redacted=$false}); SourceDataTimeUtc=$SourceData; ObservationTimeUtc='2026-01-01T12:00:00Z'; FetchTimeUtc=$FetchTime; InputArtifactFingerprint=('a'*64); ReasonCodes=@('Observed'); RedactedFields=@()
        }
    }
}
Describe 'ChannelForgeExternalEvidenceObservation/v1' {
    It 'parses the schema and accepts a canonical observation projection' {
        { Get-Content $schema -Raw | ConvertFrom-Json } | Should -Not -Throw
        { ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject (New-ObservationInput) } | Should -Not -Throw
    }
    It 'produces deterministic identity and canonical ordering' {
        $one=ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject (New-ObservationInput -FetchTime '2026-01-01T12:00:00Z')
        $two=ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject (New-ObservationInput -FetchTime '2026-01-01T13:00:00Z')
        $one.ObservationId | Should -Be $two.ObservationId; $one.ReadOnly | Should -BeTrue; $one.ContractVersion | Should -Be 'ChannelForgeExternalEvidenceObservation/v1'; @($one.FieldObservations | ForEach-Object FieldName) | Should -Be @('ScheduledStartUtc','Title')
    }
    It 'keeps source-data, observation, and fetch timestamps distinct' {
        $o=ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject (New-ObservationInput)
        $o.SourceDataTimeUtc | Should -Be '2026-01-01T11:00:00Z'; $o.ObservationTimeUtc | Should -Be '2026-01-01T12:00:00Z'; $o.FetchTimeUtc | Should -Be '2026-01-01T12:00:00Z'
    }
    It 'rejects unsupported fields and does not expose policy fields' {
        $sample=New-ObservationInput; $sample.FieldObservations=@($sample.FieldObservations)+@([ordered]@{FieldName='Odds';ValueType='String';NormalizedValue='1';OriginalValueOrFingerprint=$null;SourceDataTimeUtc=$null;ObservationTimeUtc=$null;ReasonCodes=@();Redacted=$false}); { ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject $sample } | Should -Throw '*Unsupported*'
        $o=ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject (New-ObservationInput); @($o.PSObject.Properties.Name) | Should -Not -Contain 'ConfidenceScore'; @($o.PSObject.Properties.Name) | Should -Not -Contain 'CanPublish'; @($o.PSObject.Properties.Name) | Should -Not -Contain 'RequiresReview'
    }
    It 'keeps provisional and binding references non-canonical' {
        $o=ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject (New-ObservationInput); $o.ProvisionalSubjectKey | Should -Be 'source:event-1'; $o.BindingContext.PlaylistId | Should -Be 'playlist-1'; $o.BindingContext.BindingKind | Should -Be 'SourceScoped'; @($o.PSObject.Properties.Name) | Should -Not -Contain 'CanonicalEventId'; @($o.PSObject.Properties.Name) | Should -Not -Contain 'CanonicalChannelId'
    }
    It 'makes redaction explicit and rejects unsafe source references' {
        $sample=New-ObservationInput; $sample.RedactedFields=@('PrivatePath'); $sample.FieldObservations[0].Redacted=$true; $sample.FieldObservations[0].OriginalValueOrFingerprint=$null; $o=ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject $sample; $o.RedactedFields | Should -Contain 'PrivatePath'; $o.FieldObservations[0].Redacted | Should -BeFalse
        $bad=New-ObservationInput; $bad.SourceRecordReference='https://user:token@example.invalid/x'; { ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject $bad } | Should -Throw
    }
    It 'supports generic sports and non-sports observations without sports-only fields' {
        $sports=New-ObservationInput; $sports.FieldObservations=@([ordered]@{FieldName='Participant';ValueType='String';NormalizedValue='Home';OriginalValueOrFingerprint='Home';SourceDataTimeUtc=$null;ObservationTimeUtc=$null;ReasonCodes=@();Redacted=$false}); (ConvertTo-ChannelForgeExternalEvidenceObservation $sports).ObservationKind | Should -Be 'ScheduleEvent'
        $generic=New-ObservationInput; $generic.FieldObservations=@([ordered]@{FieldName='Category';ValueType='String';NormalizedValue='Drama';OriginalValueOrFingerprint='Drama';SourceDataTimeUtc=$null;ObservationTimeUtc=$null;ReasonCodes=@();Redacted=$false}); (ConvertTo-ChannelForgeExternalEvidenceObservation $generic).FieldObservations[0].FieldName | Should -Be 'Category'
    }
    It 'preserves absent source-data time as null' {
        $sample=New-ObservationInput -SourceData $null; $o=ConvertTo-ChannelForgeExternalEvidenceObservation $sample; $o.SourceDataTimeUtc | Should -BeNullOrEmpty
    }
    It 'represents unavailable and rejected observations without policy disposition' {
        foreach($status in @('SourceUnavailable','Rejected')) { $sample=New-ObservationInput; $sample.ObservationStatus=$status; $o=ConvertTo-ChannelForgeExternalEvidenceObservation $sample; $o.ObservationStatus | Should -Be $status; @($o.PSObject.Properties.Name) | Should -Not -Contain 'RequiresReview' }
    }
    It 'keeps source relationship and evidence class distinct' {
        $sample=New-ObservationInput; $sample.SourceRelationship='Independent'; $sample.EvidenceClass='ProviderXMLTV'; $o=ConvertTo-ChannelForgeExternalEvidenceObservation $sample; $o.SourceRelationship | Should -Be 'Independent'; $o.EvidenceClass | Should -Be 'ProviderXMLTV'
    }
    It 'rejects malformed timestamps, missing fields, and invalid binding vocabulary' {
        $sample=New-ObservationInput; $sample.FetchTimeUtc='not-a-time'; { ConvertTo-ChannelForgeExternalEvidenceObservation $sample } | Should -Throw
        $sample=New-ObservationInput; $sample.Remove('SourceId'); { ConvertTo-ChannelForgeExternalEvidenceObservation $sample } | Should -Throw
        $sample=New-ObservationInput; $sample.BindingContext.BindingKind='Guess'; { ConvertTo-ChannelForgeExternalEvidenceObservation $sample } | Should -Throw
    }
    It 'keeps duplicate identical observations deterministic' {
        $a=ConvertTo-ChannelForgeExternalEvidenceObservation (New-ObservationInput); $b=ConvertTo-ChannelForgeExternalEvidenceObservation (New-ObservationInput); $a.ObservationId | Should -Be $b.ObservationId
    }
    It 'serializes the same projection identically' {
        $a=ConvertTo-ChannelForgeExternalEvidenceObservation (New-ObservationInput); $b=ConvertTo-ChannelForgeExternalEvidenceObservation (New-ObservationInput); ($a|ConvertTo-Json -Depth 10 -Compress) | Should -Be ($b|ConvertTo-Json -Depth 10 -Compress)
    }
    It 'rejects field-level attempts to override inherited provenance' {
        $sample=New-ObservationInput; $sample.FieldObservations=@([ordered]@{FieldName='Title';ValueType='String';NormalizedValue='x';SourceId='other';AdapterId='other';EvidenceClass='Heuristic';SourceRelationship='Mirror';OriginalValueOrFingerprint='x';SourceDataTimeUtc=$null;ObservationTimeUtc=$null;ReasonCodes=@();Redacted=$false}); { ConvertTo-ChannelForgeExternalEvidenceObservation $sample } | Should -Throw
    }
    It 'keeps identity stable when semantic arrays and reason arrays are reordered' {
        $a=New-ObservationInput; $a.ReasonCodes=@('Z','A'); $a.RedactedFields=@('Z','A'); $a.FieldObservations[0].ReasonCodes=@('Z','A'); $b=New-ObservationInput; $b.ReasonCodes=@('A','Z'); $b.RedactedFields=@('A','Z'); $b.FieldObservations[0].ReasonCodes=@('A','Z'); (ConvertTo-ChannelForgeExternalEvidenceObservation $a).ObservationId | Should -Be (ConvertTo-ChannelForgeExternalEvidenceObservation $b).ObservationId
    }
    It 'changes identity for semantic values and source record references' {
        $a=New-ObservationInput; $b=New-ObservationInput; $b.FieldObservations[0].NormalizedValue='Changed'; $c=New-ObservationInput; $c.SourceRecordReference='event-2'; (ConvertTo-ChannelForgeExternalEvidenceObservation $a).ObservationId | Should -Not -Be (ConvertTo-ChannelForgeExternalEvidenceObservation $b).ObservationId; (ConvertTo-ChannelForgeExternalEvidenceObservation $a).ObservationId | Should -Not -Be (ConvertTo-ChannelForgeExternalEvidenceObservation $c).ObservationId
    }
    It 'does not include sensitive identity material' {
        $sample=New-ObservationInput; $sample.InputArtifactFingerprint=('b'*64); $sample.FetchTimeUtc='2026-01-01T13:00:00Z'; $o=ConvertTo-ChannelForgeExternalEvidenceObservation $sample; $o.ObservationId | Should -Not -Match 'token|private|cache'; $o.ObservationId.Length | Should -Be 64
    }
    It 'rejects unknown top-level and field properties through runtime parity rules' {
        $sample=New-ObservationInput; $sample.Unknown='x'; { ConvertTo-ChannelForgeExternalEvidenceObservation $sample } | Should -Throw
        $sample=New-ObservationInput; $sample.FieldObservations=@([ordered]@{FieldName='Title';ValueType='String';NormalizedValue='x';Unknown='x';OriginalValueOrFingerprint='x';SourceDataTimeUtc=$null;ObservationTimeUtc=$null;ReasonCodes=@();Redacted=$false}); { ConvertTo-ChannelForgeExternalEvidenceObservation $sample } | Should -Throw
    }
}
