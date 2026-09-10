class GuidePatternInferenceResult {
    [string]$ContractVersion
    [string]$InferenceMethod
    [string]$InferenceStatus
    [string]$OverallState
    [object[]]$Candidates
    [object]$SelectedCandidate
    [object[]]$ExtractionPreview
    [object[]]$Examples
    [object[]]$ReviewItems
    [object[]]$Provenance
    [int]$ExampleCount
    [int]$MatchedExampleCount
    [int]$ConfidenceScore
    [string]$ConfidenceState
    [string]$DriftStatus
    [string]$BaselineRuleId
    [object]$DriftComparison
    [object]$CrossSourceAssessment
    [bool]$ReadOnly
    [string]$PublicationState
    [string]$PromotionRequired
    [bool]$CanPublish
    [bool]$AcceptedStatePreserved
    [string]$AcceptedStateMutation
    [string[]]$ReasonCodes
    [string[]]$RedactedFields

    GuidePatternInferenceResult() {
        $this.ContractVersion = 'guide-intelligence/pattern-result/v1'
        $this.InferenceMethod = 'NativeEventPattern'
        $this.InferenceStatus = 'EvidenceOnly'
        $this.OverallState = 'Unresolved'
        $this.Candidates = @()
        $this.SelectedCandidate = $null
        $this.ExtractionPreview = @()
        $this.Examples = @()
        $this.ReviewItems = @()
        $this.Provenance = @()
        $this.ExampleCount = 0
        $this.MatchedExampleCount = 0
        $this.ConfidenceScore = 0
        $this.ConfidenceState = 'Unresolved'
        $this.DriftStatus = 'NotEvaluated'
        $this.BaselineRuleId = ''
        $this.DriftComparison = [ordered]@{}
        $this.CrossSourceAssessment = [ordered]@{}
        $this.ReadOnly = $true
        $this.PublicationState = 'CandidateOnly'
        $this.PromotionRequired = 'ExplicitAcceptance'
        $this.CanPublish = $false
        $this.AcceptedStatePreserved = $false
        $this.AcceptedStateMutation = 'None'
        $this.RedactedFields = @(
            'Url'
            'StreamUrl'
            'Credential'
            'Token'
            'PrivatePath'
            'ParserError'
            'CandidateHash'
            'GenerationId'
            'SafeText'
        )
    }
}
