BeforeAll {
    $script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Repo 'src/ChannelForge/ChannelForge.psd1') -Force

    function New-TestObservation {
        param(
            [string]$SourceId,
            [string]$Title = 'Evening News',
            [string]$Subtitle = '',
            [string]$StartUtc = '2026-01-01T12:00:00Z',
            [string]$StopUtc = '2026-01-01T13:00:00Z',
            [string[]]$Participants = @(),
            [string]$ChannelReference = 'station-one',
            [string]$Playlist = 'playlist-one',
            [string]$BindingKind = 'SourceScoped',
            [string]$SourceDataTimeUtc = '2026-01-01T11:30:00Z',
            [string]$FetchTimeUtc = '2026-01-01T11:45:00Z',
            [string]$SourceFamily = 'fixture-guide-family',
            [string]$SourceRecordReference = 'event-one',
            [string]$ProvisionalSubjectKey = '',
            [string]$SourceRelationship = 'Independent',
            [string]$ObservationStatus = 'Observed',
            [string]$Network = '',
            [string]$ChannelAssignment = ''
        )
        $fields = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in @(
            @{ Name = 'Title'; Value = $Title; Type = 'String' },
            @{ Name = 'Subtitle'; Value = $Subtitle; Type = 'String' },
            @{ Name = 'ScheduledStartUtc'; Value = $StartUtc; Type = 'Instant' },
            @{ Name = 'StopUtc'; Value = $StopUtc; Type = 'Instant' },
            @{ Name = 'Participant'; Value = $Participants; Type = 'StringArray' },
            @{ Name = 'Network'; Value = $Network; Type = 'String' },
            @{ Name = 'ChannelAssignment'; Value = $ChannelAssignment; Type = 'String' }
        )) {
            if (($entry.Type -eq 'StringArray' -and @($entry.Value).Count -eq 0) -or
                ($entry.Type -ne 'StringArray' -and [string]::IsNullOrWhiteSpace([string]$entry.Value))) { continue }
            [void]$fields.Add([ordered]@{
                FieldName = $entry.Name
                ValueType = $entry.Type
                NormalizedValue = $entry.Value
                OriginalValueOrFingerprint = if ($entry.Value -is [array]) { [string]::Join('|', $entry.Value) } else { [string]$entry.Value }
                SourceDataTimeUtc = $SourceDataTimeUtc
                ObservationTimeUtc = $FetchTimeUtc
                ReasonCodes = @()
                Redacted = $false
            })
        }
        $binding = [ordered]@{
            PlaylistId = if ($BindingKind -eq 'Unbound') { $null } else { $Playlist }
            ChannelReference = $ChannelReference
            StationReference = $null
            BindingKind = $BindingKind
        }
        $input = [ordered]@{
            ObservationStatus = $ObservationStatus
            ObservationKind = 'ScheduleEvent'
            EntityType = 'Event'
            AdapterId = "fixture.$SourceId"
            AdapterVersion = '1.0.0'
            ParserVersion = 'fixture-1'
            SourceId = $SourceId
            SourceFamily = $SourceFamily
            EvidenceClass = 'ProviderXMLTV'
            SourceRelationship = $SourceRelationship
            SourceRecordReference = $SourceRecordReference
            ProvisionalSubjectKey = $ProvisionalSubjectKey
            SourceChannelReference = $ChannelReference
            BindingContext = $binding
            FieldObservations = @($fields)
            SourceDataTimeUtc = $SourceDataTimeUtc
            ObservationTimeUtc = $FetchTimeUtc
            FetchTimeUtc = $FetchTimeUtc
            InputArtifactFingerprint = $null
            ReasonCodes = @()
            RedactedFields = @()
        }
        ConvertTo-ChannelForgeExternalEvidenceObservation -InputObject $input
    }

    function New-TestBinding {
        param([string]$SourceId = 'guide-a', [string]$Reference = 'station-one', [string]$ChannelId = 'channel-one', [string]$Network = 'North Network')
        [pscustomobject]@{ PlaylistId = 'playlist-one'; SourceId = $SourceId; SourceChannelReference = $Reference; ChannelId = $ChannelId; Network = $Network }
    }

    function New-TestCoverageWindow {
        param([string]$SourceId = 'guide-b', [string]$ChannelId = 'channel-one', [string]$StartUtc = '2026-01-01T12:00:00Z', [string]$StopUtc = '2026-01-01T13:00:00Z')
        [pscustomobject]@{ SourceId = $SourceId; ChannelId = $ChannelId; StartUtc = $StartUtc; StopUtc = $StopUtc }
    }
}

Describe 'XMLTV guide comparison over ChannelForgeExternalEvidenceObservation/v1' {
    BeforeEach {
        $script:EvaluationTime = [datetimeoffset]'2026-01-01T12:00:00Z'
    }

    It 'reports exact agreement for independently sourced matching observations' {
        $observations = @((New-TestObservation -SourceId 'guide-a'), (New-TestObservation -SourceId 'guide-b'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime

        @($report.Findings.Kind) | Should -Contain 'ExactAgreement'
        $report.Correlations.Count | Should -Be 1
        $report.EvidenceContractVersion | Should -Be 'ChannelForgeExternalEvidenceObservation/v1'
    }

    It 'reports harmless subtitle variation without calling it a contradiction' {
        $observations = @((New-TestObservation -SourceId 'guide-a'), (New-TestObservation -SourceId 'guide-b' -Subtitle 'Local studio'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime

        @($report.Findings.Kind) | Should -Contain 'HarmlessMetadataVariation'
        @($report.Findings | Where-Object Kind -eq 'HarmlessMetadataVariation')[0].Status | Should -Be 'Informational'
        @($report.Findings | Where-Object Status -eq 'Contradiction').Count | Should -Be 0
    }

    It 'correlates the event before reporting a start-time shift' {
        $observations = @(
            (New-TestObservation -SourceId 'guide-a'),
            (New-TestObservation -SourceId 'guide-b' -StartUtc '2026-01-01T12:05:00Z')
        )
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime

        @($report.Findings | Where-Object Kind -eq 'TimeConflict').Details.Shift | Should -Contain 'StartTimeShift'
        $report.Correlations.Count | Should -Be 1
        @($report.Findings.Kind) | Should -Not -Contain 'ProgrammeMissing'
    }

    It 'reports a stop-time shift separately from a start-time shift' {
        $observations = @(
            (New-TestObservation -SourceId 'guide-a'),
            (New-TestObservation -SourceId 'guide-b' -StopUtc '2026-01-01T13:10:00Z')
        )
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime

        @($report.Findings | Where-Object Kind -eq 'TimeConflict').Details.Shift | Should -Contain 'StopTimeShift'
        $report.Correlations.Count | Should -Be 1
    }

    It 'identifies a correlated event shifted at both boundaries' {
        $observations = @(
            (New-TestObservation -SourceId 'guide-a'),
            (New-TestObservation -SourceId 'guide-b' -StartUtc '2026-01-01T12:05:00Z' -StopUtc '2026-01-01T13:10:00Z')
        )
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime

        @($report.Findings | Where-Object Kind -eq 'TimeConflict').Details.Shift | Should -Contain 'StartAndStopTimeShift'
    }

    It 'keeps near-time event correlation independent of enumeration order' {
        $first = New-TestObservation -SourceId 'guide-a' -Title 'Cup Final' -Participants @('North', 'South') -StartUtc '2026-01-01T12:00:00Z'
        $second = New-TestObservation -SourceId 'guide-b' -Title 'Cup Final' -Participants @('South', 'North') -StartUtc '2026-01-01T12:12:00Z'
        $left = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($first, $second) -EvaluationTimeUtc $script:EvaluationTime
        $right = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($second, $first) -EvaluationTimeUtc $script:EvaluationTime

        $left.Correlations.Count | Should -Be 1
        $left.Json | Should -Be $right.Json
        @($left.Findings.Kind) | Should -Not -Contain 'ProgrammeMissing'
    }

    It 'reports ambiguous candidate sets without selecting an enumeration winner' {
        $observations = @(
            (New-TestObservation -SourceId 'guide-a' -Title 'News' -StartUtc '2026-01-01T12:00:00Z' -StopUtc '2026-01-01T13:00:00Z'),
            (New-TestObservation -SourceId 'guide-b' -Title 'News' -StartUtc '2026-01-01T12:10:00Z' -StopUtc '2026-01-01T12:50:00Z' -SourceRecordReference 'event-b1'),
            (New-TestObservation -SourceId 'guide-b' -Title 'News' -StartUtc '2026-01-01T12:20:00Z' -StopUtc '2026-01-01T13:10:00Z' -SourceRecordReference 'event-b2')
        )
        $left = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime
        $right = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($observations[2], $observations[0], $observations[1]) -EvaluationTimeUtc $script:EvaluationTime

        @($left.Findings.Kind) | Should -Contain 'AmbiguousCorrelation'
        $left.Correlations.Count | Should -Be 0
        @($left.Findings | Where-Object Kind -eq 'AmbiguousCorrelation').Details.WinnerSelected | Should -Contain $false
        $left.Json | Should -Be $right.Json
    }

    It 'retains unbound evidence and excludes it from playlist assessment' {
        $observations = @(
            (New-TestObservation -SourceId 'guide-a'),
            (New-TestObservation -SourceId 'guide-unbound' -BindingKind 'Unbound' -Playlist '')
        )
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime

        $report.UnboundEvidence.SourceId | Should -Contain 'guide-unbound'
        $report.UnboundObservationCount | Should -Be 1
        $report.AppliedObservationCount | Should -Be 1
        @($report.Findings.Kind) | Should -Contain 'UnboundEvidence'
        $report.Correlations.Count | Should -Be 0
    }

    It 'derives stale and fresh states from source facts and explicit evaluation time' {
        $observations = @(
            (New-TestObservation -SourceId 'guide-stale' -SourceDataTimeUtc '2026-01-01T00:00:00Z' -FetchTimeUtc '2026-01-01T11:55:00Z'),
            (New-TestObservation -SourceId 'guide-fresh' -SourceDataTimeUtc '2026-01-01T11:30:00Z' -FetchTimeUtc '2026-01-01T11:55:00Z')
        )
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime -FreshnessTtl ([timespan]::FromHours(1))

        ($report.FreshnessAssessments | Where-Object SourceId -eq 'guide-stale').FreshnessState | Should -Be 'Stale'
        ($report.FreshnessAssessments | Where-Object SourceId -eq 'guide-fresh').FreshnessState | Should -Be 'Fresh'
        @($report.Findings.Kind) | Should -Contain 'StaleObservation'
        ($report.Provenance | Where-Object SourceId -eq 'guide-stale').FetchTimeUtc | Should -Be '2026-01-01T11:55:00Z'
    }

    It 'classifies benign duplicates and material same-source and cross-source overlaps' {
        $observations = @(
            (New-TestObservation -SourceId 'guide-a' -Title 'News' -SourceRecordReference 'a1'),
            (New-TestObservation -SourceId 'guide-a' -Title 'News' -SourceRecordReference 'a2'),
            (New-TestObservation -SourceId 'guide-a' -Title 'Movie' -StartUtc '2026-01-01T12:30:00Z' -StopUtc '2026-01-01T13:30:00Z' -SourceRecordReference 'a3'),
            (New-TestObservation -SourceId 'guide-b' -Title 'Sports' -StartUtc '2026-01-01T12:20:00Z' -StopUtc '2026-01-01T12:45:00Z' -SourceRecordReference 'b1')
        )
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime

        @($report.Findings.Kind) | Should -Contain 'BenignExactDuplicateOverlap'
        @($report.Findings.Kind) | Should -Contain 'MaterialOverlap'
        @($report.Findings | Where-Object Kind -eq 'BenignExactDuplicateOverlap').Details.OverlapType | Should -Contain 'SameSource'
        @($report.Findings | Where-Object Kind -eq 'MaterialOverlap').Details.OverlapType | Should -Contain 'CrossSource'
    }

    It 'does not infer coverage gaps without an explicit expected window' {
        $observation = New-TestObservation -SourceId 'guide-a'
        $withoutScope = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($observation) -EvaluationTimeUtc $script:EvaluationTime
        $withScope = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($observation) -EvaluationTimeUtc $script:EvaluationTime -ExpectedCoverageWindows @((New-TestCoverageWindow -SourceId 'guide-a' -StartUtc '2026-01-01T11:00:00Z' -StopUtc '2026-01-01T14:00:00Z')) -DurableChannelBindings @((New-TestBinding -SourceId 'guide-a'))

        @($withoutScope.Findings.Kind) | Should -Not -Contain 'CoverageGap'
        @($withScope.Findings.Kind) | Should -Contain 'CoverageGap'
        $withScope.CoverageGaps.Count | Should -Be 2
    }

    It 'reports missing programmes only when another guide has explicit coverage' {
        $observation = New-TestObservation -SourceId 'guide-a'
        $withoutScope = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($observation) -EvaluationTimeUtc $script:EvaluationTime
        $withScope = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($observation) -EvaluationTimeUtc $script:EvaluationTime -ExpectedCoverageWindows @((New-TestCoverageWindow -SourceId 'guide-b')) -DurableChannelBindings @((New-TestBinding -SourceId 'guide-a'))

        @($withoutScope.Findings.Kind) | Should -Not -Contain 'ProgrammeMissing'
        @($withScope.Findings.Kind) | Should -Contain 'ProgrammeMissing'
    }

    It 'flags suspicious assignment against a durable binding without retargeting' {
        $observation = New-TestObservation -SourceId 'guide-a' -Network 'South Network'
        $binding = New-TestBinding -SourceId 'guide-a' -Network 'North Network'
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($observation) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings @($binding)

        @($report.Findings.Kind) | Should -Contain 'SuspiciousAssignment'
        $finding = @($report.Findings | Where-Object Kind -eq 'SuspiciousAssignment')[0]
        $finding.ChannelId | Should -Be 'channel-one'
        $finding.Details.Retargeted | Should -BeFalse
    }

    It 'compares accepted knowledge read-only and reports contradictory fresh evidence' {
        $observation = New-TestObservation -SourceId 'guide-a' -Title 'Rescheduled Final' -Participants @('North', 'South')
        $binding = New-TestBinding -SourceId 'guide-a'
        $accepted = [pscustomobject]@{ KnowledgeId = 'accepted-event-one'; ChannelId = 'channel-one'; Title = 'Scheduled Final'; Participants = @('North', 'South'); StartUtc = '2026-01-01T12:00:00Z'; StopUtc = '2026-01-01T13:00:00Z' }
        $before = $accepted | ConvertTo-Json -Depth 5 -Compress
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($observation) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings @($binding) -AcceptedKnowledge @($accepted)

        @($report.Findings.Kind) | Should -Contain 'AcceptedKnowledgeConflict'
        @($report.Findings | Where-Object Kind -eq 'AcceptedKnowledgeConflict').Details.AcceptedKnowledgeChanged | Should -Contain $false
        ($accepted | ConvertTo-Json -Depth 5 -Compress) | Should -Be $before
        $report.AcceptedKnowledgeMutation | Should -Be 'None'
    }

    It 'keeps every assessment report-only and never changes accepted-state authority' {
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @((New-TestObservation -SourceId 'guide-a')) -EvaluationTimeUtc $script:EvaluationTime

        $report.ReportOnly | Should -Be 'REPORT_ONLY'
        $report.ReadOnly | Should -BeTrue
        $report.CanPublish | Should -BeFalse
        $report.AcceptedStateMutation | Should -Be 'None'
    }
}
