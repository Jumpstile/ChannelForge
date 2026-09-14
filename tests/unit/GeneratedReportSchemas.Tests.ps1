BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    $script:ReviewSchema = Join-Path $script:RepoRoot 'schemas\guide-pattern-review.schema.json'
    $script:PreviewSchema = Join-Path $script:RepoRoot 'schemas\guided-event-pattern-preview.schema.json'
    $script:SummarySchema = Join-Path $script:RepoRoot 'schemas\guided-setup-summary.schema.json'
    $script:AcceptancePlanSchema = Join-Path $script:RepoRoot 'schemas\guide-pattern-acceptance-plan.schema.json'
    $script:WorkflowPath = Join-Path $script:RepoRoot 'scripts\Build-My-Lineup.ps1'
    $script:PlaylistFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\playlist.m3u'

    function New-InferenceFixture {
        param([string[]]$Examples = @(
                'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm'
                'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm'
                'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
            ))

        return Invoke-ChannelForgeGuidePatternInference `
            -Examples $Examples `
            -EventType Fight `
            -TimezoneMap ([ordered]@{ UTC = '+00:00' }) `
            -ReferenceInstantUtc ([datetimeoffset]'2024-04-15T00:00:00Z')
    }

    function Assert-JsonSchemaValid {
        param(
            [Parameter(Mandatory)][string]$Json,
            [Parameter(Mandatory)][string]$Schema
        )

        Test-Json -Json $Json -SchemaFile $Schema | Should -BeTrue
    }

    function Test-JsonSchemaValid {
        param(
            [Parameter(Mandatory)][string]$Json,
            [Parameter(Mandatory)][string]$Schema
        )

        try {
            return [bool](Test-Json -Json $Json -SchemaFile $Schema -ErrorAction Stop)
        }
        catch {
            return $false
        }
    }

    function New-GuidedSetupRoot {
        param([Parameter(Mandatory)][string]$Name)

        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data\rules'), (Join-Path $root 'data\lineup') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\rules\aliases.json') -Destination (Join-Path $root 'data\rules\aliases.json')
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\lineup\numbering_blocks.json') -Destination (Join-Path $root 'data\lineup\numbering_blocks.json')
        return $root
    }

    function New-SafeVolatileAssessment {
        param(
            [ValidateSet('EligibleCurrent', 'Omitted', 'ReviewRequired')][string]$Decision,
            [ValidateSet('Current', 'Stale', 'Unavailable', 'Contradictory', 'Unknown')][string]$Status = 'Stale'
        )

        return [ordered]@{
            FactId = 'fact-01'
            FactType = 'TeamStatistic'
            SubjectType = 'Team'
            SubjectId = 'team-01'
            SourceId = 'official-stats'
            SourceType = 'OfficialStats'
            SourceRelationship = 'Authoritative'
            FetchedAtUtc = '2024-09-11T19:00:00Z'
            DataTimestampUtc = '2024-09-11T18:00:00Z'
            EvaluationInstantUtc = '2024-09-11T20:00:00Z'
            EventStartUtc = '2024-09-11T20:00:00Z'
            EventTimezone = 'UTC'
            ValidFromUtc = ''
            ValidToUtc = ''
            Season = '2024'
            SeasonPhase = 'RegularSeason'
            EventSeasonPhase = 'RegularSeason'
            Week = '1'
            Round = ''
            Competition = 'NFL'
            League = 'NFL'
            Sport = 'Football'
            FreshnessState = if ($Status -eq 'Stale') { 'Stale' } else { 'Current' }
            FreshnessTtlMinutes = 1440
            ConfidenceState = if ($Decision -eq 'ReviewRequired') { 'NeedsReview' } else { 'Confirmed' }
            Status = $Status
            ContradictionGroup = ''
            Decision = $Decision
            ReasonCodes = @(if ($Decision -eq 'EligibleCurrent') { @() } else { @('VolatileFactStale') })
        }
    }
}

Describe 'Generated report JSON schemas' {
    It 'validates Stage C review JSON and preserves deterministic output' {
        $inference = New-InferenceFixture
        $first = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Json
        $second = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Json

        Assert-JsonSchemaValid -Json $first -Schema $script:ReviewSchema
        $first | Should -Be $second
        $review = $first | ConvertFrom-Json
        $review.Safety.PublicationState | Should -Be 'CandidateOnly'
        $review.Safety.CanPublish | Should -BeFalse
        $review.Safety.AcceptedStateMutation | Should -Be 'None'
        $review.Safety.ProviderMutation | Should -BeFalse
        $review.Safety.DownstreamMutation | Should -BeFalse
        $review.Safety.FilesystemMutation | Should -BeFalse
        $review.ReadOnly | Should -BeTrue
    }

    It 'validates Stage D preview JSON and Guided Setup summary JSON' {
        $root = New-GuidedSetupRoot -Name 'schema-preview'
        & $script:WorkflowPath `
            -Root $root `
            -M3UPath $script:PlaylistFixture `
            -EventPatternPreview `
            -EventPatternExamples @(
                'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm'
                'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm'
                'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
            ) `
            -EventPatternType Fight `
            -EventPatternReferenceInstantUtc '2024-04-15T00:00:00Z' | Out-Null

        $summaryJson = Get-Content -LiteralPath (Join-Path $root 'output\reports\guided-setup-summary.json') -Raw
        $previewJson = Get-Content -LiteralPath (Join-Path $root 'output\reports\guided-event-pattern-preview.json') -Raw
        Assert-JsonSchemaValid -Json $summaryJson -Schema $script:SummarySchema
        Assert-JsonSchemaValid -Json $previewJson -Schema $script:PreviewSchema

        $summary = $summaryJson | ConvertFrom-Json
        $preview = $previewJson | ConvertFrom-Json
        $summary.EventPatternPreview.Safety.CanPublish | Should -BeFalse
        $summary.EventPatternPreview.Safety.AcceptedStateMutation | Should -Be 'None'
        $preview.Safety.PublicationState | Should -Be 'CandidateOnly'
        $preview.Safety.PromotionRequired | Should -Be 'ExplicitAcceptance'
        $preview.Safety.ProviderMutation | Should -BeFalse
        $preview.Safety.DownstreamMutation | Should -BeFalse
        $preview.Safety.FilesystemMutation | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'validates Stage E direct identity and Stage C/D hash-redacted identity states' {
        $inference = New-InferenceFixture
        $directJson = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $inference -OutputFormat Json
        Assert-JsonSchemaValid -Json $directJson -Schema $script:AcceptancePlanSchema
        $direct = $directJson | ConvertFrom-Json
        $direct.ProposedFutureRule.Status | Should -Be 'ProposedOnly'
        $direct.ProposedFutureRule.RuleId | Should -Match '^pattern-[0-9a-f]{64}$'

        $reviewJson = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Json
        $review = Get-ChannelForgeGuidePatternReview -InferenceResult $inference
        $reviewPlanJson = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $review -OutputFormat Json
        Assert-JsonSchemaValid -Json $reviewPlanJson -Schema $script:AcceptancePlanSchema
        $reviewPlan = $reviewPlanJson | ConvertFrom-Json
        $reviewPlan.ProposedFutureRule.Status | Should -Be 'NotAvailableFromReview'
        $reviewPlan.ProposedFutureRule.RuleId | Should -BeNullOrEmpty
        $reviewPlanJson | Should -Not -Match 'pattern-[0-9a-f]{64}'
    }

    It 'requires invariant safety fields and rejects unsafe values' {
        $reviewJson = Get-ChannelForgeGuidePatternReview -InferenceResult (New-InferenceFixture) -OutputFormat Json
        $review = $reviewJson | ConvertFrom-Json
        $review.Safety.CanPublish = $true
        $unsafe = $review | ConvertTo-Json -Depth 30 -Compress
        (Test-JsonSchemaValid -Json $unsafe -Schema $script:ReviewSchema) | Should -BeFalse

        $planJson = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject (New-InferenceFixture) -OutputFormat Json
        $plan = $planJson | ConvertFrom-Json
        $plan.Safety.PSObject.Properties.Remove('CanPublish')
        $missing = $plan | ConvertTo-Json -Depth 30 -Compress
        (Test-JsonSchemaValid -Json $missing -Schema $script:AcceptancePlanSchema) | Should -BeFalse
    }

    It 'keeps sensitive values out of validated Stage C and Stage D JSON' {
        $sensitiveExamples = @(
            'UFC 01: https://example.invalid/REDACTED // UTC Sat 13 Apr 5:00pm'
            'UFC 02: C:\private\provider\guide.json // UTC Sat 20 Apr 5:00pm'
            'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
        )
        $reviewJson = Get-ChannelForgeGuidePatternReview -InferenceResult (New-InferenceFixture -Examples $sensitiveExamples) -OutputFormat Json
        Assert-JsonSchemaValid -Json $reviewJson -Schema $script:ReviewSchema
        $reviewJson | Should -Not -Match 'fixture-token|C:\\private|https?://'
        @('Url', 'StreamUrl', 'Token', 'PrivatePath', 'RawExamples') | ForEach-Object {
            ($reviewJson | ConvertFrom-Json).RedactedFields | Should -Contain $_
        }
    }

    It 'validates volatile statuses and rejects current decisions under degraded status' {
        $plan = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject (New-InferenceFixture) -OutputFormat Json | ConvertFrom-Json
        foreach ($status in @('NotProvided', 'Contradictory', 'SourceUnavailable', 'StaleOrReviewNeeded', 'ReviewNeeded')) {
            $plan.VolatileFacts.Status = $status
            $plan.VolatileFacts.Total = 0
            $plan.VolatileFacts.EligibleCount = 0
            $plan.VolatileFacts.OmittedCount = 0
            $plan.VolatileFacts.Facts = @()
            $plan.VolatileFacts.Omitted = @()
            Assert-JsonSchemaValid -Json ($plan | ConvertTo-Json -Depth 30 -Compress) -Schema $script:AcceptancePlanSchema
        }

        $staleFact = New-SafeVolatileAssessment -Decision Omitted -Status Stale
        $sourceInference = New-InferenceFixture
        $sourceInference.ReferenceInstantUtc = '2024-09-11T20:00:00Z'
        $sourceInference.VolatileFacts = @($staleFact)
        $sourceJson = Get-ChannelForgeGuidePatternAcceptancePlan -InputObject $sourceInference -OutputFormat Json
        $sourcePlan = $sourceJson | ConvertFrom-Json
        Assert-JsonSchemaValid -Json $sourceJson -Schema $script:AcceptancePlanSchema
        ($sourcePlan.VolatileFacts.Omitted[0].ReasonCodes -is [array]) | Should -BeTrue

        $plan.VolatileFacts.Status = 'StaleOrReviewNeeded'
        $plan.VolatileFacts.Total = 1
        $plan.VolatileFacts.OmittedCount = 1
        $plan.VolatileFacts.Facts = @($staleFact)
        $plan.VolatileFacts.Omitted = @($staleFact)
        Assert-JsonSchemaValid -Json ($plan | ConvertTo-Json -Depth 30 -Compress) -Schema $script:AcceptancePlanSchema

        $staleFact.Decision = 'EligibleCurrent'
        $invalidCurrent = $plan | ConvertTo-Json -Depth 30 -Compress
        (Test-JsonSchemaValid -Json $invalidCurrent -Schema $script:AcceptancePlanSchema) | Should -BeFalse
    }
}
