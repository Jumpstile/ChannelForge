BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function New-ConfirmedStageCInference {
        return Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm',
                'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm',
                'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
            ) `
            -TimezoneMap ([ordered]@{ UTC = '+00:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z' `
            -EventType Fight `
            -League UFC `
            -Sport MMA
    }

    function New-StageCEvidence {
        param(
            [Parameter(Mandatory)][ValidateSet('AcceptedKnowledge', 'XMLTV', 'ScheduleSource')]
            [string]$EvidenceType,
            [Parameter(Mandatory)][string]$SourceId,
            [Parameter(Mandatory)][ValidateSet('Authoritative', 'Independent', 'Mirror', 'Unknown')]
            [string]$SourceRelationship,
            [Parameter(Mandatory)][ValidateSet('Current', 'Stale', 'Unavailable', 'Unknown')]
            [string]$FreshnessState,
            [Parameter(Mandatory)][ValidateSet('Confirmed', 'SafeCandidate', 'NeedsReview', 'Unresolved', 'Contradiction', 'StaleSource', 'SourceUnavailable')]
            [string]$ConfidenceState,
            [Parameter(Mandatory)][int]$ConfidenceScore
        )
            return New-ChannelForgeGuideEvidence `
                -EvidenceType $EvidenceType `
                -SourceId $SourceId `
                -SourceFamily 'stage-c' `
                -SourceRelationship $SourceRelationship `
                -ChannelReference 'event.ufc.01' `
                -DisplayName 'UFC 01: Fight Night' `
                -Title 'Fight Night' `
                -EventType Fight `
                -League UFC `
                -Sport MMA `
                -StartUtc '2024-04-13T22:00:00Z' `
                -SourceTimezone UTC `
                -ConfidenceState $ConfidenceState `
                -ConfidenceScore $ConfidenceScore `
                -FreshnessState $FreshnessState
        }
}

Describe 'Get-ChannelForgeGuidePatternReview' {
    It 'summarizes a confirmed candidate while keeping publication blocked' {
        $inference = New-ConfirmedStageCInference
        $report = Get-ChannelForgeGuidePatternReview -InferenceResult $inference
        $json = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Json
        $markdown = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Markdown

        $report.ContractVersion | Should -Be 'guide-intelligence/pattern-review/v1'
        $report.Summary.State | Should -Be 'Confirmed'
        $report.Pattern.Description | Should -Match 'Channel names follow'
        @($report.Fields | Where-Object { $_.FieldName -eq 'EventTitle' }).Found | Should -BeTrue
        $report.Event.EventTitle | Should -Be 'Fight Night'
        @('2024-04-13', '2024-04-20', '2024-04-27') | Should -Contain $report.Event.EventDate
        $report.Event.EventTime | Should -Be '5:00pm'
        @($report.Event.EventTimezone) | Should -Contain 'UTC'
        $report.Event.Sport | Should -Be 'MMA'
        $report.Event.League | Should -Be 'UFC'
        $report.Safety.PublicationState | Should -Be 'CandidateOnly'
        $report.Safety.CanPublish | Should -BeFalse
        $report.Safety.PromotionRequired | Should -Be 'ExplicitAcceptance'
        $report.Safety.AcceptedStateMutation | Should -Be 'None'
        $report.NextAction.Blocked | Should -BeTrue
        ($json | ConvertFrom-Json).Safety.CanPublish | Should -BeFalse
        $markdown | Should -Match '# ChannelForge event-pattern review'
        $markdown | Should -Match 'CandidateOnly'
        $markdown | Should -Not -Match '(?i)regex'
    }

    It 'explains needs-review reasons in plain language' {
        $inference = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC 01: Fight Night // ET Sat 13 Apr 5:00pm',
                'UFC 02: Fight Night // ET Sat 20 Apr 99:99pm'
            ) `
            -MinimumExamples 2 `
            -TimezoneMap ([ordered]@{ ET = '-05:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z' `
            -EventType Fight
        $report = Get-ChannelForgeGuidePatternReview -InferenceResult $inference
        $markdown = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Markdown

        $report.Summary.State | Should -Be 'NeedsReview'
        @($report.Review.Reasons | ForEach-Object Code) | Should -Contain 'InvalidTime'
        $report.NextAction.Status | Should -Be 'Review required'
        $report.NextAction.Blocked | Should -BeTrue
        $markdown | Should -Match 'malformed or out of range'
        $report.Safety.CanPublish | Should -BeFalse
    }

    It 'explains contradictions without selecting a winning interpretation' {
        $inference = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC 01: Fight Night // UK Sat 13 Apr 10:00pm // ET Sat 13 Apr 5:00pm',
                'UFC 02: Fight Night // UK Sat 20 Apr 10:00pm // ET Sat 20 Apr 6:00pm'
            ) `
            -MinimumExamples 2 `
            -TimezoneMap ([ordered]@{ UK = '+00:00'; ET = '-05:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z' `
            -EventType Fight
        $report = Get-ChannelForgeGuidePatternReview -InferenceResult $inference
        $markdown = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Markdown

        $report.Summary.State | Should -Be 'Contradiction'
        @($report.Review.Reasons | ForEach-Object Code) | Should -Contain 'EvidenceContradicts'
        $report.NextAction.Action | Should -Match 'Resolve the conflicting evidence'
        $report.NextAction.Blocked | Should -BeTrue
        $markdown | Should -Match 'will not choose one'
        $report.Safety.AcceptedStateMutation | Should -Be 'None'
    }

    It 'keeps stale and unavailable evidence visible without demoting accepted state' {
        $accepted = New-StageCEvidence -EvidenceType AcceptedKnowledge -SourceId accepted-local -SourceRelationship Authoritative -FreshnessState Current -ConfidenceState Confirmed -ConfidenceScore 96
        $stale = New-StageCEvidence -EvidenceType XMLTV -SourceId guide-old -SourceRelationship Independent -FreshnessState Stale -ConfidenceState Confirmed -ConfidenceScore 95
        $unavailable = New-StageCEvidence -EvidenceType ScheduleSource -SourceId schedule-down -SourceRelationship Independent -FreshnessState Unavailable -ConfidenceState SourceUnavailable -ConfidenceScore 0

        $staleReview = Get-ChannelForgeGuidePatternReview -InferenceResult (Invoke-ChannelForgeGuidePatternInference -Evidence @($accepted, $stale) -MinimumExamples 2)
        $unavailableReview = Get-ChannelForgeGuidePatternReview -InferenceResult (Invoke-ChannelForgeGuidePatternInference -Evidence @($accepted, $unavailable) -MinimumExamples 2)

        $staleReview.Summary.State | Should -Be 'StaleSource'
        $unavailableReview.Summary.State | Should -Be 'SourceUnavailable'
        $staleReview.Safety.AcceptedStatePreserved | Should -BeTrue
        $unavailableReview.Safety.AcceptedStatePreserved | Should -BeTrue
        @($staleReview.Provenance.Sources | ForEach-Object SourceId) | Should -Contain 'guide-old'
        @($unavailableReview.Provenance.Sources | ForEach-Object SourceId) | Should -Contain 'schedule-down'
        $staleReview.Safety.AcceptedStateMutation | Should -Be 'None'
        $unavailableReview.Safety.AcceptedStateMutation | Should -Be 'None'
        $staleReview.NextAction.Blocked | Should -BeTrue
        $unavailableReview.NextAction.Blocked | Should -BeTrue
    }

    It 'reports drift as review-only and does not adopt the new pattern' {
        $baseline = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC 00: Fight Night // UTC Sat 13 Apr 5:00pm',
                'UFC 01: Fight Night // UTC Sat 20 Apr 5:00pm',
                'UFC 02: Fight Night // UTC Sat 27 Apr 5:00pm'
            ) `
            -TimezoneMap ([ordered]@{ UTC = '+00:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z' `
            -EventType Fight
        $drifted = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC EVENT 00 - Fight Night // UTC Sat 13 Apr 5:00pm',
                'UFC EVENT 01 - Fight Night // UTC Sat 20 Apr 5:00pm',
                'UFC EVENT 02 - Fight Night // UTC Sat 27 Apr 5:00pm'
            ) `
            -TimezoneMap ([ordered]@{ UTC = '+00:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z' `
            -EventType Fight `
            -ExistingRule $baseline.Candidates[0]
        $report = Get-ChannelForgeGuidePatternReview -InferenceResult $drifted
        $markdown = Get-ChannelForgeGuidePatternReview -InferenceResult $drifted -OutputFormat Markdown

        $report.Drift.Status | Should -Be 'Detected'
        $report.Drift.ReviewOnly | Should -BeTrue
        $report.Drift.Adoption | Should -Be 'NotApplied'
        $report.NextAction.Blocked | Should -BeTrue
        $markdown | Should -Match 'Adoption was not applied'
    }

    It 'excludes sensitive values from JSON and Markdown output' {
        $inference = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC 01: https://example.invalid/REDACTED // UTC Sat 13 Apr 5:00pm',
                'UFC 02: C:\private\provider\guide.json // UTC Sat 20 Apr 5:00pm',
                'UFC 03: Fight Night credential=fixture-credential-value // UTC Sat 27 Apr 5:00pm'
            ) `
            -TimezoneMap ([ordered]@{ UTC = '+00:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z' `
            -EventType Fight
        $report = Get-ChannelForgeGuidePatternReview -InferenceResult $inference
        $json = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Json
        $markdown = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Markdown

        foreach ($text in @($json, $markdown)) {
            $text | Should -Not -Match 'provider\.invalid|fixture-token-value|fixture-credential-value|C:\\private|guide\.json'
            $text | Should -Not -Match '(?i)https?://|[A-Z]:[\\/]'
        }
        @($report.RedactedFields) | Should -Contain 'RawExamples'
        @($report.RedactedFields) | Should -Contain 'RuleId'
        @($report.RedactedFields) | Should -Contain 'SafeText'
    }

    It 'is deterministic for equivalent inference results' {
        $forward = New-ConfirmedStageCInference
        $reverse = Invoke-ChannelForgeGuidePatternInference `
            -Examples @(
                'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm',
                'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm',
                'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm'
            ) `
            -TimezoneMap ([ordered]@{ UTC = '+00:00' }) `
            -ReferenceInstantUtc '2024-04-15T00:00:00Z' `
            -EventType Fight `
            -League UFC `
            -Sport MMA

        $forwardJson = Get-ChannelForgeGuidePatternReview -InferenceResult $forward -OutputFormat Json
        $reverseJson = Get-ChannelForgeGuidePatternReview -InferenceResult $reverse -OutputFormat Json
        $forwardMarkdown = Get-ChannelForgeGuidePatternReview -InferenceResult $forward -OutputFormat Markdown
        $reverseMarkdown = Get-ChannelForgeGuidePatternReview -InferenceResult $reverse -OutputFormat Markdown

        $forwardJson | Should -Be $reverseJson
        $forwardMarkdown | Should -Be $reverseMarkdown
    }

    It 'does not mutate accepted objects or write provider, downstream, or filesystem state' {
        $accepted = New-StageCEvidence -EvidenceType AcceptedKnowledge -SourceId accepted-local -SourceRelationship Authoritative -FreshnessState Current -ConfidenceState Confirmed -ConfidenceScore 96
        $inference = Invoke-ChannelForgeGuidePatternInference -Evidence @($accepted) -MinimumExamples 2
        $beforeAccepted = $accepted | ConvertTo-Json -Depth 20
        $beforeFiles = @(Get-ChildItem -LiteralPath $TestDrive -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)

        $null = Get-ChannelForgeGuidePatternReview -InferenceResult $inference
        $null = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Json
        $null = Get-ChannelForgeGuidePatternReview -InferenceResult $inference -OutputFormat Markdown

        $afterAccepted = $accepted | ConvertTo-Json -Depth 20
        $afterFiles = @(Get-ChildItem -LiteralPath $TestDrive -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
        $afterAccepted | Should -Be $beforeAccepted
        $afterFiles | Should -Be $beforeFiles
        $report = Get-ChannelForgeGuidePatternReview -InferenceResult $inference
        $report.Safety.ProviderMutation | Should -BeFalse
        $report.Safety.DownstreamMutation | Should -BeFalse
        $report.Safety.FilesystemMutation | Should -BeFalse
        $report.Safety.AcceptedStateMutation | Should -Be 'None'
    }
}
