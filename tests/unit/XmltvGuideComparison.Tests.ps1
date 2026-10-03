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
            [string]$UpdatedStartUtc = '',
            [string[]]$Participants = @(),
            [string]$Category = '',
            [string]$Description = '',
            [string]$Competition = '',
            [string]$EventStatus = '',
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
            [string[]]$ReasonCodes = @(),
            [bool]$RedactTimeFields = $false
        )
        $fields = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in @(
            @{ Name = 'Title'; Value = $Title; Type = 'String' },
            @{ Name = 'Subtitle'; Value = $Subtitle; Type = 'String' },
            @{ Name = 'ScheduledStartUtc'; Value = $StartUtc; Type = 'Instant' },
            @{ Name = 'UpdatedStartUtc'; Value = $UpdatedStartUtc; Type = 'Instant' },
            @{ Name = 'StopUtc'; Value = $StopUtc; Type = 'Instant' },
            @{ Name = 'Participant'; Value = $Participants; Type = 'StringArray' },
            @{ Name = 'Description'; Value = $Description; Type = 'String' },
            @{ Name = 'Category'; Value = $Category; Type = 'String' },
            @{ Name = 'Competition'; Value = $Competition; Type = 'String' },
            @{ Name = 'EventStatus'; Value = $EventStatus; Type = 'String' },
            @{ Name = 'Network'; Value = $Network; Type = 'String' },
            @{ Name = 'ChannelAssignment'; Value = $ChannelAssignment; Type = 'String' }
        )) {
            if (($entry.Type -eq 'StringArray' -and @($entry.Value).Count -eq 0) -or
                ($entry.Type -ne 'StringArray' -and [string]::IsNullOrWhiteSpace([string]$entry.Value))) { continue }
            [void]$fields.Add([ordered]@{
                FieldName = $entry.Name
                ValueType = $entry.Type
                NormalizedValue = $entry.Value
                OriginalValueOrFingerprint = if ($RedactTimeFields -and $entry.Name -in @('ScheduledStartUtc', 'UpdatedStartUtc', 'StopUtc')) { 'redacted-clock-fingerprint' } elseif ($entry.Value -is [array]) { [string]::Join('|', $entry.Value) } else { [string]$entry.Value }
                SourceDataTimeUtc = $SourceDataTimeUtc
                ObservationTimeUtc = $FetchTimeUtc
                ReasonCodes = @()
                Redacted = ($RedactTimeFields -and ($entry.Name -in @('ScheduledStartUtc', 'UpdatedStartUtc', 'StopUtc')))
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
            ReasonCodes = @($ReasonCodes)
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

    It 'preserves distinct generated IDs for same-channel correlations' {
        $observations = @(
            (New-TestObservation -SourceId 'guide-a' -Title 'News' -SourceRecordReference 'news-a'),
            (New-TestObservation -SourceId 'guide-b' -Title 'News' -SourceRecordReference 'news-b'),
            (New-TestObservation -SourceId 'guide-a' -Title 'Movie' -StartUtc '2026-01-01T14:00:00Z' -StopUtc '2026-01-01T15:00:00Z' -SourceRecordReference 'movie-a'),
            (New-TestObservation -SourceId 'guide-b' -Title 'Movie' -StartUtc '2026-01-01T14:00:00Z' -StopUtc '2026-01-01T15:00:00Z' -SourceRecordReference 'movie-b')
        )
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations $observations -EvaluationTimeUtc $script:EvaluationTime
        $correlationIds = @($report.Correlations | ForEach-Object CorrelationId)

        $correlationIds.Count | Should -Be 2
        @($correlationIds | Sort-Object -Unique).Count | Should -Be 2
        @($correlationIds | Where-Object { $_ -notmatch '^[a-f0-9]{64}:[a-f0-9]{64}$' }).Count | Should -Be 0
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

    It 'correlates differently named cross-channel events and proposes reversible contextual aliases' {
        $left = New-TestObservation -SourceId 'guide-a' -Title 'Championship: Alpha vs Beta' -StartUtc '2026-01-01T08:00:00-05:00' -StopUtc '2026-01-01T09:00:00-05:00' -Participants @('Alpha', 'Beta') -Competition 'Regional Final' -Category 'Wrestling'
        $right = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Alpha v Beta Championship' -StartUtc '2026-01-01T13:02:00Z' -StopUtc '2026-01-01T14:02:00Z' -Participants @('Beta', 'Alpha') -Competition 'Regional Final' -Category 'Wrestling'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($left, $right) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings
        $reversed = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($right, $left) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings
        $reversed.Json | Should -Be $report.Json


        $report.CrossChannelCorrelations.Count | Should -Be 1
        $correlation = $report.CrossChannelCorrelations[0]
        $correlation.ConfidenceScore | Should -BeGreaterThan 69
        $correlation.ChannelIds | Should -Be @('channel-one', 'channel-two')
        $correlation.SourceIds | Should -Be @('guide-a', 'guide-b')
        $correlation.CanMerge | Should -BeFalse
        $correlation.Provenance.Count | Should -Be 2
        (@($correlation.TimeEvidence | Where-Object DisplayStart -eq '2026-01-01T08:00:00-05:00')[0]).CanonicalStartUtc | Should -Be '2026-01-01T13:00:00Z'
        $report.ContextualAliasProposals.Count | Should -Be 1
        $report.ContextualAliasProposals[0].Status | Should -Be 'Proposed'
        $report.ContextualAliasProposals[0].Reversible | Should -BeTrue
        $report.ContextualAliasProposals[0].Accepted | Should -BeFalse
        $proposal = $report.ContextualAliasProposals[0]
        $proposal.EvidenceCount | Should -Be 2
        $proposal.ApprovalState | Should -Be 'Pending'
        $proposal.FirstSeenAtUtc | Should -Be '2026-01-01T11:45:00Z'
        $proposal.LastSeenAtUtc | Should -Be '2026-01-01T11:45:00Z'
    }

    It 'uses offset evidence from the effective updated start field' {
        $left = New-TestObservation -SourceId 'guide-a' -Title 'Regional Championship Final' -StartUtc '2026-01-01T12:00:00Z' -UpdatedStartUtc '2026-01-01T08:00:00-05:00' -StopUtc '2026-01-01T09:00:00-05:00' -Participants @('North', 'East') -Competition 'League Final'
        $right = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Regional Championship Final' -StartUtc '2026-01-01T13:00:00Z' -UpdatedStartUtc '2026-01-01T13:00:00Z' -StopUtc '2026-01-01T14:00:00Z' -Participants @('North', 'East') -Competition 'League Final'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($left, $right) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $report.CrossChannelCorrelations.Count | Should -Be 1
        $leftTime = @($report.CrossChannelCorrelations[0].TimeEvidence | Where-Object ObservationId -eq $left.ObservationId)[0]
        $leftTime.DisplayStart | Should -Be '2026-01-01T08:00:00-05:00'
        $leftTime.CanonicalStartUtc | Should -Be '2026-01-01T13:00:00Z'
    }
    It 'does not infer cross-channel UTC from timezone-less display clocks' {
        $left = New-TestObservation -SourceId 'guide-a' -Title 'Regional Championship Final' -StartUtc '2026-01-01T12:00:00' -StopUtc '2026-01-01T13:00:00' -Participants @('North', 'East') -Competition 'League Final'
        $right = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Regional Championship Final' -StartUtc '2026-01-01T12:00:00Z' -StopUtc '2026-01-01T13:00:00Z' -Participants @('North', 'East') -Competition 'League Final'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($left, $right) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $report.CrossChannelCorrelations.Count | Should -Be 0
    }

    It 'never publishes redacted time fingerprints as display-clock evidence' {
        $left = New-TestObservation -SourceId 'guide-a' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final' -RedactTimeFields $true
        $right = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($left, $right) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $report.CrossChannelCorrelations.Count | Should -Be 0
        $report.ContextualAliasProposals.Count | Should -Be 0
        $report.Json | Should -Not -Match 'redacted-clock-fingerprint'
    }

    It 'keeps stale and future rows diagnostic but ineligible for cross-channel aliases' {
        $stale = New-TestObservation -SourceId 'guide-stale' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final' -SourceDataTimeUtc '2025-12-30T11:30:00Z'
        $fresh = New-TestObservation -SourceId 'guide-fresh' -ChannelReference 'station-two' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final'
        $bindings = @((New-TestBinding -SourceId 'guide-stale' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-fresh' -Reference 'station-two' -ChannelId 'channel-two'))
        $staleReport = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($stale, $fresh) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings
        $future = New-TestObservation -SourceId 'guide-future' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final' -SourceDataTimeUtc '2026-01-02T11:30:00Z'
        $futureReport = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($future, $fresh) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings @((New-TestBinding -SourceId 'guide-future' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-fresh' -Reference 'station-two' -ChannelId 'channel-two'))

        ($staleReport.FreshnessAssessments | Where-Object SourceId -eq 'guide-stale').FreshnessState | Should -Be 'Stale'
        @($staleReport.Findings.Kind) | Should -Contain 'StaleObservation'
        $staleReport.CrossChannelCorrelations.Count | Should -Be 0
        $staleReport.ContextualAliasProposals.Count | Should -Be 0
        ($futureReport.FreshnessAssessments | Where-Object SourceId -eq 'guide-future').FreshnessState | Should -Be 'FutureDated'
        @($futureReport.Findings.Kind) | Should -Contain 'FutureDatedObservation'
        $futureReport.CrossChannelCorrelations.Count | Should -Be 0
        $futureReport.ContextualAliasProposals.Count | Should -Be 0
    }


    It 'does not cross-correlate nearby distinct events with conflicting participants' {
        $left = New-TestObservation -SourceId 'guide-a' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final'
        $right = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Regional Championship Final' -Participants @('South', 'West') -Competition 'League Final'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($left, $right) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $report.CrossChannelCorrelations.Count | Should -Be 0
        $report.ContextualAliasProposals.Count | Should -Be 0
    }

    It 'keeps live programming separate from replay observations' {
        $live = New-TestObservation -SourceId 'guide-a' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final' -EventStatus 'Live'
        $replay = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final' -EventStatus 'Replay'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($live, $replay) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $report.CrossChannelCorrelations.Count | Should -Be 0
        $report.ContextualAliasProposals.Count | Should -Be 0
    }
    It 'uses corroborating descriptions for news and aligned title/category/time for movies' {
        $description = 'A detailed report on the city council vote and the community response from local residents.'
        $newsA = New-TestObservation -SourceId 'guide-a' -Title 'Evening News' -Description $description -Category 'News'
        $newsB = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Evening News Broadcast' -Description $description -Category 'News'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $newsReport = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($newsA, $newsB) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings
        $movieA = New-TestObservation -SourceId 'guide-a' -Title 'The Example Movie' -Category 'Film'
        $movieB = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'The Example Movie' -Category 'Movies'
        $movieReport = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($movieA, $movieB) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $newsReport.CrossChannelCorrelations.Count | Should -Be 1
        $newsReport.CrossChannelCorrelations[0].CorrelationBasis | Should -Contain 'MatchingDescription'
        $movieReport.CrossChannelCorrelations.Count | Should -Be 1
        $movieReport.CrossChannelCorrelations[0].CorrelationBasis | Should -Contain 'MovieTitleAndAiring'
        $movieReport.CrossChannelCorrelations[0].CorrelationBasis | Should -Contain 'MatchingCategory'
    }

    It 'preserves non-Latin programme and participant text during correlation' {
        $title = 'نهائي بطولة المملكة'
        $participants = @('الهلال', 'النصر')
        $left = New-TestObservation -SourceId 'guide-a' -Title $title -Participants $participants -Competition 'دوري روشن'
        $right = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title $title -Participants $participants -Competition 'دوري روشن'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($left, $right) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $report.CrossChannelCorrelations.Count | Should -Be 1
        $report.CrossChannelCorrelations[0].CorrelationBasis | Should -Contain 'MatchingParticipants'
    }



    It 'keeps episodic programmes distinct while correlating the same episode' {
        $sameA = New-TestObservation -SourceId 'guide-a' -Title 'The Long Running Show' -Subtitle 'S01E03' -Category 'Entertainment'
        $sameB = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'The Long Running Show' -Subtitle 'S01E03' -Category 'Entertainment'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $same = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($sameA, $sameB) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings
        $differentB = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'The Long Running Show' -Subtitle 'S01E04' -Category 'Entertainment'
        $different = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($sameA, $differentB) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $same.CrossChannelCorrelations.Count | Should -Be 1
        $same.ContextualAliasProposals.Count | Should -Be 0
        $different.CrossChannelCorrelations.Count | Should -Be 0
    }

    It 'marks one-to-many cross-channel matches for review without selecting a winner' {
        $left = New-TestObservation -SourceId 'guide-a' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final'
        $rightOne = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final' -SourceRecordReference 'event-b1'
        $rightTwo = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title 'Regional Championship Final' -Participants @('North', 'East') -Competition 'League Final' -SourceRecordReference 'event-b2'
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($left, $rightOne, $rightTwo) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        @($report.CrossChannelCorrelations | Where-Object ReviewRequired).Count | Should -Be 2
        @($report.Findings.Kind) | Should -Contain 'AmbiguousCrossChannelProgrammeCorrelation'
        $report.ContextualAliasProposals.Count | Should -Be 0
        @($report.CrossChannelCorrelations | Where-Object CanMerge).Count | Should -Be 0
    }

    It 'builds category-wide channel profiles and gap candidates, including missing XMLTV' {
        $observation = New-TestObservation -SourceId 'guide-a' -Category 'Movies'
        $unknownObservation = New-TestObservation -SourceId 'guide-unknown' -Category 'unregistered-category'
        $bindings = @(
            (New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-known'),
            (New-TestBinding -SourceId 'guide-ppv' -Reference 'ppv-reference' -ChannelId 'channel-ppv'),
            (New-TestBinding -SourceId 'guide-temporary' -Reference 'temporary-reference' -ChannelId 'channel-temporary'),
            (New-TestBinding -SourceId 'guide-unknown' -ChannelId 'channel-unknown'),
            (New-TestBinding -SourceId 'guide-obscure' -Reference 'obscure-reference' -ChannelId 'channel-obscure')
        )
        $windows = @(
            (New-TestCoverageWindow -SourceId 'guide-a' -ChannelId 'channel-known' -StartUtc '2026-01-01T11:00:00Z' -StopUtc '2026-01-01T14:00:00Z'),
            (New-TestCoverageWindow -SourceId 'guide-ppv' -ChannelId 'channel-ppv' -StartUtc '2026-01-01T12:00:00Z' -StopUtc '2026-01-01T13:00:00Z')
        )
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($observation, $unknownObservation) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings -ExpectedCoverageWindows $windows

        $known = @($report.ChannelEvidenceProfiles | Where-Object ChannelId -eq 'channel-known')[0]
        $known.GuideState | Should -Be 'CoverageGap'
        $known.CategoryKeys | Should -Contain 'movies'
        $ppv = @($report.ChannelEvidenceProfiles | Where-Object ChannelId -eq 'channel-ppv')[0]
        $unknown = @($report.ChannelEvidenceProfiles | Where-Object ChannelId -eq 'channel-unknown')[0]
        $unknown.CategoryKeys.Count | Should -Be 0
        $unknown.EnrichmentCategoryKeys.Count | Should -Be 0
        $ppv.GuideState | Should -Be 'MissingXmltv'
        @($ppv.EnrichmentCategoryKeys) | Should -Contain 'wrestling'
        @($ppv.EnrichmentCategoryKeys) | Should -Contain 'movies'
        @($ppv.EnrichmentCategoryKeys) | Should -Contain 'news'
        $expectedCategories = @('football', 'baseball', 'basketball', 'hockey', 'soccer', 'wrestling', 'motorsports', 'boxing', 'mma', 'tennis', 'golf', 'rugby', 'cricket', 'lacrosse', 'other-sports', 'movies', 'news', 'kids', 'entertainment', 'documentary', 'comedy')
        (@($ppv.EnrichmentCategoryKeys | Sort-Object) -join ',') | Should -BeExactly (@($expectedCategories | Sort-Object) -join ',')
        @($ppv.EnrichmentCategoryKeys) | Should -Contain 'documentary'
        @($report.EnrichmentCandidates | Where-Object { $_.ChannelId -eq 'channel-ppv' -and $_.Kind -eq 'MissingXmltv' }).Count | Should -Be 1
        @($report.EnrichmentCandidates | Where-Object { $_.SourceAccess -ne 'NotEvaluated' -or $_.CanFetch }).Count | Should -Be 0
    }

    It 'redacts sensitive report values and escapes untrusted Markdown content' {
        $hostileTitle = '[click](https://attacker.invalid) <img src=x onerror=alert(1)> Regional Championship Final'
        $left = New-TestObservation -SourceId 'guide-a' -Title $hostileTitle -Participants @('North', 'East') -Competition 'League Final' -Description 'Shared details' -SourceRecordReference 'API_KEY=provenanceSecret file=/home/private/provenance.xml'
        $variant = New-TestObservation -SourceId 'guide-a' -Title $hostileTitle -Participants @('North', 'East') -Competition 'League Final' -Description 'api_key=fieldSecret' -SourceRecordReference 'event-a-variant'
        $right = New-TestObservation -SourceId 'guide-b' -ChannelReference 'station-two' -Title $hostileTitle -Participants @('North', 'East') -Competition 'League Final' -Description 'Shared details'
        $rejected = New-TestObservation -SourceId 'guide-c' -ObservationStatus 'Rejected' -ReasonCodes @('password=reasonSecret', 'Authorization: Bearer authSecret')
        $bindings = @((New-TestBinding -SourceId 'guide-a' -ChannelId 'channel-one'), (New-TestBinding -SourceId 'guide-b' -Reference 'station-two' -ChannelId 'channel-two'))
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @($left, $variant, $right, $rejected) -EvaluationTimeUtc $script:EvaluationTime -DurableChannelBindings $bindings

        $report.Json | Should -Not -Match 'fieldSecret|anotherSecret|provenanceSecret|provenance\.xml|reasonSecret|authSecret|attacker\.invalid'
        $report.Markdown | Should -Not -Match 'fieldSecret|anotherSecret|provenanceSecret|provenance\.xml|reasonSecret|authSecret|attacker\.invalid|(?<!\\)<img|!\[|\]\('
        $report.Markdown | Should -Match '\\<img'
        @($report.Findings.Kind) | Should -Contain 'RejectedObservation'
    }

    It 'keeps every assessment report-only and never changes accepted-state authority' {
        $report = Compare-ChannelForgeXmltvGuides -PlaylistId 'playlist-one' -Observations @((New-TestObservation -SourceId 'guide-a')) -EvaluationTimeUtc $script:EvaluationTime

        $report.ReportOnly | Should -Be 'REPORT_ONLY'
        $report.ReadOnly | Should -BeTrue
        $report.CanPublish | Should -BeFalse
        $report.AcceptedStateMutation | Should -Be 'None'
    }
}
