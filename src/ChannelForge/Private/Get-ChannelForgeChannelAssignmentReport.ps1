function Get-ChannelForgeChannelAssignmentReport {
    # "Where is this assigned?" for one channel. Report only: nothing is changed or written.
    # Finds the channel by tvg-id or display name (case-insensitive), then says where its
    # source, group, guide and number came from. Anything not known is reported as 'Unknown'
    # or 'None', never guessed. Two or more matches return Found = $false with the names, so
    # the caller can ask for a more exact query.
    # BindingResult is the object from Resolve-ChannelForgeM3UXmltvBinding. Omit it and the
    # guide is reported as 'Unknown'. GuideChoice and ChannelNumber are the saved decision
    # records from Read-ChannelForgeChannelDecisions.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Channel[]]$Channel,
        [Parameter(Mandatory)][string]$Query,
        [AllowNull()][object]$BindingResult = $null,
        [AllowEmptyCollection()][object[]]$GuideChoice = @(),
        [AllowEmptyCollection()][object[]]$ChannelNumber = @()
    )

    $text = $Query.Trim()
    $matches_ = @($Channel | Where-Object {
            $_.TvgId -and $_.TvgId.Trim() -ieq $text -or $_.DisplayName.Trim() -ieq $text
        })
    if ($matches_.Count -ne 1) {
        $why = if ($matches_.Count -eq 0) { 'NotFound' } else { 'Ambiguous' }
        return [pscustomobject][ordered]@{
            Found   = $false
            Query   = $text
            Reason  = $why
            Matches = @($matches_ | ForEach-Object { $_.DisplayName } | Sort-Object)
        }
    }
    $ch = $matches_[0]

    $guide = Get-ChannelForgeAssignmentGuide -Channel $ch -BindingResult $BindingResult -GuideChoice $GuideChoice
    $savedNumber = @($ChannelNumber | Where-Object { [string]$_.channelKey -ceq (Get-ChannelForgeChannelIdentityKey -Channel $ch) }) | Select-Object -First 1
    $number = [pscustomobject][ordered]@{
        Value       = $ch.AssignedNumber
        IsSavedUser = ($null -ne $savedNumber -and $null -ne $ch.AssignedNumber -and [int]$savedNumber.number -eq [int]$ch.AssignedNumber)
        SavedNumber = if ($null -ne $savedNumber) { [int]$savedNumber.number } else { $null }
    }

    [pscustomobject][ordered]@{
        Found    = $true
        Query    = $text
        Name     = $ch.DisplayName
        Source   = if ($ch.Provider) { $ch.Provider } else { 'Unknown' }
        Playlist = if ($ch.Playlist) { $ch.Playlist } else { 'Unknown' }
        Group    = if ($ch.Group) { $ch.Group } else { 'None' }
        Guide    = $guide
        Number   = $number
        Decision = Get-ChannelForgeAssignmentDecision -Channel $ch -GuideChoice $GuideChoice
    }
}

function Get-ChannelForgeAssignmentDecision {
    # The saved guide choice for this channel, or $null. The key is made from the stream URL.
    [CmdletBinding()]
    param([Parameter(Mandatory)][Channel]$Channel, [AllowEmptyCollection()][object[]]$GuideChoice = @())

    if ([string]::IsNullOrWhiteSpace($Channel.Url)) { return $null }
    $key = Get-ChannelForgeChannelKey -Url $Channel.Url
    return @($GuideChoice | Where-Object { [string]$_.key -ceq $key }) | Select-Object -First 1
}

function Get-ChannelForgeAssignmentGuide {
    # Where the guide binding came from: a saved choice, the playlist's tvg-id matched to the
    # guide, or nothing. 'Unknown' means the binding result was not supplied.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Channel]$Channel,
        [AllowNull()][object]$BindingResult = $null,
        [AllowEmptyCollection()][object[]]$GuideChoice = @()
    )

    $decision = Get-ChannelForgeAssignmentDecision -Channel $Channel -GuideChoice $GuideChoice
    if ($null -ne $decision -and $decision.choice -in @('BindTrueMatch', 'ShareOnPurpose')) {
        return [pscustomobject][ordered]@{ GuideId = [string]$decision.guideId; Origin = 'SavedDecision'; Status = [string]$decision.choice }
    }
    if ($null -eq $BindingResult) {
        return [pscustomobject][ordered]@{ GuideId = $null; Origin = 'Unknown'; Status = 'NotEvaluated' }
    }
    foreach ($row in @($BindingResult.ExactBindings) + @($BindingResult.ReviewNeeded) + @($BindingResult.UnboundChannels)) {
        if ($null -ne $row -and [object]::ReferenceEquals($row.M3UChannel, $Channel)) {
            $id = if ($row.PSObject.Properties['XmltvChannelId']) { [string]$row.XmltvChannelId } else { $null }
            $origin = if ($row.Status -eq 'Exact') { 'PlaylistTvgId' } else { 'None' }
            return [pscustomobject][ordered]@{ GuideId = $id; Origin = $origin; Status = [string]$row.Status }
        }
    }
    return [pscustomobject][ordered]@{ GuideId = $null; Origin = 'None'; Status = 'Unknown' }
}

function Format-ChannelForgeChannelAssignmentReport {
    # Plain-text lines for one report from Get-ChannelForgeChannelAssignmentReport.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Report)

    if (-not $Report.Found) {
        if ($Report.Reason -eq 'Ambiguous') {
            return @("More than one channel matches '$($Report.Query)':") + @($Report.Matches | ForEach-Object { "  $_" })
        }
        return @("No channel matches '$($Report.Query)'.")
    }
    $guide = if ($Report.Guide.GuideId) { "$($Report.Guide.GuideId) (from $($Report.Guide.Origin))" } else { "none ($($Report.Guide.Status))" }
    $number = if ($null -eq $Report.Number.Value) { 'none' }
    elseif ($Report.Number.IsSavedUser) { "$($Report.Number.Value) (saved by you)" }
    else { "$($Report.Number.Value) (assigned automatically)" }
    $decision = if ($null -eq $Report.Decision) { 'none' } else { [string]$Report.Decision.choice }
    @(
        "Channel:  $($Report.Name)"
        "Source:   $($Report.Source)"
        "Group:    $($Report.Group)"
        "Guide:    $guide"
        "Number:   $number"
        "Decision: $decision"
    )
}
