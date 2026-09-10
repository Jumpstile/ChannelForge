BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixtureDirectory = Join-Path $RepoRoot 'tests\fixtures\guide-intelligence'

    function Read-StageBFixture {
        param([Parameter(Mandatory)][string]$Name)
        return Get-Content (Join-Path $script:FixtureDirectory $Name) -Raw | ConvertFrom-Json
    }

    function ConvertTo-StageBTimezoneMap {
        param([AllowNull()][object]$InputObject)
        $map = [ordered]@{}
        if ($null -ne $InputObject) {
            foreach ($property in $InputObject.PSObject.Properties) {
                $map[$property.Name] = [string]$property.Value
            }
        }
        return $map
    }

    function Invoke-StageBFixtureCase {
        param([Parameter(Mandatory)][object]$Case)
        $parameters = @{
            Examples = @($Case.examples | ForEach-Object { [string]$_ })
            MinimumExamples = [int]$Case.minimumExamples
            TimezoneMap = ConvertTo-StageBTimezoneMap -InputObject $Case.timezoneMap
        }
        if ($null -ne $Case.PSObject.Properties['eventType'] -and -not [string]::IsNullOrWhiteSpace([string]$Case.eventType)) {
            $parameters.EventType = [string]$Case.eventType
        }
        if ($null -ne $Case.PSObject.Properties['referenceInstantUtc'] -and -not [string]::IsNullOrWhiteSpace([string]$Case.referenceInstantUtc)) {
            $parameters.ReferenceInstantUtc = [datetimeoffset]$Case.referenceInstantUtc
        }
        return Invoke-ChannelForgeGuidePatternInference @parameters
    }
}

Describe 'Invoke-ChannelForgeGuidePatternInference' {
    It 'exports a beginner-safe examples contract without a regex parameter' {
        $command = Get-Command Invoke-ChannelForgeGuidePatternInference
        @($command.Parameters.Keys) | Should -Contain 'Examples'
        @($command.Parameters.Keys) | Should -Contain 'Evidence'
        @($command.Parameters.Keys) | Should -Not -Contain 'Regex'

        $result = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm',
                'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm',
                'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
            ) `
            -EventType Fight `
            -TimezoneMap ([ordered]@{ UTC = '+00:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z'

        $result.InferenceMethod | Should -Be 'NativeEventPattern'
        $result.OverallState | Should -Be 'Confirmed'
        $result.PublicationState | Should -Be 'CandidateOnly'
        $result.PromotionRequired | Should -Be 'ExplicitAcceptance'
        $result.CanPublish | Should -BeFalse
        $result.ReadOnly | Should -BeTrue
        $result.AcceptedStateMutation | Should -Be 'None'
        $result.Candidates.Count | Should -Be 1
        $result.SelectedCandidate | Should -Not -BeNullOrEmpty
        @($result.Candidates[0].Grammar.Segments | ForEach-Object { $_.Extractor }) | Should -Not -Contain 'Regex'
        @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '01' })[0].StartTimeUtc | Should -Be '2024-04-13T17:00:00Z'
        @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '01' })[0].EventDayOfWeek | Should -Be 'Sat'
        @($result.Candidates[0].Grammar.WeekdayFormats) | Should -Contain 'EEE'
    }

    It 'infers every required UFC example and preserves title punctuation' {
        $fixture = Read-StageBFixture -Name 'stage-b-ufc-pattern-examples.json'
        $parameters = @{
            Examples = @($fixture.examples | ForEach-Object { [string]$_.input })
            MinimumExamples = [int]$fixture.minimumExamples
            TimezoneMap = ConvertTo-StageBTimezoneMap -InputObject $fixture.timezoneMap
            ReferenceInstantUtc = [datetimeoffset]$fixture.referenceInstantUtc
        }
        $result = Invoke-ChannelForgeGuidePatternInference @parameters

        $result.OverallState | Should -Be 'Confirmed'
        $result.ExampleCount | Should -Be 6
        $result.MatchedExampleCount | Should -Be 6
        $result.ReviewItems.Count | Should -Be 0
        $result.Candidates[0].Scope.EventFamily | Should -Be 'Fight'
        $result.Candidates[0].Scope.League | Should -Be 'UFC'
        $result.Candidates[0].Scope.Sport | Should -Be 'MMA'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'ChannelIdentifier'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'ChannelOrdinal'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'EventTitle'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'EventDate'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'EventTime'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'EventTimezone'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'HomeParticipant'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'AwayParticipant'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'League'
        @($result.Candidates[0].FieldCandidates | ForEach-Object { $_.FieldName }) | Should -Contain 'Sport'

        foreach ($fixtureExample in @($fixture.examples)) {
            $expected = $fixtureExample.expected
            $item = @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq [string]$expected.channelOrdinalText })[0]
            $item | Should -Not -BeNullOrEmpty
            $item.ChannelIdentifier | Should -Be $expected.channelIdentifier
            $item.EventTitle | Should -Be $expected.title
            $item.EventDate | Should -Be $expected.date
            $item.StartUtc | Should -Be (([datetimeoffset]$expected.startUtc).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"))
            $item.EventType | Should -Be $expected.eventType
            $item.League | Should -Be $expected.league
            $item.Sport | Should -Be $expected.sport
            if ($null -ne $expected.PSObject.Properties['homeParticipant']) { $item.HomeParticipant | Should -Be $expected.homeParticipant }
            if ($null -ne $expected.PSObject.Properties['awayParticipant']) { $item.AwayParticipant | Should -Be $expected.awayParticipant }
        }
    }

    It 'is deterministic across input order and reference instant for the same grammar' {
        $examples = @(
            'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm',
            'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm',
            'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
        )
        $forward = Invoke-ChannelForgeGuidePatternInference -Examples $examples -EventType Fight -TimezoneMap ([ordered]@{ UTC = '+00:00' }) -ReferenceInstantUtc '2024-04-15T00:00:00Z'
        $reverse = Invoke-ChannelForgeGuidePatternInference -Examples @($examples | Sort-Object -Descending) -EventType Fight -TimezoneMap ([ordered]@{ UTC = '+00:00' }) -ReferenceInstantUtc '2024-04-15T00:00:00Z'
        $otherReference = Invoke-ChannelForgeGuidePatternInference -Examples $examples -EventType Fight -TimezoneMap ([ordered]@{ UTC = '+00:00' }) -ReferenceInstantUtc '2025-04-15T00:00:00Z'

        $forward.Candidates[0].RuleId | Should -Be $reverse.Candidates[0].RuleId
        $forward.Candidates[0].RuleId | Should -Be $otherReference.Candidates[0].RuleId
        $forward.Candidates[0].RuleId | Should -Match '^pattern-[0-9a-f]{64}$'
        ($forward.ExtractionPreview | ConvertTo-Json -Depth 20) | Should -Be ($reverse.ExtractionPreview | ConvertTo-Json -Depth 20)
    }

    It 'covers PPV, temporary event, league, single-team, and ESPN-plus scopes' {
        $fixture = Read-StageBFixture -Name 'stage-b-event-family-examples.json'
        foreach ($case in @($fixture.cases)) {
            $result = Invoke-StageBFixtureCase -Case $case
            $result.OverallState | Should -Be 'Confirmed' -Because $case.caseId
            $result.ExtractionPreview[0].EventType | Should -Be $case.expected.eventType -Because $case.caseId
            if ($null -ne $case.expected.PSObject.Properties['league']) { $result.Candidates[0].Scope.League | Should -Be $case.expected.league }
            if ($null -ne $case.expected.PSObject.Properties['sport']) { $result.Candidates[0].Scope.Sport | Should -Be $case.expected.sport }
            if ($null -ne $case.expected.PSObject.Properties['homeParticipant']) {
                @($result.ExtractionPreview | ForEach-Object { $_.HomeParticipant }) | Should -Contain $case.expected.homeParticipant
            }
        }
        $nativeEspn = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'ESPN+ 03: UFC Fight Night // ET Sat 20 Apr 7:00pm',
                'ESPN+ 04: UFC Fight Night Replay // ET Sun 21 Apr 7:00pm'
            ) `
            -TimezoneMap ([ordered]@{ ET = '-05:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z' `
            -MinimumExamples 2
        $nativeEspn.Candidates[0].Scope.EventFamily | Should -Be 'StreamingEvent'
    }
    It 'supports bounded date, time, punctuation, and ordinal variants' {
        $fixture = Read-StageBFixture -Name 'stage-b-format-cases.json'
        foreach ($case in @($fixture.cases)) {
            $parameters = @{
                Examples = @($case.examples | ForEach-Object { [string]$_ })
                EventType = [string]$case.eventType
                MinimumExamples = if ($null -ne $case.PSObject.Properties['minimumExamples']) { [int]$case.minimumExamples } else { [int]$fixture.minimumExamples }
                TimezoneMap = ConvertTo-StageBTimezoneMap -InputObject $fixture.timezoneMap
                ReferenceInstantUtc = [datetimeoffset]$fixture.referenceInstantUtc
                DateOrder = if ($null -ne $case.PSObject.Properties['dateOrder']) { [string]$case.dateOrder } else { 'MonthFirst' }
            }
            $result = Invoke-ChannelForgeGuidePatternInference @parameters
            $result.OverallState | Should -Be $case.expected.state -Because $case.caseId

            if ($case.caseId -eq 'mixed-date-and-time-formats') {
                @($result.Candidates[0].Grammar.DateFormats) | Should -Contain 'M/dd'
                @($result.Candidates[0].Grammar.DateFormats) | Should -Contain 'MM.dd'
                @($result.Candidates[0].Grammar.DateFormats) | Should -Contain 'dd MMMM'
                @($result.Candidates[0].Grammar.DateFormats) | Should -Contain 'MMM dd'
                @($result.Candidates[0].Grammar.TimeFormats) | Should -Contain 'H:mm'
                @($result.Candidates[0].Grammar.TimeFormats) | Should -Contain 'HH:mm'
                @($result.Candidates[0].Grammar.TimeFormats) | Should -Contain 'h:mm a'
                @($result.Candidates[0].Grammar.TimeFormats) | Should -Contain 'hh:mm a'
                @($result.Candidates[0].Grammar.TimeFormats) | Should -Contain 'h:mma'
                $titleItem = @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '2' })[0]
                $titleItem.EventTitle | Should -Be $case.expected.title
                $expectedSecondStartUtc = ([datetimeoffset]$case.expected.secondStartUtc).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                $titleItem.StartUtc | Should -Be $expectedSecondStartUtc
            }
            elseif ($case.caseId -eq 'day-first-punctuation') {
                $firstItem = @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '1' })[0]
                $firstItem.EventDate | Should -Be $case.expected.firstDate
                @($result.Candidates[0].Grammar.DateFormats) | Should -Contain $case.expected.dateFormat
            }
            elseif ($case.caseId -eq 'explicit-year-formats') {
                $firstItem = @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '1' })[0]
                $firstItem.EventDate | Should -Be $case.expected.firstDate
                @($result.Candidates[0].Grammar.DateFormats) | Should -Contain 'MMM dd, yy'
                @($result.Candidates[0].Grammar.DateFormats) | Should -Contain 'MM/dd/yyyy'
            }
            else {
                $ordinalItem = @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq $case.expected.ordinalText })[0]
                $ordinalItem.ChannelIdentifier | Should -Be $case.expected.identifier
                $ordinalItem.ChannelOrdinal | Should -Be ([int]$case.expected.ordinal)
                $ordinalItem.HomeParticipant | Should -Be $case.expected.homeParticipant
                $ordinalItem.AwayParticipant | Should -Be $case.expected.awayParticipant
                $ordinalSegment = @($result.Candidates[0].Grammar.Segments | Where-Object { $_.Name -eq 'ChannelOrdinal' })[0]
                $ordinalSegment.Width | Should -Be ([int]$case.expected.ordinalWidth)
            }
        }
    }

    It 'requires explicit timezone mappings and cross-checks duplicate zones' {
        $fixture = Read-StageBFixture -Name 'stage-b-timezone-cases.json'
        foreach ($case in @($fixture.cases)) {
            $result = Invoke-StageBFixtureCase -Case $case
            if ($null -ne $case.expected.PSObject.Properties['state']) { $result.OverallState | Should -Be $case.expected.state -Because $case.caseId }
            if ($null -ne $case.expected.PSObject.Properties['crossCheck']) { $result.Candidates[0].TimezoneInterpretation.CrossCheck | Should -Be $case.expected.crossCheck -Because $case.caseId }
            if ($null -ne $case.expected.PSObject.Properties['reason']) { @($result.ReasonCodes) | Should -Contain $case.expected.reason -Because $case.caseId }
            if ($null -ne $case.expected.PSObject.Properties['firstDate']) {
                @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '01' })[0].EventDate | Should -Be $case.expected.firstDate
                $expectedStartUtc = ([datetimeoffset]$case.expected.firstStartUtc).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '01' })[0].StartUtc | Should -Be $expectedStartUtc
            }
        }

        $agreement = Invoke-StageBFixtureCase -Case $fixture.cases[0]
        $agreement.ReviewItems.Count | Should -Be 0
        $agreement.Candidates[0].TimezoneInterpretation.Mappings.ET | Should -Be '-05:00'
        $agreement.Candidates[0].TimezoneInterpretation.Mappings.UK | Should -Be '+00:00'
    }

    It 'returns review states for insufficient, malformed, missing, and outlier evidence' {
        $fixture = Read-StageBFixture -Name 'stage-b-review-cases.json'
        foreach ($case in @($fixture.cases)) {
            $result = Invoke-StageBFixtureCase -Case $case
            $result.OverallState | Should -Be $case.expected.state -Because $case.caseId
            @($result.ReasonCodes) | Should -Contain $case.expected.reason -Because $case.caseId
            $result.CanPublish | Should -BeFalse
            $result.Candidates[0].RequiresReview | Should -BeTrue
        }
    }

    It 'detects drift and never auto-adopts the new candidate' {
        $fixture = Read-StageBFixture -Name 'stage-b-drift-cases.json'
        $baseParameters = @{
            Examples = @($fixture.baselineExamples | ForEach-Object { [string]$_ })
            MinimumExamples = [int]$fixture.minimumExamples
            TimezoneMap = ConvertTo-StageBTimezoneMap -InputObject $fixture.timezoneMap
            ReferenceInstantUtc = [datetimeoffset]$fixture.referenceInstantUtc
            EventType = 'Fight'
        }
        $baseline = Invoke-ChannelForgeGuidePatternInference @baseParameters
        $baselineJson = $baseline.Candidates[0] | ConvertTo-Json -Depth 20
        $driftParameters = @{
            Examples = @($fixture.driftedExamples | ForEach-Object { [string]$_ })
            MinimumExamples = [int]$fixture.minimumExamples
            TimezoneMap = ConvertTo-StageBTimezoneMap -InputObject $fixture.timezoneMap
            ReferenceInstantUtc = [datetimeoffset]$fixture.referenceInstantUtc
            EventType = 'Fight'
            ExistingRule = $baseline.Candidates[0]
        }
        $drift = Invoke-ChannelForgeGuidePatternInference @driftParameters

        $drift.OverallState | Should -Be 'NeedsReview'
        $drift.DriftStatus | Should -Be $fixture.expected.driftStatus
        @($drift.ReasonCodes) | Should -Contain $fixture.expected.reason
        $drift.DriftComparison.Adoption | Should -Be $fixture.expected.adoption
        $drift.PublicationState | Should -Be $fixture.expected.publicationState
        ($baseline.Candidates[0] | ConvertTo-Json -Depth 20) | Should -Be $baselineJson
    }

    It 'uses Stage A evidence provenance, preserves accepted inputs, and excludes mirrors from independence' {
        $accepted = New-ChannelForgeGuideEvidence -EvidenceType AcceptedKnowledge -SourceId accepted-local -SourceFamily local -SourceRelationship Authoritative -ChannelReference event.ufc.01 -DisplayName 'UFC 01: Pereira vs Hill' -Title 'Pereira vs Hill' -EventType Fight -League UFC -Sport MMA -HomeParticipant Pereira -AwayParticipant Hill -StartUtc '2024-04-13T22:00:00Z' -SourceTimezone UTC -ConfidenceState Confirmed -ConfidenceScore 96 -FreshnessState Current
        $independent = New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-independent -SourceFamily xmltv -SourceRelationship Independent -ChannelReference event.ufc.01 -DisplayName 'UFC 01: Pereira vs Hill' -Title 'Pereira vs Hill' -EventType Fight -League UFC -Sport MMA -HomeParticipant Pereira -AwayParticipant Hill -StartUtc '2024-04-13T22:00:00Z' -SourceTimezone UTC -ConfidenceState Confirmed -ConfidenceScore 96 -FreshnessState Current
        $mirror = New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-mirror -SourceFamily xmltv-mirror -SourceRelationship Mirror -ChannelReference event.ufc.01 -DisplayName 'UFC 01: Pereira vs Hill' -Title 'Pereira vs Hill' -EventType Fight -League UFC -Sport MMA -HomeParticipant Pereira -AwayParticipant Hill -StartUtc '2024-04-13T22:00:00Z' -SourceTimezone UTC -ConfidenceState Confirmed -ConfidenceScore 96 -FreshnessState Current
        $accepted.Group = 'ufc-events'
        $independent.Group = 'ufc-events'
        $mirror.Group = 'ufc-events'
        $accepted.EventStatus = 'Live'
        $independent.EventStatus = 'Live'
        $mirror.EventStatus = 'Live'
        $before = $accepted | ConvertTo-Json -Depth 20
        $result = Invoke-ChannelForgeGuidePatternInference -Evidence @($accepted, $independent, $mirror) -MinimumExamples 2
        $after = $accepted | ConvertTo-Json -Depth 20

        $result.OverallState | Should -Be 'Confirmed'
        $result.CrossSourceAssessment.State | Should -Be 'Agreement'
        @($result.CrossSourceAssessment.IndependentSourceIds) | Should -Contain 'accepted-local'
        @($result.CrossSourceAssessment.IndependentSourceIds) | Should -Contain 'guide-independent'
        $result.Candidates[0].Scope.Group | Should -Be 'ufc-events'
        @($result.CrossSourceAssessment.MirrorSourceIds) | Should -Contain 'guide-mirror'
        $result.ExtractionPreview[0].ChannelReference | Should -Be 'event.ufc.01'
        $result.ExtractionPreview[0].StartUtc | Should -Be '2024-04-13T22:00:00Z'
        @($result.ExtractionPreview | ForEach-Object { $_.EventStatus }) | Should -Be @('Live', 'Live', 'Live')
        $after | Should -Be $before
        $result.AcceptedStatePreserved | Should -BeTrue
        $result.AcceptedStateMutation | Should -Be 'None'
        @($result.ReasonCodes) | Should -Contain 'AcceptedKnowledge'
        @($result.ReviewItems | ForEach-Object { $_.Code }) | Should -Not -Contain 'AcceptedKnowledge'
    }

    It 'propagates stale and unavailable source states without publishing' {
        $stale = New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-old -SourceFamily xmltv -ChannelReference event.stale.01 -DisplayName 'UFC 01: Fight Night' -Title 'Fight Night' -EventType Fight -StartUtc '2024-04-13T22:00:00Z' -SourceTimezone UTC -ConfidenceState Confirmed -ConfidenceScore 95 -FreshnessState Stale
        $stalePeer = New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-old-peer -SourceFamily xmltv -ChannelReference event.stale.02 -DisplayName 'UFC 02: Fight Night' -Title 'Fight Night' -EventType Fight -StartUtc '2024-04-20T22:00:00Z' -SourceTimezone UTC -ConfidenceState Confirmed -ConfidenceScore 95 -FreshnessState Current
        $unavailable = New-ChannelForgeGuideEvidence -EvidenceType ScheduleSource -SourceId schedule-down -SourceFamily schedule -ChannelReference event.down.01 -DisplayName 'UFC 01: Fight Night' -Title 'Fight Night' -EventType Fight -StartUtc '2024-04-13T22:00:00Z' -SourceTimezone UTC -ConfidenceState SourceUnavailable -ConfidenceScore 0 -FreshnessState Unavailable
        $unavailablePeer = New-ChannelForgeGuideEvidence -EvidenceType ScheduleSource -SourceId schedule-down-peer -SourceFamily schedule -ChannelReference event.down.02 -DisplayName 'UFC 02: Fight Night' -Title 'Fight Night' -EventType Fight -StartUtc '2024-04-20T22:00:00Z' -SourceTimezone UTC -ConfidenceState SourceUnavailable -ConfidenceScore 0 -FreshnessState Unavailable

        $staleResult = Invoke-ChannelForgeGuidePatternInference -Evidence @($stale, $stalePeer) -MinimumExamples 2
        $unavailableResult = Invoke-ChannelForgeGuidePatternInference -Evidence @($unavailable, $unavailablePeer) -MinimumExamples 2
        $staleResult.OverallState | Should -Be 'StaleSource'
        $unavailableResult.OverallState | Should -Be 'SourceUnavailable'
        $staleResult.CanPublish | Should -BeFalse
        $unavailableResult.CanPublish | Should -BeFalse
    }

    It 'redacts sensitive input before output and does not expose safe text' {
        $fixture = Read-StageBFixture -Name 'stage-b-sensitive-input-cases.json'
        $examples = @($fixture.cases | ForEach-Object {
            $joiner = if ($null -ne $_.PSObject.Properties['joiner']) { [string]$_.joiner } else { '' }
            $_.parts -join $joiner
        })
        $result = Invoke-ChannelForgeGuidePatternInference `
            -Examples $examples `
            -MinimumExamples ([int]$fixture.minimumExamples) `
            -TimezoneMap (ConvertTo-StageBTimezoneMap -InputObject $fixture.timezoneMap) `
            -ReferenceInstantUtc ([datetimeoffset]$fixture.referenceInstantUtc) `
            -EventType Fight
        $privateCase = @($fixture.cases | Where-Object { $_.caseId -eq 'private-path' })[0]
        $privateFileFragment = ([string]$privateCase.parts[3] -split '\s+')[0]
        $unsafeDefaultTimezone = @($privateCase.parts[0..2] + $privateFileFragment) -join ([string]$privateCase.joiner)
        $defaultTimezoneResult = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC 01: Fight // Sat 13 Apr 5:00pm',
                'UFC 02: Fight // Sat 20 Apr 5:00pm'
            ) `
            -DefaultTimezone $unsafeDefaultTimezone `
            -MinimumExamples 2 `
            -ReferenceInstantUtc ([datetimeoffset]$fixture.referenceInstantUtc) `
            -EventType Fight
        $defaultTimezoneJson = $defaultTimezoneResult | ConvertTo-Json -Depth 20
        $defaultTimezoneJson | Should -Not -Match ([regex]::Escape([string]$privateCase.parts[0]))
        $defaultTimezoneJson | Should -Not -Match ([regex]::Escape($privateFileFragment))
        $json = $result | ConvertTo-Json -Depth 20

        foreach ($case in @($fixture.cases)) {
            foreach ($fragment in @($case.forbiddenOutputFragments)) {
                $json | Should -Not -Match ([regex]::Escape([string]$fragment)) -Because $case.caseId
            }
        }
        foreach ($field in @($fixture.expected.redactedFieldsInclude)) {
            @($result.RedactedFields) | Should -Contain $field
        }
        @($result.PSObject.Properties.Name) | Should -Not -Contain 'SafeText'
        $json | Should -Not -Match '(?i)https?://|[A-Z]:[\\/]'
    }
}
