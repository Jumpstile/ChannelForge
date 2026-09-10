class GuidePatternExample {
    [string]$ContractVersion
    [int]$Ordinal
    [string]$InputField
    [string]$SourceId
    [string]$SourceFamily
    [string]$EvidenceType
    [string]$SourceRelationship
    [string]$Group
    [string]$EventType
    [string]$EventStatus
    [string]$League
    [string]$Sport
    [string]$FreshnessState
    [string]$ConfidenceState
    [string]$EvidenceStartUtc
    [string]$EvidenceEndUtc
    [string]$SourceTimezone
    [string]$ChannelReference
    [string]$EvidenceTitle
    [string]$EvidenceHomeParticipant
    [string]$EvidenceAwayParticipant
    [string[]]$EvidenceReasonCodes
    [string]$SafeFingerprint
    [string]$SafeText
    [bool]$ReadOnly

    GuidePatternExample() {
        $this.ContractVersion = 'guide-intelligence/pattern-example/v1'
        $this.Ordinal = 0
        $this.InputField = 'DisplayName'
        $this.SourceId = ''
        $this.SourceFamily = ''
        $this.EvidenceType = 'ProviderDisplayText'
        $this.SourceRelationship = 'Unknown'
        $this.Group = ''
        $this.EventType = 'Unknown'
        $this.EventStatus = 'Unknown'
        $this.League = ''
        $this.Sport = ''
        $this.FreshnessState = 'Unknown'
        $this.ConfidenceState = 'Unknown'
        $this.EvidenceStartUtc = ''
        $this.EvidenceEndUtc = ''
        $this.SourceTimezone = ''
        $this.ChannelReference = ''
        $this.EvidenceTitle = ''
        $this.EvidenceHomeParticipant = ''
        $this.EvidenceAwayParticipant = ''
        $this.EvidenceReasonCodes = @()
        $this.SafeFingerprint = ''
        $this.SafeText = ''
        $this.ReadOnly = $true
    }
}
