class Channel {
    [string]$Provider
    [string]$Playlist
    [string]$OriginalName
    [string]$NormalizedName
    [string]$DisplayName
    [string]$TvgId
    [string]$TvgName
    [string]$Logo
    [string]$Group
    # Stream URL. Unlike provider/EPG source URLs, this is the actual
    # playable content of a merged lineup, not a secret to redact from
    # generated reports (see Export-ChannelForgeM3UPlaylist).
    [string]$Url
    [string]$Category
    [string]$League
    [string]$Sport
    [string]$Network
    [string]$Region
    [string]$Language
    [nullable[int]]$PreferredNumber
    [nullable[int]]$AssignedNumber
    [int]$Priority
    [bool]$IsLocal
    [bool]$IsAdult
    [bool]$IsRegionalSports
    [bool]$IsDuplicate
    [int]$Confidence
    [System.Collections.ArrayList]$Warnings

    Channel() {
        $this.Provider = ''
        $this.Playlist = ''
        $this.OriginalName = ''
        $this.NormalizedName = ''
        $this.DisplayName = ''
        $this.TvgId = ''
        $this.TvgName = ''
        $this.Logo = ''
        $this.Group = ''
        $this.Url = ''
        $this.Category = ''
        $this.League = ''
        $this.Sport = ''
        $this.Network = ''
        $this.Region = ''
        $this.Language = ''
        $this.PreferredNumber = $null
        $this.AssignedNumber = $null
        $this.Priority = 0
        $this.IsLocal = $false
        $this.IsAdult = $false
        $this.IsRegionalSports = $false
        $this.IsDuplicate = $false
        $this.Confidence = 0
        $this.Warnings = [System.Collections.ArrayList]::new()
    }
}