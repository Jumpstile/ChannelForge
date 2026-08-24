class Programme {
    [string]$ChannelId
    # Canonical XMLTV processing keeps ChannelId normalized for existing
    # source-scoped output contracts. Guide binding uses this raw value so
    # ordinal M3U/XMLTV identity comparison cannot be weakened by trimming.
    [string]$RawChannelId
    [datetimeoffset]$Start
    [datetimeoffset]$End
    [string]$Title
    [string]$Subtitle
    [string]$Description
    [string[]]$Categories
    [string]$EpisodeNumber
    [bool]$IsNew
    [bool]$IsLive
    [bool]$IsPremiere
    [string]$SourceId
    [object]$Evidence

    Programme() {
        $this.ChannelId = ''
        $this.RawChannelId = ''
        $this.Start = [datetimeoffset]::MinValue
        $this.End = [datetimeoffset]::MinValue
        $this.Title = ''
        $this.Subtitle = ''
        $this.Description = ''
        $this.Categories = @()
        $this.EpisodeNumber = ''
        $this.IsNew = $false
        $this.IsLive = $false
        $this.IsPremiere = $false
        $this.SourceId = ''
        $this.Evidence = $null
    }
}
