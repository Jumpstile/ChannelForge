class GuidePatternReviewReport {
    [string]$ContractVersion
    [string]$ReportType
    [object]$Summary
    [object]$Pattern
    [object[]]$Fields
    [object]$Event
    [object]$Confidence
    [object]$Review
    [object]$Drift
    [object]$Provenance
    [object]$VolatileFacts
    [object]$Safety
    [object]$NextAction
    [int]$ExampleCount
    [int]$MatchedExampleCount
    [bool]$ReadOnly
    [string[]]$RedactedFields

    GuidePatternReviewReport() {
        $this.ContractVersion = 'guide-intelligence/pattern-review/v1'
        $this.ReportType = 'BeginnerEventPatternReview'
        $this.Summary = [ordered]@{}
        $this.Pattern = [ordered]@{}
        $this.Fields = @()
        $this.Event = [ordered]@{}
        $this.Confidence = [ordered]@{}
        $this.Review = [ordered]@{}
        $this.Drift = [ordered]@{}
        $this.Provenance = [ordered]@{}
        $this.VolatileFacts = [ordered]@{}
        $this.Safety = [ordered]@{}
        $this.NextAction = [ordered]@{}
        $this.ExampleCount = 0
        $this.MatchedExampleCount = 0
        $this.ReadOnly = $true
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
            'RawExamples'
            'RuleId'
            'VolatileValue'
        )
    }
}
