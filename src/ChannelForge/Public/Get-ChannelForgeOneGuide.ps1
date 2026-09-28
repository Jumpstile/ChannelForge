function Get-ChannelForgeOneGuide {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('LiveNow', 'StartingSoon', 'Category', 'Details')][string]$Query,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Programmes,
        [Parameter(Mandatory)][datetimeoffset]$EvaluationTimeUtc,
        [ValidateSet('live-now', 'starting-soon', 'wrestling', 'football', 'baseball', 'soccer', 'movies', 'news')][string]$CategoryKey,
        [ValidatePattern('^[a-f0-9]{64}$')][string]$ItemId,
        [ValidateRange(1, 100)][int]$MaximumItems = 100,
        [ValidateRange(0, 2147483647)][int]$Offset = 0
    )

    $evaluation = $EvaluationTimeUtc.ToUniversalTime()
    $startingSoonEnd = $evaluation.AddHours(2)
    $itemGroups = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $taxonomyOrder = @('live-now', 'starting-soon', 'wrestling', 'football', 'baseball', 'soccer', 'movies', 'news')
    $taxonomy = @{
        wrestling = 'wrestling'
        football = 'football'
        baseball = 'baseball'
        soccer = 'soccer'
        movies = 'movies'
        movie = 'movies'
        news = 'news'
    }

    function Get-InputValue {
        param([AllowNull()][object]$InputObject, [Parameter(Mandatory)][string]$Name)
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.IDictionary]) {
            if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
            return $null
        }
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
        return $null
    }

    function Get-SafeIdentifier {
        param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Domain, [string]$Fallback = '')
        $raw = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $Fallback }
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
        $safe = ConvertTo-ChannelForgeGuideSafeText -Value $raw -MaximumLength 128
        if ($safe -match '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') { return $safe.ToLowerInvariant() }
        return ('cf-' + (Get-ChannelForgeDomainHash -Domain $Domain -InputObject $raw))
    }

    function Get-SafeOptionalText {
        param([AllowNull()][object]$Value, [int]$MaximumLength = 128)
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
        $safe = ConvertTo-ChannelForgeGuideSafeText -Value $Value -MaximumLength $MaximumLength
        if ([string]::IsNullOrWhiteSpace($safe)) { return $null }
        return $safe
    }

    foreach ($programme in $Programmes) {
        if ($null -eq $programme) { throw 'One Guide source contains a null programme.' }
        $title = ConvertTo-ChannelForgeGuideSafeText -Value (Get-InputValue $programme 'Title') -MaximumLength 256
        if ([string]::IsNullOrWhiteSpace($title)) { continue }

        $startValue = Get-InputValue $programme 'Start'
        $stopValue = Get-InputValue $programme 'End'
        $start = [datetimeoffset]::MinValue
        $stop = [datetimeoffset]::MinValue
        if ($null -eq $startValue -or $null -eq $stopValue -or
            -not [datetimeoffset]::TryParse([string]$startValue, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$start) -or
            -not [datetimeoffset]::TryParse([string]$stopValue, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$stop) -or
            $stop -le $start) {
            throw 'One Guide programme has an invalid time interval.'
        }
        $start = $start.ToUniversalTime()
        $stop = $stop.ToUniversalTime()
        $startText = $start.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        $stopText = $stop.ToString('o', [Globalization.CultureInfo]::InvariantCulture)

        $subtitle = Get-SafeOptionalText (Get-InputValue $programme 'Subtitle') 256
        $description = Get-SafeOptionalText (Get-InputValue $programme 'Description') 512
        $episodeNumber = Get-SafeOptionalText (Get-InputValue $programme 'EpisodeNumber') 128
        $categories = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($rawCategory in @(Get-InputValue $programme 'Categories')) {
            if ($null -eq $rawCategory) { continue }
            $categoryText = ConvertTo-ChannelForgeGuideSafeText -Value $rawCategory -MaximumLength 128
            $key = $categoryText.Trim().ToLowerInvariant()
            if ($taxonomy.ContainsKey($key)) { [void]$categories.Add([string]$taxonomy[$key]) }
        }
        $declaredKind = [string](Get-InputValue $programme 'Kind')
        if ($declaredKind -notin @('Programme', 'Event', 'Movie', 'SeriesEpisode', 'Other')) { $declaredKind = '' }
        $kind = if ($categories.Contains('movies')) { 'Movie' }
            elseif (-not [string]::IsNullOrWhiteSpace($episodeNumber)) { 'SeriesEpisode' }
            elseif (@($categories | Where-Object { $_ -in @('wrestling', 'football', 'baseball', 'soccer') }).Count -gt 0) { 'Event' }
            elseif (-not [string]::IsNullOrWhiteSpace($declaredKind)) { $declaredKind }
            else { 'Programme' }

        $sport = Get-SafeOptionalText (Get-InputValue $programme 'Sport') 128
        $league = Get-SafeOptionalText (Get-InputValue $programme 'League') 128
        $homeParticipant = Get-SafeOptionalText (Get-InputValue $programme 'HomeParticipant') 128
        $awayParticipant = Get-SafeOptionalText (Get-InputValue $programme 'AwayParticipant') 128
        $promotion = $null
        $promotionInput = Get-InputValue $programme 'Promotion'
        if ($categories.Contains('wrestling') -and $null -ne $promotionInput) {
            $promotionId = Get-SafeIdentifier (Get-InputValue $promotionInput 'Id') 'one-guide-promotion/v1'
            $promotionName = Get-SafeOptionalText (Get-InputValue $promotionInput 'Name') 128
            if (-not [string]::IsNullOrWhiteSpace($promotionId) -and $null -ne $promotionName) {
                $promotion = [ordered]@{ Id = $promotionId; Name = $promotionName }
            }
        }

        $status = if ($start -le $evaluation -and $stop -gt $evaluation) { 'Live' }
            elseif ($start -gt $evaluation -and $start -le $startingSoonEnd) { 'StartingSoon' }
            elseif ($start -gt $evaluation) { 'Upcoming' }
            else { 'Past' }
        if ($status -eq 'Live') { [void]$categories.Add('live-now') }
        elseif ($status -eq 'StartingSoon') { [void]$categories.Add('starting-soon') }

        $safeTitleKey = [regex]::Replace($title.Trim().ToLowerInvariant(), '\s+', ' ')
        $safeSubtitleKey = if ($null -eq $subtitle) { '' } else { [regex]::Replace($subtitle.Trim().ToLowerInvariant(), '\s+', ' ') }
        # V1 correlation deliberately excludes classification and provider/channel
        # metadata. Corroborating sources may disagree on those fields while still
        # describing the same scheduled content.
        $identity = [ordered]@{
            Title = $safeTitleKey
            Subtitle = $safeSubtitleKey
            EpisodeNumber = if ($null -eq $episodeNumber) { '' } else { $episodeNumber.ToLowerInvariant() }
            StartUtc = $startText
            StopUtc = $stopText
        }
        $itemId = Get-ChannelForgeDomainHash -Domain 'one-guide-item/v1' -InputObject $identity

        $sourceId = Get-SafeIdentifier (Get-InputValue $programme 'SourceId') 'one-guide-source/v1' 'accepted-guide'
        $sourceLabel = Get-SafeOptionalText (Get-InputValue $programme 'SourceLabel') 128
        if ($null -eq $sourceLabel) { $sourceLabel = if ($sourceId -eq 'accepted-guide') { 'Accepted guide' } else { $sourceId } }
        $channelReference = Get-SafeIdentifier (Get-InputValue $programme 'ChannelId') 'one-guide-channel/v1'
        if ([string]::IsNullOrWhiteSpace($channelReference)) { continue }
        $offeringId = Get-ChannelForgeDomainHash -Domain 'one-guide-offering/v1' -InputObject ([ordered]@{
            ItemId = $itemId
            SourceId = $sourceId
            ChannelReference = $channelReference
        })
        $offering = [pscustomobject][ordered]@{
            OfferingId = $offeringId
            SourceId = $sourceId
            SourceLabel = $sourceLabel
            Availability = 'GuideOnly'
            Entitlement = 'Unknown'
            Launch = [pscustomobject][ordered]@{ Kind = 'Channel'; ChannelReference = $channelReference }
            DvrSupported = $null
            TimeshiftSupported = $null
        }

        if (-not $itemGroups.ContainsKey($itemId)) {
            $itemGroups[$itemId] = [pscustomobject][ordered]@{
                Identity = $identity
                ItemId = $itemId
                Kind = $kind
                Title = $title
                Subtitle = $subtitle
                Description = $description
                EpisodeNumber = $episodeNumber
                StartUtc = $startText
                StopUtc = $stopText
                Status = $status
                CategoryKeys = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
                Sport = $sport
                League = $league
                HomeParticipant = $homeParticipant
                AwayParticipant = $awayParticipant
                Promotion = $promotion
                Offerings = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
            }
        }
        $group = $itemGroups[$itemId]
        if (-not $group.Offerings.ContainsKey($offeringId)) {
            $group.Offerings[$offeringId] = $offering
        }
        elseif ([StringComparer]::Ordinal.Compare($sourceLabel, [string]$group.Offerings[$offeringId].SourceLabel) -lt 0) {
            $group.Offerings[$offeringId].SourceLabel = $sourceLabel
        }
        if ([StringComparer]::Ordinal.Compare($title, [string]$group.Title) -lt 0) { $group.Title = $title }
        if ($null -ne $description -and ($null -eq $group.Description -or [StringComparer]::Ordinal.Compare($description, [string]$group.Description) -lt 0)) { $group.Description = $description }
        if ($null -ne $subtitle -and ($null -eq $group.Subtitle -or [StringComparer]::Ordinal.Compare($subtitle, [string]$group.Subtitle) -lt 0)) { $group.Subtitle = $subtitle }
        if ($null -ne $episodeNumber -and ($null -eq $group.EpisodeNumber -or [StringComparer]::Ordinal.Compare($episodeNumber, [string]$group.EpisodeNumber) -lt 0)) { $group.EpisodeNumber = $episodeNumber }
        foreach ($category in $categories) { [void]$group.CategoryKeys.Add($category) }

        foreach ($metadata in @(
                @{ Name = 'Sport'; Value = $sport },
                @{ Name = 'League'; Value = $league },
                @{ Name = 'HomeParticipant'; Value = $homeParticipant },
                @{ Name = 'AwayParticipant'; Value = $awayParticipant }
            )) {
            $candidate = $metadata.Value
            $current = $group.($metadata.Name)
            if ($null -ne $candidate -and ($null -eq $current -or [StringComparer]::Ordinal.Compare([string]$candidate, [string]$current) -lt 0)) {
                $group.($metadata.Name) = $candidate
            }
        }
        if ($null -ne $promotion) {
            $candidatePromotionKey = "$($promotion.Id)::$($promotion.Name)"
            $currentPromotionKey = if ($null -eq $group.Promotion) { $null } else { "$($group.Promotion.Id)::$($group.Promotion.Name)" }
            if ($null -eq $currentPromotionKey -or [StringComparer]::Ordinal.Compare($candidatePromotionKey, $currentPromotionKey) -lt 0) {
                $group.Promotion = $promotion
            }
        }
    }


    $offeringComparison = [System.Comparison[object]]{
        param($left, $right)
        $comparison = [StringComparer]::Ordinal.Compare([string]$left.SourceId, [string]$right.SourceId)
        if ($comparison -eq 0) { $comparison = [StringComparer]::Ordinal.Compare([string]$left.Launch.ChannelReference, [string]$right.Launch.ChannelReference) }
        if ($comparison -eq 0) { $comparison = [StringComparer]::Ordinal.Compare([string]$left.OfferingId, [string]$right.OfferingId) }
        return $comparison
    }
    $itemComparison = [System.Comparison[object]]{
        param($left, $right)
        $comparison = [StringComparer]::Ordinal.Compare([string]$left.StartUtc, [string]$right.StartUtc)
        if ($comparison -eq 0) { $comparison = [StringComparer]::Ordinal.Compare([string]$left.Title, [string]$right.Title) }
        if ($comparison -eq 0) { $comparison = [StringComparer]::Ordinal.Compare([string]$left.ItemId, [string]$right.ItemId) }
        return $comparison
    }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($group in $itemGroups.Values) {
        $allOfferings = @($group.Offerings.Values)
        [Array]::Sort($allOfferings, $offeringComparison)
        $offerings = @($allOfferings | Select-Object -First 16)
        $orderedCategories = [System.Collections.Generic.List[string]]::new()
        foreach ($taxonomyKey in $taxonomyOrder) {
            if (@($group.CategoryKeys) -contains $taxonomyKey) { [void]$orderedCategories.Add($taxonomyKey) }
        }
        $finalKind = if (@($orderedCategories) -contains 'movies') { 'Movie' }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$group.EpisodeNumber)) { 'SeriesEpisode' }
            elseif (@($orderedCategories | Where-Object { $_ -in @('wrestling', 'football', 'baseball', 'soccer') }).Count -gt 0) { 'Event' }
            elseif (@($orderedCategories) -contains 'news') { 'Programme' }
            else { 'Other' }
        $items.Add([pscustomobject][ordered]@{
            ItemId = $group.ItemId
            Kind = $finalKind
            Title = $group.Title
            Subtitle = $group.Subtitle
            Description = $group.Description
            EpisodeNumber = $group.EpisodeNumber
            StartUtc = $group.StartUtc
            StopUtc = $group.StopUtc
            Status = $group.Status
            CategoryKeys = @($orderedCategories)
            Sport = $group.Sport
            League = $group.League
            HomeParticipant = $group.HomeParticipant
            AwayParticipant = $group.AwayParticipant
            Promotion = $group.Promotion
            Offerings = $offerings
            OfferingCount = $allOfferings.Count
            OfferingsTruncated = ($allOfferings.Count -gt $offerings.Count)
            FreshnessState = 'Unknown'
            ConfidenceState = 'Unknown'
            ConfidenceScore = $null
        })
    }
    $orderedItems = $items.ToArray()
    [Array]::Sort($orderedItems, $itemComparison)

    if ($Query -eq 'Category') {
        if ([string]::IsNullOrWhiteSpace($CategoryKey)) { throw 'CategoryKey is required for a category query.' }
        $CategoryKey = $CategoryKey.ToLowerInvariant()
    }
    if ($Query -eq 'Details' -and [string]::IsNullOrWhiteSpace($ItemId)) { throw 'ItemId is required for a details query.' }
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $orderedItems) {
        $include = switch ($Query) {
            'LiveNow' { $item.Status -ceq 'Live' }
            'StartingSoon' { $item.Status -ceq 'StartingSoon' }
            'Category' { $item.CategoryKeys -ccontains $CategoryKey }
            'Details' { [string]$item.ItemId -ceq $ItemId }
        }
        if ($include) { [void]$selected.Add($item) }
    }
    $totalCount = $selected.Count
    $upperBound = [Math]::Min([int64]$totalCount, ([int64]$Offset + [int64]$MaximumItems))
    $returned = [System.Collections.Generic.List[object]]::new()
    for ($index = $Offset; $index -lt $upperBound; $index++) { [void]$returned.Add($selected[$index]) }
    $result = [ordered]@{
        Version = 'one-guide/v1'
        EvaluationTimeUtc = $evaluation.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        Query = $Query
        Offset = $Offset
        MaximumItems = $MaximumItems
        TotalCount = $totalCount
        ItemsTruncated = ([int64]$Offset + [int64]$returned.Count -lt [int64]$totalCount)
        Items = @($returned.ToArray())
    }
    if ($Query -eq 'Category') { $result.CategoryKey = $CategoryKey }
    return [pscustomobject]$result
}
