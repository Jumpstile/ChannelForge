function Get-ChannelForgeChannelIdentityKey {
    # The one place a lineup identity key is made: the tvg-id when present, otherwise the
    # display name, lowercased. Merge-ChannelForgeLineup dedups on it and saved channel
    # numbers are keyed by it.
    [CmdletBinding()]
    param([Parameter(Mandatory)][Channel]$Channel)

    if ($Channel.TvgId) { return "id:$($Channel.TvgId.Trim().ToLowerInvariant())" }
    return "name:$($Channel.DisplayName.Trim().ToLowerInvariant())"
}
