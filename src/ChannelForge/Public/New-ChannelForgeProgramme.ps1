function New-ChannelForgeProgramme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChannelId,

        [Parameter(Mandatory)]
        [datetimeoffset]$Start,

        [Parameter(Mandatory)]
        [datetimeoffset]$End,

        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Subtitle = '',

        [string]$Description = '',

        [string[]]$Categories = @(),

        [string]$EpisodeNumber = '',

        [bool]$IsNew = $false,

        [bool]$IsLive = $false,

        [bool]$IsPremiere = $false,

        [string]$SourceId = '',

        [object]$Evidence = $null
    )

    if ([string]::IsNullOrWhiteSpace($ChannelId)) {
        throw 'Programme ChannelId cannot be empty.'
    }

    if ([string]::IsNullOrWhiteSpace($Title)) {
        throw 'Programme Title cannot be empty.'
    }

    if ($End -le $Start) {
        throw 'Programme End must be later than Start.'
    }

    $programme = [Programme]::new()
    $programme.RawChannelId = $ChannelId
    $programme.ChannelId = $ChannelId.Trim()
    $programme.Start = $Start
    $programme.End = $End
    $programme.Title = $Title.Trim()
    $programme.Subtitle = if ($null -eq $Subtitle) { '' } else { $Subtitle.Trim() }
    $programme.Description = if ($null -eq $Description) { '' } else { $Description.Trim() }
    $programme.Categories = @(
        $Categories |
            ForEach-Object { if ($null -ne $_ -and -not [string]::IsNullOrWhiteSpace($_)) { $_.Trim() } } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $programme.EpisodeNumber = if ($null -eq $EpisodeNumber) { '' } else { $EpisodeNumber.Trim() }
    $programme.IsNew = $IsNew
    $programme.IsLive = $IsLive
    $programme.IsPremiere = $IsPremiere
    $programme.SourceId = if ($null -eq $SourceId) { '' } else { $SourceId.Trim() }
    $programme.Evidence = $Evidence

    return $programme
}
