class GuideEventPatternRule {
    [string]$ContractVersion
    [string]$RuleId
    [int]$RuleVersion
    [string]$CreatedUtc
    [string]$ValidatedUtc
    [string]$LastSuccessfulValidationUtc
    [object]$Scope
    [object]$Grammar
    [object[]]$FieldCandidates
    [object]$TimezoneInterpretation
    [object[]]$EvidenceReferences
    [string]$ConfidenceState
    [int]$ConfidenceScore
    [string]$DriftStatus
    [string]$BaselineRuleId
    [object]$DriftComparison
    [object]$CrossSourceAssessment
    [string[]]$ReasonCodes
    [bool]$RequiresReview
    [string]$PublicationState
    [string]$PromotionRequired
    [bool]$CanPublish
    [bool]$AcceptedStateChanged
    [bool]$ReadOnly

    GuideEventPatternRule() {
        $this.ContractVersion = 'guide-intelligence/pattern/v1'
        $this.RuleId = ''
        $this.RuleVersion = 1
        $this.Scope = [ordered]@{}
        $this.CreatedUtc = ''
        $this.ValidatedUtc = ''
        $this.LastSuccessfulValidationUtc = ''
        $this.Grammar = [ordered]@{}
        $this.FieldCandidates = @()
        $this.TimezoneInterpretation = [ordered]@{}
        $this.EvidenceReferences = @()
        $this.ConfidenceState = 'Unresolved'
        $this.ConfidenceScore = 0
        $this.DriftStatus = 'NotEvaluated'
        $this.BaselineRuleId = ''
        $this.DriftComparison = [ordered]@{}
        $this.CrossSourceAssessment = [ordered]@{}
        $this.ReasonCodes = @()
        $this.RequiresReview = $true
        $this.PublicationState = 'CandidateOnly'
        $this.PromotionRequired = 'ExplicitAcceptance'
        $this.CanPublish = $false
        $this.AcceptedStateChanged = $false
        $this.ReadOnly = $true
    }
}
