class GuideReadinessRecord {
    [string]$ContractVersion
    [string]$ChannelReference
    [string]$EventType
    [string]$Title
    [string]$ReadinessState
    [string]$PublicationState
    [string]$PromotionRequired
    [bool]$RequiresReview
    [bool]$AcceptedStatePreserved
    [bool]$AcceptedStateChanged
    [object[]]$Evidence
    [string[]]$ReasonCodes
    [string[]]$RedactedFields
    [bool]$ReadOnly

    GuideReadinessRecord() {
        $this.ContractVersion = 'guide-intelligence/v1'
        $this.ChannelReference = ''
        $this.EventType = 'Unknown'
        $this.Title = ''
        $this.ReadinessState = 'Unresolved'
        $this.PublicationState = 'CandidateOnly'
        $this.PromotionRequired = 'ExplicitAcceptance'
        $this.RequiresReview = $true
        $this.AcceptedStatePreserved = $true
        $this.AcceptedStateChanged = $false
        $this.Evidence = @()
        $this.ReasonCodes = @()
        $this.RedactedFields = @(
            'Url'
            'StreamUrl'
            'Credential'
            'Token'
            'PrivatePath'
            'ParserError'
            'CandidateHash'
            'GenerationId'
        )
        $this.ReadOnly = $true
    }
}
