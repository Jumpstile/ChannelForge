BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixtureDirectory = Join-Path $RepoRoot 'tests\fixtures\guide-intelligence'
    $script:EventFixture = @(Get-Content (Join-Path $script:FixtureDirectory 'stage-a-events.json') -Raw | ConvertFrom-Json)

    function New-FixtureEvidence {
        param([Parameter(Mandatory)][object]$Fixture)
        $parameters = @{
            EvidenceType = [string]$Fixture.evidenceType
            SourceId = [string]$Fixture.sourceId
            SourceFamily = [string]$Fixture.sourceFamily
            SourceRelationship = [string]$Fixture.sourceRelationship
            ChannelReference = [string]$Fixture.channelReference
            DisplayName = [string]$Fixture.displayName
            Group = [string]$Fixture.group
            Title = [string]$Fixture.title
            EventType = [string]$Fixture.eventType
            League = [string]$Fixture.league
            Sport = [string]$Fixture.sport
            HomeParticipant = [string]$Fixture.homeParticipant
            AwayParticipant = [string]$Fixture.awayParticipant
            StartUtc = [string]$Fixture.startUtc
            EndUtc = [string]$Fixture.endUtc
            SourceTimezone = [string]$Fixture.sourceTimezone
            EventStatus = [string]$Fixture.eventStatus
            ConfidenceState = [string]$Fixture.confidenceState
            ConfidenceScore = [int]$Fixture.confidenceScore
            FreshnessState = [string]$Fixture.freshnessState
            ReasonCodes = @($Fixture.reasonCodes | ForEach-Object { [string]$_ })
        }
        return New-ChannelForgeGuideEvidence @parameters
    }
}

Describe 'Stage A guide intelligence fixtures' {
    It 'covers every required event family and source path' {
        @($script:EventFixture.eventType | Sort-Object -Unique) | Should -Contain 'Fight'
        @($script:EventFixture.eventType | Sort-Object -Unique) | Should -Contain 'PPV'
        @($script:EventFixture.eventType | Sort-Object -Unique) | Should -Contain 'TemporaryEvent'
        @($script:EventFixture.eventType | Sort-Object -Unique) | Should -Contain 'League'
        @($script:EventFixture.eventType | Sort-Object -Unique) | Should -Contain 'SingleTeam'
        @($script:EventFixture.eventType | Sort-Object -Unique) | Should -Contain 'StreamingEvent'
        @($script:EventFixture.eventStatus | Sort-Object -Unique) | Should -Contain 'Postponed'
        @($script:EventFixture.eventStatus | Sort-Object -Unique) | Should -Contain 'Cancelled'
        @($script:EventFixture.eventStatus | Sort-Object -Unique) | Should -Contain 'Rescheduled'
        @($script:EventFixture.confidenceState | Sort-Object -Unique) | Should -Contain 'StaleSource'
        @($script:EventFixture.confidenceState | Sort-Object -Unique) | Should -Contain 'SourceUnavailable'
        @($script:EventFixture.confidenceState | Sort-Object -Unique) | Should -Contain 'NeedsReview'
        @($script:EventFixture.evidenceType | Sort-Object -Unique) | Should -Contain 'ProviderDisplayText'
        @($script:EventFixture.confidenceState | Sort-Object -Unique) | Should -Contain 'Unresolved'
        @($script:EventFixture.evidenceType | Sort-Object -Unique) | Should -Contain 'ProviderM3UMetadata'
        @($script:EventFixture.evidenceType | Sort-Object -Unique) | Should -Contain 'XMLTV'
        @($script:EventFixture.evidenceType | Sort-Object -Unique) | Should -Contain 'AEDDerivedXMLTV'
        @($script:EventFixture.evidenceType | Sort-Object -Unique) | Should -Contain 'AEDDerivedM3U'
        @($script:EventFixture.evidenceType | Sort-Object -Unique) | Should -Contain 'ScheduleSource'
        @($script:EventFixture.evidenceType | Sort-Object -Unique) | Should -Contain 'AcceptedKnowledge'
    }

    It 'contains only sanitized fixture data and valid XMLTV examples' {
        $eventText = Get-Content (Join-Path $script:FixtureDirectory 'stage-a-events.json') -Raw
        $staleText = Get-Content (Join-Path $script:FixtureDirectory 'stage-a-stale-guide.json') -Raw
        $eventText + $staleText | Should -Not -Match '(?i)https?://|password|passwd|secret|credential|token|parser error|[A-Z]:[\\/]'
        { [xml](Get-Content (Join-Path $script:FixtureDirectory 'stage-a-valid-event-guide.xml') -Raw) } | Should -Not -Throw
        { [xml](Get-Content (Join-Path $script:FixtureDirectory 'stage-a-missing-tvg-id.xml') -Raw) } | Should -Not -Throw
        { [xml](Get-Content (Join-Path $script:FixtureDirectory 'stage-a-malformed-event-guide.xml') -Raw) } | Should -Throw
    }
}

Describe 'New-ChannelForgeGuideEvidence' {
    It 'models provider, guide, AED, schedule, and accepted knowledge without raw input retention' {
        $evidence = New-ChannelForgeGuideEvidence `
            -EvidenceType ProviderM3UMetadata `
            -SourceId provider-main `
            -SourceFamily provider-lineup `
            -SourceRelationship Authoritative `
            -ChannelReference event.ufc.20260912 `
            -DisplayName 'UFC Fight Night' `
            -Title 'UFC Fight Night' `
            -EventType Fight `
            -Sport MMA `
            -StartUtc '2026-09-12T23:00:00-04:00' `
            -EndUtc '2026-09-13T06:00:00Z' `
            -SourceTimezone America/New_York `
            -ConfidenceState Confirmed `
            -ConfidenceScore 96 `
            -FreshnessState Current

        $evidence.GetType().Name | Should -Be 'GuideEvidenceRecord'
        $evidence.ContractVersion | Should -Be 'guide-intelligence/v1'
        $evidence.StartUtc | Should -Be '2026-09-13T03:00:00Z'
        $evidence.ConfidenceState | Should -Be 'Confirmed'
        $evidence.ReadOnly | Should -BeTrue
        @($evidence.RedactedFields) | Should -Contain 'StreamUrl'
        @($evidence.RedactedFields) | Should -Contain 'GenerationId'
    }

    It 'accepts safe metadata fields and excludes sensitive metadata' {
        $evidence = New-ChannelForgeGuideEvidence `
            -EvidenceType AEDDerivedXMLTV `
            -SourceId aed-bootstrap `
            -Metadata ([ordered]@{
                SourceFamily = 'provider-guide'
                ChannelReference = 'ppv.event.20260913'
                DisplayName = 'PPV https://private.example.invalid/guide'
                Title = 'PPV Main Event C:\private\guide.xml'
                EventType = 'PPV'
                ConfidenceState = 'SafeCandidate'
                ConfidenceScore = 82
                FreshnessState = 'Current'
                Url = 'https://private.example.invalid/stream'
                StreamUrl = 'https://private.example.invalid/live'
                Credential = 'secret-value'
                Token = 'token-value'
                ParserError = 'raw parser error'
                CandidateHash = ('a' * 64)
                GenerationId = ('b' * 64)
            })

        $json = $evidence | ConvertTo-Json -Depth 10
        $json | Should -Not -Match 'private\.example\.invalid|secret-value|token-value|raw parser error|[A-Z]:[\\/]private'
        $evidence.SourceFamily | Should -Be 'provider-guide'
        $evidence.ChannelReference | Should -Be 'ppv.event.20260913'
        $evidence.ConfidenceState | Should -Be 'SafeCandidate'
        $evidence.ConfidenceScore | Should -Be 82
    }

    It 'downgrades low-confidence confirmation and preserves only safe reason codes' {
        $evidence = New-ChannelForgeGuideEvidence `
            -EvidenceType ProviderDisplayText `
            -SourceId provider-main `
            -ChannelReference event.ambiguous.01 `
            -Title 'Ambiguous Event' `
            -EventType Sports `
            -ConfidenceState Confirmed `
            -ConfidenceScore 35 `
            -ReasonCodes @('AmbiguousTitle')

        $evidence.ConfidenceState | Should -Be 'NeedsReview'
        @($evidence.ReasonCodes) | Should -Contain 'ConfidenceBelowThreshold'
        { New-ChannelForgeGuideEvidence -EvidenceType ProviderDisplayText -SourceId 'https://private.example.invalid/source' } | Should -Throw '*logical identifier*'
    }

    It 'maps stale and unavailable source evidence to explicit states' {
        $stale = New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-old -ChannelReference event.stale.01 -Title 'Stale Event' -EventType Sports -ConfidenceState Confirmed -ConfidenceScore 95 -FreshnessState Stale
        $unavailable = New-ChannelForgeGuideEvidence -EvidenceType ScheduleSource -SourceId schedule-down -ChannelReference event.down.01 -Title 'Unavailable Event' -EventType Sports -ConfidenceState Confirmed -ConfidenceScore 95 -FreshnessState Unavailable

        $stale.ConfidenceState | Should -Be 'StaleSource'
        $unavailable.ConfidenceState | Should -Be 'SourceUnavailable'
    }
}

Describe 'Get-ChannelForgeGuideReadiness' {
    It 'reports confirmed evidence as candidate-only and never publishes from read-only projection' {
        $evidence = New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-primary -ChannelReference sports.mlb.01 -Title 'League Baseball Tonight' -EventType League -League MLB -Sport Baseball -StartUtc '2026-09-14T23:00:00Z' -EndUtc '2026-09-15T02:00:00Z' -ConfidenceState Confirmed -ConfidenceScore 96 -FreshnessState Current
        $result = Get-ChannelForgeGuideReadiness -Evidence @($evidence)

        $result.OverallState | Should -Be 'Confirmed'
        $result.Records[0].ReadinessState | Should -Be 'Confirmed'
        $result.PublicationState | Should -Be 'CandidateOnly'
        $result.PromotionRequired | Should -Be 'ExplicitAcceptance'
        $result.CanPublish | Should -BeFalse
        $result.AcceptedStateMutation | Should -Be 'None'
        $result.ReadOnly | Should -BeTrue
        @($result.PSObject.Properties.Name) | Should -Not -Contain 'GenerationId'
    }

    It 'keeps low-confidence events in review' {
        $evidence = New-ChannelForgeGuideEvidence -EvidenceType ProviderDisplayText -SourceId provider-main -ChannelReference event.review.01 -Title 'Ambiguous Event' -EventType Sports -ConfidenceState SafeCandidate -ConfidenceScore 40 -FreshnessState Current -ReasonCodes @('AmbiguousTitle', 'AmbiguousTime')
        $result = Get-ChannelForgeGuideReadiness -Evidence @($evidence)

        $result.OverallState | Should -Be 'NeedsReview'
        $result.Records[0].ReadinessState | Should -Be 'NeedsReview'
        $result.Records[0].RequiresReview | Should -BeTrue
        $result.CanPublish | Should -BeFalse
    }

    It 'rejects contradictory timing and preserves accepted evidence unchanged' {
        $accepted = New-ChannelForgeGuideEvidence -EvidenceType AcceptedKnowledge -SourceId accepted-local -ChannelReference event.conflict.01 -Title 'Conflicting Event' -EventType Sports -StartUtc '2026-09-21T23:00:00Z' -EndUtc '2026-09-22T02:00:00Z' -ConfidenceState Confirmed -ConfidenceScore 98 -FreshnessState Current
        $candidate = New-ChannelForgeGuideEvidence -EvidenceType ScheduleSource -SourceId schedule-secondary -ChannelReference event.conflict.01 -Title 'Conflicting Event' -EventType Sports -StartUtc '2026-09-21T22:00:00Z' -EndUtc '2026-09-22T01:00:00Z' -ConfidenceState NeedsReview -ConfidenceScore 52 -FreshnessState Current -ReasonCodes @('EvidenceContradicts', 'AmbiguousTime')
        $before = $accepted | ConvertTo-Json -Depth 10
        $result = Get-ChannelForgeGuideReadiness -Evidence @($candidate, $accepted)
        $after = $accepted | ConvertTo-Json -Depth 10

        $result.OverallState | Should -Be 'Contradiction'
        $result.Records[0].ReadinessState | Should -Be 'Contradiction'
        $result.Records[0].RequiresReview | Should -BeTrue
        $result.AcceptedStatePreserved | Should -BeTrue
        $result.AcceptedStateMutation | Should -Be 'None'
        $result.CanPublish | Should -BeFalse
        $after | Should -Be $before
    }

    It 'preserves accepted state when source evidence is stale or unavailable' {
        $accepted = New-ChannelForgeGuideEvidence -EvidenceType AcceptedKnowledge -SourceId accepted-local -ChannelReference event.stale.01 -Title 'Known Event' -EventType Sports -StartUtc '2026-09-20T23:00:00Z' -EndUtc '2026-09-21T02:00:00Z' -ConfidenceState Confirmed -ConfidenceScore 98 -FreshnessState Current
        $stale = New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-old -ChannelReference event.stale.01 -Title 'Known Event' -EventType Sports -StartUtc '2026-09-20T23:00:00Z' -EndUtc '2026-09-21T02:00:00Z' -ConfidenceState Confirmed -ConfidenceScore 95 -FreshnessState Stale
        $before = $accepted | ConvertTo-Json -Depth 10
        $result = Get-ChannelForgeGuideReadiness -Evidence @($accepted, $stale)
        $after = $accepted | ConvertTo-Json -Depth 10

        $result.OverallState | Should -Be 'StaleSource'
        $result.AcceptedStatePreserved | Should -BeTrue
        $result.AcceptedStateMutation | Should -Be 'None'
        $after | Should -Be $before
    }

    It 'does not mutate accepted state while projecting event evidence' {
        $accepted = New-ChannelForgeGuideEvidence -EvidenceType AcceptedKnowledge -SourceId accepted-local -ChannelReference event.readonly.01 -Title 'Read Only Event' -EventType Fight -ConfidenceState Confirmed -ConfidenceScore 99 -FreshnessState Current
        $snapshot = $accepted | ConvertTo-Json -Depth 10
        [void](Get-ChannelForgeGuideReadiness -Evidence @($accepted))

        ($accepted | ConvertTo-Json -Depth 10) | Should -Be $snapshot
        $accepted.ReadOnly | Should -BeTrue
    }

    It 'does not count mirrored sources as independent confirmation' {
        $first = New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-a -SourceFamily shared-feed -SourceRelationship Mirror -ChannelReference event.mirror.01 -Title 'Mirrored Event' -EventType Sports -StartUtc '2026-09-23T23:00:00Z' -EndUtc '2026-09-24T02:00:00Z' -ConfidenceState Confirmed -ConfidenceScore 95 -FreshnessState Current
        $second = New-ChannelForgeGuideEvidence -EvidenceType AEDDerivedXMLTV -SourceId guide-b -SourceFamily shared-feed -SourceRelationship Mirror -ChannelReference event.mirror.01 -Title 'Mirrored Event' -EventType Sports -StartUtc '2026-09-23T23:00:00Z' -EndUtc '2026-09-24T02:00:00Z' -ConfidenceState Confirmed -ConfidenceScore 95 -FreshnessState Current
        $result = Get-ChannelForgeGuideReadiness -Evidence @($first, $second)

        $result.OverallState | Should -Be 'NeedsReview'
        $result.Records[0].RequiresReview | Should -BeTrue
        $result.CanPublish | Should -BeFalse
    }
}
