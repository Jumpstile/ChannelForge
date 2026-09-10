class GuidePatternFieldCandidate {
    [string]$ContractVersion
    [string]$FieldName
    [string]$ExtractionKind
    [string]$Format
    [string]$TimezoneLabel
    [bool]$Required
    [int]$ObservedCount
    [int]$ExampleCount
    [int]$ConfidenceScore
    [string]$ConfidenceState
    [string[]]$ExampleOrdinals
    [string[]]$ReasonCodes
    [object[]]$Provenance
    [bool]$ReadOnly

    GuidePatternFieldCandidate() {
        $this.ContractVersion = 'guide-intelligence/pattern-field/v1'
        $this.FieldName = ''
        $this.ExtractionKind = ''
        $this.Format = ''
        $this.TimezoneLabel = ''
        $this.Required = $false
        $this.ObservedCount = 0
        $this.ExampleCount = 0
        $this.ConfidenceScore = 0
        $this.ConfidenceState = 'Unresolved'
        $this.ExampleOrdinals = @()
        $this.ReasonCodes = @()
        $this.Provenance = @()
        $this.ReadOnly = $true
    }
}
