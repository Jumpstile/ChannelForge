function New-ChannelForgeDuplicateReviewItem {
    # One review item per duplicate that Merge-ChannelForgeLineup dropped.
    # The first copy is kept (today's default); the item only reports it and
    # asks the question. Names and sources only, never stream URLs.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IdentityKey,
        [Parameter(Mandatory)][object]$Kept,
        [Parameter(Mandatory)][object]$Dropped
    )

    $keptSource = [string]$Kept.Playlist
    $droppedSource = [string]$Dropped.Playlist
    $name = [string]$Kept.DisplayName

    [pscustomobject][ordered]@{
        IdentityKey = $IdentityKey
        Name        = $name
        Kept        = [pscustomobject][ordered]@{ Name = $name; Provider = [string]$Kept.Provider; Playlist = $keptSource }
        Dropped     = [pscustomobject][ordered]@{ Name = [string]$Dropped.DisplayName; Provider = [string]$Dropped.Provider; Playlist = $droppedSource }
        State       = 'ReviewNeeded'
        Question    = "ChannelForge found $name in more than one playlist. Which copy do you want?"
        Choices     = @(
            "Keep both streams and use $droppedSource as failover if $keptSource fails."
            "Prefer $droppedSource and use $keptSource as failover."
            "Keep only $keptSource."
            "Keep only $droppedSource."
            'Keep both as separate channels.'
            'Ask me later / mark review needed.'
        )
    }
}
