class GuideEvidenceRecord {
    [string]$ContractVersion
    [string]$EvidenceType
    [string]$SourceId
    [string]$SourceFamily
    [string]$SourceRelationship
    [string]$ChannelReference
    [string]$DisplayName
    [string]$Group
    [string]$Title
    [string]$EventType
    [string]$League
    [string]$Sport
    [string]$HomeParticipant
    [string]$AwayParticipant
    [string]$StartUtc
    [string]$EndUtc
    [string]$SourceTimezone
    [string]$EventStatus
    [string]$ConfidenceState
    [int]$ConfidenceScore
    [string]$FreshnessState
    [string[]]$ReasonCodes
    [string[]]$RedactedFields
    [object[]]$VolatileFacts
    [bool]$ReadOnly

    GuideEvidenceRecord() {
        $this.ContractVersion = 'guide-intelligence/v1'
        $this.EvidenceType = ''
        $this.SourceId = ''
        $this.SourceFamily = ''
        $this.SourceRelationship = 'Unknown'
        $this.ChannelReference = ''
        $this.DisplayName = ''
        $this.Group = ''
        $this.Title = ''
        $this.EventType = 'Unknown'
        $this.League = ''
        $this.Sport = ''
        $this.HomeParticipant = ''
        $this.AwayParticipant = ''
        $this.StartUtc = ''
        $this.EndUtc = ''
        $this.SourceTimezone = ''
        $this.EventStatus = 'Unknown'
        $this.ConfidenceState = 'Unresolved'
        $this.ConfidenceScore = 0
        $this.FreshnessState = 'Unknown'
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
            'VolatileValue'
        )
        $this.VolatileFacts = @()
        $this.ReadOnly = $true
    }
}
