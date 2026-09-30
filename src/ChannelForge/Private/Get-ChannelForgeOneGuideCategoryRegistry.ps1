function Get-ChannelForgeOneGuideCategoryRegistry {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject][ordered]@{ Key = 'live-now'; DisplayName = 'Live Now'; Group = 'temporal'; Aliases = @() }
        [pscustomobject][ordered]@{ Key = 'starting-soon'; DisplayName = 'Starting Soon'; Group = 'temporal'; Aliases = @() }
        [pscustomobject][ordered]@{ Key = 'wrestling'; DisplayName = 'Wrestling'; Group = 'sports'; Aliases = @('wrestling', 'professional wrestling', 'pro wrestling') }
        [pscustomobject][ordered]@{ Key = 'football'; DisplayName = 'Football'; Group = 'sports'; Aliases = @('football') }
        [pscustomobject][ordered]@{ Key = 'baseball'; DisplayName = 'Baseball'; Group = 'sports'; Aliases = @('baseball') }
        [pscustomobject][ordered]@{ Key = 'soccer'; DisplayName = 'Soccer'; Group = 'sports'; Aliases = @('soccer', 'association football') }
        [pscustomobject][ordered]@{ Key = 'movies'; DisplayName = 'Movies'; Group = 'content'; Aliases = @('movie', 'movies', 'film', 'films') }
        [pscustomobject][ordered]@{ Key = 'news'; DisplayName = 'News'; Group = 'content'; Aliases = @('news', 'current affairs') }
    )
}
