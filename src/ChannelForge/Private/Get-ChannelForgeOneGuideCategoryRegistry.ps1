function Get-ChannelForgeOneGuideCategoryRegistry {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject][ordered]@{ Key = 'live-now'; DisplayName = 'Live Now'; Group = 'temporal'; Aliases = @() }
        [pscustomobject][ordered]@{ Key = 'starting-soon'; DisplayName = 'Starting Soon'; Group = 'temporal'; Aliases = @() }
        [pscustomobject][ordered]@{ Key = 'football'; DisplayName = 'Football'; Group = 'sports'; Aliases = @('football') }
        [pscustomobject][ordered]@{ Key = 'baseball'; DisplayName = 'Baseball'; Group = 'sports'; Aliases = @('baseball') }
        [pscustomobject][ordered]@{ Key = 'basketball'; DisplayName = 'Basketball'; Group = 'sports'; Aliases = @('basketball') }
        [pscustomobject][ordered]@{ Key = 'hockey'; DisplayName = 'Hockey'; Group = 'sports'; Aliases = @('hockey', 'ice hockey') }
        [pscustomobject][ordered]@{ Key = 'soccer'; DisplayName = 'Soccer'; Group = 'sports'; Aliases = @('soccer', 'association football') }
        [pscustomobject][ordered]@{ Key = 'wrestling'; DisplayName = 'Wrestling'; Group = 'sports'; Aliases = @('wrestling', 'professional wrestling', 'pro wrestling') }
        [pscustomobject][ordered]@{ Key = 'motorsports'; DisplayName = 'Auto Racing & Motorsports'; Group = 'sports'; Aliases = @('auto racing', 'motor racing', 'motorsports', 'motorcycle racing') }
        [pscustomobject][ordered]@{ Key = 'boxing'; DisplayName = 'Boxing'; Group = 'sports'; Aliases = @('boxing') }
        [pscustomobject][ordered]@{ Key = 'mma'; DisplayName = 'MMA'; Group = 'sports'; Aliases = @('mma', 'mixed martial arts') }
        [pscustomobject][ordered]@{ Key = 'tennis'; DisplayName = 'Tennis'; Group = 'sports'; Aliases = @('tennis') }
        [pscustomobject][ordered]@{ Key = 'golf'; DisplayName = 'Golf'; Group = 'sports'; Aliases = @('golf') }
        [pscustomobject][ordered]@{ Key = 'rugby'; DisplayName = 'Rugby'; Group = 'sports'; Aliases = @('rugby') }
        [pscustomobject][ordered]@{ Key = 'cricket'; DisplayName = 'Cricket'; Group = 'sports'; Aliases = @('cricket') }
        [pscustomobject][ordered]@{ Key = 'lacrosse'; DisplayName = 'Lacrosse'; Group = 'sports'; Aliases = @('lacrosse') }
        [pscustomobject][ordered]@{ Key = 'other-sports'; DisplayName = 'Other Sports'; Group = 'sports'; Aliases = @('sports', 'sport', 'other sports') }
        [pscustomobject][ordered]@{ Key = 'movies'; DisplayName = 'Movies'; Group = 'content'; Aliases = @('movie', 'movies', 'film', 'films') }
        [pscustomobject][ordered]@{ Key = 'news'; DisplayName = 'News'; Group = 'content'; Aliases = @('news', 'current affairs') }
        [pscustomobject][ordered]@{ Key = 'kids'; DisplayName = 'Kids'; Group = 'content'; Aliases = @('children', "children's", 'kids') }
        [pscustomobject][ordered]@{ Key = 'entertainment'; DisplayName = 'Entertainment'; Group = 'content'; Aliases = @('entertainment') }
        [pscustomobject][ordered]@{ Key = 'documentary'; DisplayName = 'Documentary'; Group = 'content'; Aliases = @('documentary', 'documentaries') }
        [pscustomobject][ordered]@{ Key = 'comedy'; DisplayName = 'Comedy'; Group = 'content'; Aliases = @('comedy') }
    )
}
