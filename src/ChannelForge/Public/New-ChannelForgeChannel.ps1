function New-ChannelForgeChannel {
    [CmdletBinding()]
    param(
        [string]$Provider = '',
        [string]$Playlist = '',
        [Parameter(Mandatory)]
        [string]$OriginalName,
        [string]$DisplayName = '',
        [string]$TvgId = '',
        [string]$TvgName = '',
        [string]$Logo = '',
        [string]$Group = ''
    )

    # Channel is the core domain object in ChannelForge.
    # This function creates a safe default object from raw playlist metadata.
    $channel = [Channel]::new()

    $channel.Provider = $Provider
    $channel.Playlist = $Playlist
    $channel.OriginalName = $OriginalName
    $channel.NormalizedName = $OriginalName.Trim()
    $channel.DisplayName = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $OriginalName } else { $DisplayName }
    $channel.TvgId = $TvgId
    $channel.TvgName = $TvgName
    $channel.Logo = $Logo
    $channel.Group = $Group

    return $channel
}