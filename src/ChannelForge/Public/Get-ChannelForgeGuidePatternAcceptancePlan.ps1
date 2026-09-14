function Get-ChannelForgeGuidePatternAcceptancePlan {
    <#
    .SYNOPSIS
    Creates a deterministic, read-only plan describing a possible future event-pattern acceptance.

    .DESCRIPTION
    Consumes a Stage B inference result or Stage C review report. The plan explains
    eligibility and safety boundaries without accepting, adopting, publishing, or
    mutating provider, downstream, guide, or accepted state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [object]$InputObject,

        [ValidateSet('Object', 'Json', 'Markdown', 'Text')]
        [string]$OutputFormat = 'Object'
    )

    if ($null -eq $InputObject) { throw 'InputObject cannot be null.' }

    $nestedReview = Get-ChannelForgeGuidePatternReviewProperty -InputObject $InputObject -Name 'Review'
    $review = if ($InputObject -is [GuidePatternReviewReport]) {
        $InputObject
    } elseif ($null -ne $nestedReview -and $null -ne (Get-ChannelForgeGuidePatternReviewProperty -InputObject $nestedReview -Name 'Summary')) {
        $nestedReview
    } else {
        ConvertTo-ChannelForgeGuidePatternReviewReport -InferenceResult $InputObject
    }

    $state = [string]$review.Summary.State
    $drift = [string]$review.Drift.Status
    $blockedStates = @('NeedsReview', 'Unresolved', 'Contradiction', 'StaleSource', 'SourceUnavailable')
    $driftOnly = $drift -eq 'Detected'
    $eligible = $state -in @('Confirmed', 'SafeCandidate') -and -not $driftOnly
    $blocked = -not $eligible

    $reason = if ($driftOnly) {
        'Pattern drift requires review; adoption remains not applied.'
    } elseif ($state -eq 'Confirmed' -or $state -eq 'SafeCandidate') {
        ''
    } elseif ($state -in $blockedStates) {
        [string]$review.Review.PlainLanguage
    } else {
        'The event pattern is not eligible for a future acceptance plan.'
    }

    $candidate = if ($InputObject -is [GuidePatternReviewReport] -or $null -ne $nestedReview) {
        $null
    } else {
        Get-ChannelForgeGuidePatternReviewProperty -InputObject $InputObject -Name 'SelectedCandidate'
    }
    $rawRuleId = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $candidate -Name 'RuleId')
    $rawBaselineRuleId = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $candidate -Name 'BaselineRuleId')
    $ruleId = if ($rawRuleId -match '^pattern-[0-9a-f]{64}$') { $rawRuleId } else { '' }
    $baselineRuleId = if ($rawBaselineRuleId -match '^pattern-[0-9a-f]{64}$') { $rawBaselineRuleId } else { '' }
    $identityAvailable = -not [string]::IsNullOrWhiteSpace($ruleId)
    $proposedRule = [ordered]@{
        Status = if ($eligible -and $identityAvailable) { 'ProposedOnly' } elseif ($eligible) { 'NotAvailableFromReview' } else { 'NotProposed' }
        RuleId = $ruleId
        RuleVersion = if ($eligible -and $identityAvailable) { 1 } else { $null }
        BaselineRuleId = $baselineRuleId
        IdentityReason = if ($identityAvailable) { '' } else { 'Stage C/D review output intentionally omits candidate hashes; direct Stage B input is required for the proposed identity.' }
        Adoption = 'NotApplied'
    }

    $volatileFacts = Get-ChannelForgeGuidePatternReviewProperty -InputObject $review -Name 'VolatileFacts'
    if ($null -eq $volatileFacts -or $null -eq (Get-ChannelForgeGuidePatternReviewProperty -InputObject $volatileFacts -Name 'Status')) {
        $volatileFacts = Resolve-ChannelForgeGuideVolatileFacts `
            -Facts @((Get-ChannelForgeGuidePatternReviewProperty -InputObject $InputObject -Name 'VolatileFacts')) `
            -EventStartUtc ([string]$review.Event.CanonicalStartUtc) `
            -EventTimezone ([string]($review.Event.EventTimezone -join ',')) `
            -League ([string]$review.Event.League) `
            -Sport ([string]$review.Event.Sport) `
            -EvaluationInstantUtc ([string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $InputObject -Name 'ReferenceInstantUtc'))
    }
    $volatileStatus = [string](Get-ChannelForgeGuidePatternReviewProperty -InputObject $volatileFacts -Name 'Status')
    $volatileSafeForCurrent = $volatileStatus -in @('NotProvided', 'Eligible')
    $volatileSummary = if ($volatileSafeForCurrent) {
        'Stable title, time, and pattern identity are evaluated separately from volatile enrichment.'
    } else {
        'Volatile enrichment is omitted or marked for review; stable title, time, and pattern identity remain separate.'
    }


    $plan = [ordered]@{
        Version = 'guide-intelligence/pattern-acceptance-plan/v1'
        PlanType = 'FutureEventPatternAcceptance'
        Summary = [ordered]@{
            State = $state
            Status = if ($eligible) { 'ELIGIBLE_FOR_FUTURE_ACCEPTANCE' } else { 'BLOCKED' }
            BeginnerSummary = if ($eligible) { "This event pattern could be considered for acceptance later, after explicit review and acceptance. $volatileSummary" } else { "This event pattern cannot be considered for acceptance until the stated issue is resolved. $volatileSummary" }
            BlockedReason = $reason
        }
        StableIdentity = [ordered]@{
            Pattern = $review.Pattern
            Event = $review.Event
            ProposedFutureRule = $proposedRule
        }
        Pattern = $review.Pattern
        MatchedExamples = [ordered]@{
            Total = $review.ExampleCount
            Matched = $review.MatchedExampleCount
            Representative = $review.Event
        }
        Confidence = $review.Confidence
        Review = $review.Review
        Provenance = $review.Provenance
        Freshness = @($review.Provenance.Sources | ForEach-Object { [ordered]@{ SourceId = $_.SourceId; SourceFamily = $_.SourceFamily; Relationship = $_.Relationship; FreshnessState = $_.FreshnessState } })
        Drift = [ordered]@{
            Status = $drift
            ReviewOnly = $true
            Adoption = 'NotApplied'
            Explanation = if ($driftOnly) { 'The observed naming structure differs from the baseline; no rule adoption is applied.' } else { [string]$review.Drift.Explanation }
        }
        VolatileFacts = $volatileFacts
        ProposedFutureRule = $proposedRule
        Eligibility = [ordered]@{
            EligibleForFutureAcceptance = $eligible
            Blocked = $blocked
            CanAcceptNow = $false
            VolatileFactsEligible = $volatileSafeForCurrent
            VolatileFactsCanBePresentedCurrent = $volatileStatus -eq 'Eligible'
            Reason = $reason
        }
        Safety = [ordered]@{
            PlanOnly = $true
            CandidateOnly = $true
            PublicationState = 'CandidateOnly'
            CanPublish = $false
            CanAcceptNow = $false
            AcceptedStateMutation = 'None'
            ProviderMutation = $false
            DownstreamMutation = $false
            GuidePublication = $false
            FilesystemMutation = $false
            Adoption = 'NotApplied'
            RedactionApplied = $true
            SafetyBoundary = 'Review evidence only. Explicit acceptance and the existing publication boundary would still be required later.'
        }
        RequiredLater = @(
            'A person must review the evidence and confirm the proposed rule.'
            'An explicit acceptance action must occur through the existing acceptance boundary.'
            'Future implementation must revalidate source freshness, drift, candidate identity, and accepted parent state.'
            'Volatile facts must be revalidated for freshness, season context, provenance, and contradiction before any later presentation as current.'
        )
        ReadOnly = $true
        RedactedFields = @($review.RedactedFields | Sort-Object -Unique)
    }

    if ($OutputFormat -eq 'Json') {
        return ($plan | ConvertTo-Json -Depth 30 -Compress)
    }

    if ($OutputFormat -eq 'Markdown') {
        $lines = [System.Collections.Generic.List[string]]::new()
        [void]$lines.Add('# ChannelForge future event-pattern acceptance plan')
        [void]$lines.Add('')
        [void]$lines.Add(('**Status:** {0}' -f $plan.Summary.Status))
        [void]$lines.Add(('**Summary:** {0}' -f $plan.Summary.BeginnerSummary))
        [void]$lines.Add('')
        [void]$lines.Add('## Stable pattern identity')
        [void]$lines.Add('')
        [void]$lines.Add([string]$plan.Pattern.Description)
        [void]$lines.Add(('Matched examples: **{0} of {1}**.' -f $plan.MatchedExamples.Matched, $plan.MatchedExamples.Total))
        [void]$lines.Add(('Confidence: **{0}** ({1}/100).' -f $plan.Confidence.State, $plan.Confidence.Score))
        [void]$lines.Add(('Future rule identity: **{0}**.' -f $plan.ProposedFutureRule.Status))
        [void]$lines.Add(('Review state: {0}.' -f $plan.Review.PlainLanguage))
        [void]$lines.Add(('Drift: **{0}**; adoption: **NotApplied**.' -f $plan.Drift.Status))
        [void]$lines.Add('')
        [void]$lines.Add('## Volatile enrichment')
        [void]$lines.Add('')
        [void]$lines.Add(('Status: **{0}**.' -f $plan.VolatileFacts.Status))
        [void]$lines.Add(('Eligible current facts: {0}; omitted or review-needed facts: {1}.' -f $plan.VolatileFacts.EligibleCount, $plan.VolatileFacts.OmittedCount))
        [void]$lines.Add([string]$plan.VolatileFacts.Explanation)
        [void]$lines.Add('')
        [void]$lines.Add('## Eligibility')
        [void]$lines.Add('')
        [void]$lines.Add(('Eligible for future acceptance: **{0}**.' -f $plan.Eligibility.EligibleForFutureAcceptance.ToString().ToLowerInvariant()))
        [void]$lines.Add('Can accept now: **false**.')
        if (-not [string]::IsNullOrWhiteSpace($plan.Summary.BlockedReason)) { [void]$lines.Add(('Blocked reason: {0}' -f $plan.Summary.BlockedReason)) }
        [void]$lines.Add('')
        [void]$lines.Add('## Safety boundary')
        [void]$lines.Add('')
        [void]$lines.Add('Plan only; CandidateOnly; CanPublish=false; CanAcceptNow=false.')
        [void]$lines.Add('AcceptedStateMutation=None; ProviderMutation=false; DownstreamMutation=false; GuidePublication=false; Adoption=NotApplied.')
        [void]$lines.Add('Redaction applied to raw examples, source values, and volatile values.')
        [void]$lines.Add('')
        [void]$lines.Add('## What would still be required later')
        [void]$lines.Add('')
        foreach ($item in @($plan.RequiredLater)) { [void]$lines.Add(('- {0}' -f $item)) }
        [void]$lines.Add('')
        [void]$lines.Add('_This plan is review evidence only. It does not accept, adopt, publish, or mutate state._')
        return ($lines -join "`n")
    }

    if ($OutputFormat -eq 'Text') {
        $lines = [System.Collections.Generic.List[string]]::new()
        [void]$lines.Add('ChannelForge future event-pattern acceptance plan')
        [void]$lines.Add('')
        [void]$lines.Add(('Status: {0}' -f $plan.Summary.Status))
        [void]$lines.Add(('Summary: {0}' -f $plan.Summary.BeginnerSummary))
        [void]$lines.Add('')
        [void]$lines.Add('Stable pattern identity')
        [void]$lines.Add('------------------------')
        [void]$lines.Add([string]$plan.Pattern.Description)
        [void]$lines.Add(('Matched examples: {0} of {1}.' -f $plan.MatchedExamples.Matched, $plan.MatchedExamples.Total))
        [void]$lines.Add(('Confidence: {0} ({1}/100).' -f $plan.Confidence.State, $plan.Confidence.Score))
        [void]$lines.Add(('Future rule identity: {0}.' -f $plan.ProposedFutureRule.Status))
        [void]$lines.Add(('Review state: {0}.' -f $plan.Review.PlainLanguage))
        [void]$lines.Add(('Drift: {0}; adoption: NotApplied.' -f $plan.Drift.Status))
        [void]$lines.Add('')
        [void]$lines.Add('Volatile enrichment')
        [void]$lines.Add('-------------------')
        [void]$lines.Add(('Status: {0}.' -f $plan.VolatileFacts.Status))
        [void]$lines.Add(('Eligible current facts: {0}; omitted or review-needed facts: {1}.' -f $plan.VolatileFacts.EligibleCount, $plan.VolatileFacts.OmittedCount))
        [void]$lines.Add([string]$plan.VolatileFacts.Explanation)
        [void]$lines.Add('')
        [void]$lines.Add('Eligibility')
        [void]$lines.Add('-----------')
        [void]$lines.Add(('Eligible for future acceptance: {0}.' -f $plan.Eligibility.EligibleForFutureAcceptance.ToString().ToLowerInvariant()))
        [void]$lines.Add('Can accept now: false.')
        if (-not [string]::IsNullOrWhiteSpace($plan.Summary.BlockedReason)) { [void]$lines.Add(('Blocked reason: {0}' -f $plan.Summary.BlockedReason)) }
        [void]$lines.Add('')
        [void]$lines.Add('Safety boundary')
        [void]$lines.Add('---------------')
        [void]$lines.Add('Plan only; CandidateOnly; CanPublish=false; CanAcceptNow=false.')
        [void]$lines.Add('AcceptedStateMutation=None; ProviderMutation=false; DownstreamMutation=false; GuidePublication=false; Adoption=NotApplied.')
        [void]$lines.Add('Redaction applied to raw examples, source values, and volatile values.')
        [void]$lines.Add('')
        [void]$lines.Add('What would still be required later')
        [void]$lines.Add('-----------------------------------')
        foreach ($item in @($plan.RequiredLater)) { [void]$lines.Add(('  * {0}' -f $item)) }
        [void]$lines.Add('')
        [void]$lines.Add('This plan is review evidence only. It does not accept, adopt, publish, or mutate state.')
        return ($lines -join "`n")
    }

    return $plan
}
