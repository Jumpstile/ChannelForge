BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function New-StageEInference {
        param([string]$ExistingRule = '')
        $params = @{
            Examples = @(
                'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm'
                'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm'
                'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
            )
            EventType = 'Fight'
            TimezoneMap = [ordered]@{ UTC = '+00:00' }
            ReferenceInstantUtc = [datetimeoffset]'2024-04-15T00:00:00Z'
        }
        if (-not [string]::IsNullOrWhiteSpace($ExistingRule)) { $params.ExistingRule = $ExistingRule }
        return Invoke-ChannelForgeGuidePatternInference @params
    }

    function New-BlockedReview {
        param([string]$State)
        $review = Get-ChannelForgeGuidePatternReview -InferenceResult (New-StageEInference)
        $review.Summary.State = $State
        $review.Summary.PlainLanguage = "The supplied result is $State."
        $review.Review.PlainLanguage = "The supplied result is $State."
        $review.Review.Required = $true
        return $review
    }

    function New-VolatileFact {
        param(
            [Parameter(Mandatory)][string]$FactType,
            [Parameter(Mandatory)][string]$SubjectType,
            [Parameter(Mandatory)][string]$SubjectId,
            [string]$SourceId = 'official-stats',
            [string]$SourceType = 'OfficialStats',
            [string]$SourceRelationship = 'Authoritative',
            [string]$FetchedAtUtc = '2024-09-11T19:00:00Z',
            [string]$DataTimestampUtc = '2024-09-11T18:00:00Z',
            [string]$EvaluationInstantUtc = '2024-09-11T20:00:00Z',
            [string]$League = 'NFL',
            [string]$Sport = 'Football',
            [string]$Season = '2024',
            [string]$SeasonPhase = 'RegularSeason',
            [string]$EventSeasonPhase = 'RegularSeason',
            [int]$FreshnessTtlMinutes = 1440,
            [string]$Status = 'Current',
            [string]$FreshnessState = 'Current',
            [string]$ConfidenceState = 'Confirmed',
            [string]$Value = 'current-value',
            [string]$ContradictionGroup = ''
        )
        return [ordered]@{
            FactType = $FactType
            SubjectType = $SubjectType
            SubjectId = $SubjectId
            SourceId = $SourceId
            SourceType = $SourceType
            SourceRelationship = $SourceRelationship
            FetchedAtUtc = $FetchedAtUtc
            DataTimestampUtc = $DataTimestampUtc
            EvaluationInstantUtc = $EvaluationInstantUtc
            League = $League
            Sport = $Sport
            Season = $Season
            SeasonPhase = $SeasonPhase
            EventSeasonPhase = $EventSeasonPhase
            FreshnessTtlMinutes = $FreshnessTtlMinutes
            Status = $Status
            FreshnessState = $FreshnessState
            ConfidenceState = $ConfidenceState
            Value = $Value
            ContradictionGroup = $ContradictionGroup
        }
    }

    function New-VolatilePlan {
        param([Parameter(Mandatory)][object[]]$Facts)
        $league = [string]$Facts[0].League
        $sport = [string]$Facts[0].Sport
        $inference = if (-not [string]::IsNullOrWhiteSpace($league)) {
            Invoke-ChannelForgeGuidePatternInference `
                -Examples @(
                    "$league 01: Event // UTC Sat 13 Apr 5:00pm"
                    "$league 02: Event // UTC Sat 20 Apr 5:00pm"
                    "$league 03: Event // UTC Sat 27 Apr 5:00pm"
                ) `
                -EventType League `
                -League $league `
                -Sport $sport `
                -TimezoneMap ([ordered]@{ UTC = '+00:00' }) `
                -ReferenceInstantUtc ([datetimeoffset]'2024-04-15T00:00:00Z')
        } else {
            New-StageEInference
        }
        $inference.ReferenceInstantUtc = '2024-09-11T20:00:00Z'
        $inference.VolatileFacts = @($Facts)
        return Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference
    }
}

Describe 'Get-ChannelForgeGuidePatternAcceptancePlan' {
    It 'creates an eligible confirmed plan that cannot accept now' {
        $plan = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject (New-StageEInference)

        $plan.Summary.Status | Should -Be 'ELIGIBLE_FOR_FUTURE_ACCEPTANCE'
        $plan.Eligibility.EligibleForFutureAcceptance | Should -BeTrue
        $plan.Eligibility.CanAcceptNow | Should -BeFalse
        $plan.Safety.PlanOnly | Should -BeTrue
        $plan.Safety.CandidateOnly | Should -BeTrue
        $plan.Safety.CanPublish | Should -BeFalse
        $plan.Safety.AcceptedStateMutation | Should -Be 'None'
        $plan.Safety.ProviderMutation | Should -BeFalse
        $plan.Safety.DownstreamMutation | Should -BeFalse
        $plan.Safety.GuidePublication | Should -BeFalse
        $plan.Safety.Adoption | Should -Be 'NotApplied'
        @($plan.RequiredLater).Count | Should -BeGreaterThan 0
        $plan.ProposedFutureRule.RuleId | Should -Match '^pattern-[0-9a-f]{64}$'
    }

    It 'creates the same future-eligible plan for a safe candidate' {
        $review = Get-ChannelForgeGuidePatternReview -InferenceResult (New-StageEInference)
        $review.Summary.State = 'SafeCandidate'
        $plan = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $review

        $plan.Summary.Status | Should -Be 'ELIGIBLE_FOR_FUTURE_ACCEPTANCE'
        $plan.Eligibility.CanAcceptNow | Should -BeFalse
        $plan.ProposedFutureRule.Status | Should -Be 'NotAvailableFromReview'
    }

    It 'blocks review, contradiction, stale, unavailable, and insufficient-example states' {
        foreach ($state in @('NeedsReview', 'Contradiction', 'StaleSource', 'SourceUnavailable')) {
            $plan = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject (New-BlockedReview -State $state)
            $plan.Summary.Status | Should -Be 'BLOCKED'
            $plan.Eligibility.EligibleForFutureAcceptance | Should -BeFalse
            $plan.Eligibility.CanAcceptNow | Should -BeFalse
            $plan.Summary.BlockedReason | Should -Not -BeNullOrEmpty
        }

        $insufficient = New-BlockedReview -State 'NeedsReview'
        $insufficient.Review.PlainLanguage = 'More representative examples are required before this pattern can be trusted.'
        $insufficient.Review.Reasons = @([ordered]@{ Code = 'InsufficientExamples'; Message = 'More representative examples are required before this pattern can be trusted.' })
        $plan = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $insufficient
        $plan.Summary.BlockedReason | Should -Match 'More representative examples'
    }

    It 'creates a drift review-only plan without adoption' {
        $review = Get-ChannelForgeGuidePatternReview -InferenceResult (New-StageEInference)
        $review.Drift.Status = 'Detected'
        $review.Drift.Explanation = 'The naming pattern changed or differs from the baseline.'
        $plan = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $review

        $plan.Summary.Status | Should -Be 'BLOCKED'
        $plan.Drift.ReviewOnly | Should -BeTrue
        $plan.Drift.Adoption | Should -Be 'NotApplied'
        $plan.Safety.Adoption | Should -Be 'NotApplied'
        $plan.Summary.BlockedReason | Should -Match 'drift'
    }

    It 'omits stale NFL preseason statistics from a regular-season plan' {
        $fact = New-VolatileFact `
            -FactType TeamStatistic `
            -SubjectType Team `
            -SubjectId chiefs `
            -League NFL `
            -Sport Football `
            -SeasonPhase Preseason `
            -EventSeasonPhase RegularSeason `
            -DataTimestampUtc '2024-08-01T18:00:00Z' `
            -FetchedAtUtc '2024-08-02T18:00:00Z' `
            -FreshnessTtlMinutes 1440
        $plan = New-VolatilePlan -Facts @($fact)

        $plan.VolatileFacts.Status | Should -Be 'StaleOrReviewNeeded'
        $plan.VolatileFacts.Omitted[0].Decision | Should -Be 'Omitted'
        @($plan.VolatileFacts.Omitted[0].ReasonCodes) | Should -Contain 'VolatileFactStale'
        @($plan.VolatileFacts.Omitted[0].ReasonCodes) | Should -Contain 'SeasonPhaseMismatch'
        $plan.StableIdentity.Pattern.Description | Should -Not -BeNullOrEmpty
    }

    It 'omits a stale prior-day MLB game summary' {
        $fact = New-VolatileFact `
            -FactType GameSummary `
            -SubjectType Game `
            -SubjectId mlb-game-01 `
            -League MLB `
            -Sport Baseball `
            -DataTimestampUtc '2024-09-10T20:00:00Z' `
            -FetchedAtUtc '2024-09-10T20:05:00Z' `
            -EvaluationInstantUtc '2024-09-11T20:00:00Z' `
            -FreshnessTtlMinutes 360
        $plan = New-VolatilePlan -Facts @($fact)

        $plan.VolatileFacts.Status | Should -Be 'StaleOrReviewNeeded'
        $plan.VolatileFacts.Omitted[0].Decision | Should -Be 'Omitted'
        @($plan.VolatileFacts.Omitted[0].ReasonCodes) | Should -Contain 'VolatileFactStale'
        $plan.Eligibility.VolatileFactsCanBePresentedCurrent | Should -BeFalse
    }

    It 'omits stale roster and player facts' {
        $fact = New-VolatileFact `
            -FactType RosterFact `
            -SubjectType Player `
            -SubjectId player-01 `
            -DataTimestampUtc '2024-09-01T12:00:00Z' `
            -FetchedAtUtc '2024-09-01T12:05:00Z' `
            -EvaluationInstantUtc '2024-09-11T20:00:00Z' `
            -FreshnessTtlMinutes 1440
        $plan = New-VolatilePlan -Facts @($fact)

        $plan.VolatileFacts.Status | Should -Be 'StaleOrReviewNeeded'
        $plan.VolatileFacts.Omitted[0].Decision | Should -Be 'Omitted'
        @($plan.VolatileFacts.Omitted[0].ReasonCodes) | Should -Contain 'VolatileFactStale'
    }

    It 'marks volatile facts with missing provenance for review' {
        $fact = New-VolatileFact `
            -FactType PlayerStatistic `
            -SubjectType Player `
            -SubjectId player-02 `
            -SourceId '' `
            -SourceType '' `
            -FetchedAtUtc '' `
            -DataTimestampUtc '' `
            -FreshnessTtlMinutes 0
        $plan = New-VolatilePlan -Facts @($fact)

        $plan.VolatileFacts.Status | Should -Be 'ReviewNeeded'
        $plan.VolatileFacts.Omitted[0].Decision | Should -Be 'ReviewRequired'
        @($plan.VolatileFacts.Omitted[0].ReasonCodes) | Should -Contain 'MissingVolatileProvenance'
        $plan.StableIdentity.ProposedFutureRule.RuleId | Should -Match '^pattern-[0-9a-f]{64}$'
    }

    It 'keeps contradictory volatile facts in review' {
        $first = New-VolatileFact `
            -FactType GameSummary `
            -SubjectType Game `
            -SubjectId mlb-game-02 `
            -League MLB `
            -Sport Baseball `
            -ContradictionGroup mlb-game-02 `
            -Value 'Final 5-3'
        $second = New-VolatileFact `
            -FactType GameSummary `
            -SubjectType Game `
            -SubjectId mlb-game-02 `
            -League MLB `
            -Sport Baseball `
            -SourceId independent-stats `
            -ContradictionGroup mlb-game-02 `
            -Value 'Final 4-3'
        $plan = New-VolatilePlan -Facts @($first, $second)

        $plan.VolatileFacts.Status | Should -Be 'Contradictory'
        @($plan.VolatileFacts.Omitted | ForEach-Object Decision) | Should -Be @('ReviewRequired', 'ReviewRequired')
        @($plan.VolatileFacts.Omitted | ForEach-Object ReasonCodes) | Should -Contain 'ContradictoryVolatileFact'
        $plan.StableIdentity.Pattern.Description | Should -Not -BeNullOrEmpty
    }

    It 'allows a volatile fact only when freshness, context, and provenance are proven' {
        $fact = New-VolatileFact `
            -FactType TeamStatistic `
            -SubjectType Team `
            -SubjectId chiefs
        $plan = New-VolatilePlan -Facts @($fact)

        $plan.VolatileFacts.Status | Should -Be 'Eligible'
        $plan.VolatileFacts.Facts[0].Decision | Should -Be 'EligibleCurrent'
        $plan.Eligibility.VolatileFactsCanBePresentedCurrent | Should -BeTrue
    }

    It 'carries sanitized volatile metadata from Stage A evidence into Stage E' {
        $fact = New-VolatileFact -FactType TeamStatistic -SubjectType Team -SubjectId chiefs
        $evidence = @(
            (New-ChannelForgeGuideEvidence -EvidenceType ScheduleSource -SourceId schedule-a -DisplayName 'NFL 01: Event // UTC Sat 13 Apr 5:00pm' -EventType League -League NFL -Sport Football -ConfidenceState Confirmed -ConfidenceScore 96 -FreshnessState Current -Metadata ([ordered]@{ VolatileFacts = @($fact) }))
            (New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId guide-a -DisplayName 'NFL 02: Event // UTC Sat 20 Apr 5:00pm' -EventType League -League NFL -Sport Football -ConfidenceState Confirmed -ConfidenceScore 96 -FreshnessState Current)
            (New-ChannelForgeGuideEvidence -EvidenceType ProviderDisplayText -SourceId provider-a -DisplayName 'NFL 03: Event // UTC Sat 27 Apr 5:00pm' -EventType League -League NFL -Sport Football -ConfidenceState Confirmed -ConfidenceScore 96 -FreshnessState Current)
        )
        $inference = Invoke-ChannelForgeGuidePatternInference `
            -Evidence $evidence `
            -MinimumExamples 3 `
            -ReferenceInstantUtc ([datetimeoffset]'2024-09-11T20:00:00Z')
        $plan = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference

        @($inference.VolatileFacts).Count | Should -Be 1
        $plan.VolatileFacts.Status | Should -Be 'Eligible'
        $plan.VolatileFacts.Facts[0].Decision | Should -Be 'EligibleCurrent'
    }

    It 'accepts the Stage D review wrapper without changing its safety state' {
        $review = Get-ChannelForgeGuidePatternReview -InferenceResult (New-StageEInference)
        $stageD = [pscustomobject]@{
            State = $review.Summary.State
            Review = $review
            Safety = [ordered]@{ CandidateOnly = $true; CanPublish = $false; AcceptedStateMutation = 'None' }
        }
        $plan = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $stageD

        $plan.Summary.State | Should -Be $review.Summary.State
        $plan.Safety.CandidateOnly | Should -BeTrue
        $plan.Safety.AcceptedStateMutation | Should -Be 'None'
    }

    It 'does not mutate accepted, provider, downstream, or filesystem state' {
        $inference = New-StageEInference
        $before = $inference | ConvertTo-Json -Depth 30 -Compress
        $marker = Join-Path $TestDrive 'state-marker.txt'
        Set-Content -LiteralPath $marker -Value 'unchanged' -NoNewline
        $beforeFiles = @(Get-ChildItem -LiteralPath $TestDrive -Recurse -File | ForEach-Object FullName | Sort-Object)

        $null = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference -OutputFormat Json

        ($inference | ConvertTo-Json -Depth 30 -Compress) | Should -Be $before
        (Get-Content -LiteralPath $marker -Raw) | Should -Be 'unchanged'
        @(Get-ChildItem -LiteralPath $TestDrive -Recurse -File | ForEach-Object FullName | Sort-Object) | Should -Be $beforeFiles
    }

    It 'produces deterministic JSON, distinct Markdown and text, without sensitive values' {
        $inference = New-StageEInference
        $inference.VolatileFacts = @(
            [ordered]@{
                FactType = 'PlayerStatistic'
                SubjectType = 'Player'
                SubjectId = 'player-03'
                SourceId = 'sports-source'
                SourceType = 'OfficialStats'
                SourceRelationship = 'Authoritative'
                FetchedAtUtc = '2024-04-14T18:00:00Z'
                DataTimestampUtc = '2024-04-14T17:00:00Z'
                EvaluationInstantUtc = '2024-04-15T00:00:00Z'
                League = 'NFL'
                Sport = 'Football'
                Season = '2024'
                SeasonPhase = 'RegularSeason'
                EventSeasonPhase = 'RegularSeason'
                FreshnessTtlMinutes = 1440
                Status = 'Current'
                FreshnessState = 'Current'
                ConfidenceState = 'Confirmed'
                Value = 'token=secret-token password=secret-password streamurl=https://secret.example.invalid/live'
            }
        )
        $jsonA = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference -OutputFormat Json
        $jsonB = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference -OutputFormat Json
        $markdownA = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference -OutputFormat Markdown
        $markdownB = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference -OutputFormat Markdown
        $textA = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference -OutputFormat Text
        $textB = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference -OutputFormat Text
        $jsonObject = $jsonA | ConvertFrom-Json

        $jsonA | Should -Be $jsonB
        $markdownA | Should -Be $markdownB
        $textA | Should -Be $textB
        $markdownA | Should -Not -Be $textA
        $markdownA | Should -Match '^# ChannelForge'
        $markdownA | Should -Match '\*\*Status:\*\*'
        $textA | Should -Not -Match '^# '
        $textA | Should -Not -Match '\*\*'
        $jsonA | Should -Not -Match 'UFC 01'
        $markdownA | Should -Not -Match 'UFC 01'
        $textA | Should -Not -Match 'UFC 01'

        # Token, password, and stream-url names in RedactedFields are policy metadata; exact secret values must be absent.
        @($jsonObject.RedactedFields) | Should -Contain 'Token'
        @($jsonObject.RedactedFields) | Should -Contain 'StreamUrl'
        foreach ($secret in @('secret-token', 'secret-password', 'https://secret.example.invalid/live')) {
            $jsonA | Should -Not -Match ([regex]::Escape($secret))
            $markdownA | Should -Not -Match ([regex]::Escape($secret))
            $textA | Should -Not -Match ([regex]::Escape($secret))
        }
        $markdownA | Should -Match 'Can accept now: \*\*false\*\*'
        $textA | Should -Match 'Can accept now: false'
        $textA | Should -Match 'AcceptedStateMutation=None'
    }
}
