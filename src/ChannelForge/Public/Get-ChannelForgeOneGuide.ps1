function Get-ChannelForgeOneGuide {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('LiveNow', 'StartingSoon', 'Category', 'Details')][string]$Query,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Programmes,
        [Parameter(Mandatory)][datetimeoffset]$EvaluationTimeUtc,
        [string]$CategoryKey,
        [ValidatePattern('^[a-f0-9]{64}$')][string]$ItemId,
        [ValidateRange(1, 100)][int]$MaximumItems = 100,
        [ValidateRange(0, 2147483647)][int]$Offset = 0,
        [Parameter(DontShow)][AllowNull()][object]$CatalogueById,
        [Parameter(DontShow)][AllowNull()][AllowEmptyCollection()][object[]]$Catalogue = @(),
        [Parameter(DontShow)][switch]$UseCatalogue,
        [Parameter(DontShow)][switch]$ReturnCatalogue,
        [Parameter(DontShow)][switch]$CurrentAndUpcomingOnly
    )

    $evaluation = $EvaluationTimeUtc.ToUniversalTime()
    $startingSoonEnd = $evaluation.AddHours(2)
    $categoryRegistry = @(Get-ChannelForgeOneGuideCategoryRegistry)
    $taxonomyOrder = @($categoryRegistry | ForEach-Object { $_.Key })
    if ($UseCatalogue) {
        if ($Query -eq 'Details' -and $null -ne $CatalogueById) {
            if ($CatalogueById.ContainsKey($ItemId)) { $orderedItems = @($CatalogueById[$ItemId]) }
            else { $orderedItems = @() }
        }
        else { $orderedItems = @($Catalogue) }
    }
    else {
        $itemGroups = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $sourceReferences = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        $channelReferences = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
        $taxonomy = @{}
        $specificSportKeys = @{}
        foreach ($categoryDefinition in $categoryRegistry) {
            foreach ($alias in @($categoryDefinition.Aliases)) {
                $taxonomy[[string]$alias.ToLowerInvariant()] = [string]$categoryDefinition.Key
            }
            if ($categoryDefinition.Group -eq 'sports' -and $categoryDefinition.Key -ne 'other-sports') {
                $specificSportKeys[[string]$categoryDefinition.Key] = $true
            }
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

    function Get-OpaqueIdentifier {
        param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Domain, [string]$Fallback = '')
        $raw = if ($null -eq $Value) { '' } else { ([string]$Value).Trim() }
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $Fallback }
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
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
        $sourceCategories = [System.Collections.Generic.List[string]]::new()
        $hasGenericSports = $false
        $hasSpecificSport = $false
        foreach ($rawCategory in @(Get-InputValue $programme 'Categories')) {
            if ($null -eq $rawCategory) { continue }
            $categoryText = ConvertTo-ChannelForgeGuideSafeText -Value $rawCategory -MaximumLength 128
            [void]$sourceCategories.Add([string]$categoryText)
            $key = $categoryText.Trim().ToLowerInvariant()
            if ($key -in @('sport', 'sports')) { $hasGenericSports = $true; continue }
            if ($taxonomy.ContainsKey($key)) {
                $mappedCategoryKey = [string]$taxonomy[$key]
                if ($mappedCategoryKey -ceq 'other-sports') { $hasGenericSports = $true; continue }
                [void]$categories.Add($mappedCategoryKey)
                if ($specificSportKeys.ContainsKey($mappedCategoryKey)) { $hasSpecificSport = $true }
            }
        }
        if ($hasGenericSports -and -not $hasSpecificSport) {
            [void]$categories.Add('other-sports')
        }
        $sourceCategories.Sort([System.StringComparer]::Ordinal)
        $sourceCategoryEvidence = $sourceCategories.ToArray()
        $sourceCategoryKeys = @($categories)
        $declaredKind = [string](Get-InputValue $programme 'Kind')
        if ($declaredKind -cnotin @('Programme', 'Event', 'Movie', 'SeriesEpisode', 'Other')) { $declaredKind = $null }
        $sport = Get-SafeOptionalText (Get-InputValue $programme 'Sport') 128
        $league = Get-SafeOptionalText (Get-InputValue $programme 'League') 128
        $homeParticipant = Get-SafeOptionalText (Get-InputValue $programme 'HomeParticipant') 128
        $awayParticipant = Get-SafeOptionalText (Get-InputValue $programme 'AwayParticipant') 128
        $promotion = $null
        $promotionInput = Get-InputValue $programme 'Promotion'
        if ($categories.Contains('wrestling') -and $null -ne $promotionInput) {
            $promotionId = Get-OpaqueIdentifier (Get-InputValue $promotionInput 'Id') 'one-guide-promotion/v1'
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
        $rawSourceId = [string](Get-InputValue $programme 'SourceId')
        $rawChannelId = [string](Get-InputValue $programme 'ChannelId')
        $canonicalEventId = [string](Get-InputValue $programme 'CanonicalEventId')
        if ([string]::IsNullOrWhiteSpace($canonicalEventId)) { $canonicalEventId = $null }
        else { $canonicalEventId = $canonicalEventId.Trim() }
        $sourceLabel = Get-SafeOptionalText (Get-InputValue $programme 'SourceLabel') 128
        if ($null -eq $sourceLabel) { $sourceLabel = if ($rawSourceId -ceq 'accepted-guide') { 'Accepted guide' } else { 'Source' } }
        $identity = [ordered]@{
            Correlation = if ($null -ne $canonicalEventId) { 'ExplicitEvent' } else { 'ChannelOccurrence' }
            CanonicalEventId = if ($null -ne $canonicalEventId) { $canonicalEventId } else { '' }
            SourceId = if ($null -eq $canonicalEventId) { $rawSourceId } else { '' }
            ChannelId = if ($null -eq $canonicalEventId) { $rawChannelId } else { '' }
            Title = $safeTitleKey
            Subtitle = $safeSubtitleKey
            EpisodeNumber = if ($null -eq $episodeNumber) { '' } else { $episodeNumber.ToLowerInvariant() }
            StartUtc = $startText
            StopUtc = $stopText
            RowEvidence = if ($null -eq $canonicalEventId) {
                [ordered]@{
                    Title = $title
                    Subtitle = $subtitle
                    EpisodeNumber = $episodeNumber
                    Description = $description
                    RecognizedCategoryKeys = $sourceCategoryKeys
                    SourceCategories = $sourceCategoryEvidence
                    Kind = $declaredKind
                    Sport = $sport
                    League = $league
                    HomeParticipant = $homeParticipant
                    AwayParticipant = $awayParticipant
                    Promotion = $promotion
                    IsNew = [bool](Get-InputValue $programme 'IsNew')
                    IsLive = [bool](Get-InputValue $programme 'IsLive')
                    IsPremiere = [bool](Get-InputValue $programme 'IsPremiere')
                    SourceLabel = $sourceLabel
                }
            } else { $null }
        }
        $itemId = Get-ChannelForgeDomainHash -Domain 'one-guide-item/v1' -InputObject $identity
        if ($sourceReferences.ContainsKey($rawSourceId)) { $sourceId = $sourceReferences[$rawSourceId] }
        else {
            $sourceId = Get-OpaqueIdentifier $rawSourceId 'one-guide-source/v1' 'accepted-guide'
            $sourceReferences[$rawSourceId] = $sourceId
        }
        if ($channelReferences.ContainsKey($rawChannelId)) { $channelReference = $channelReferences[$rawChannelId] }
        else {
            $channelReference = Get-OpaqueIdentifier $rawChannelId 'one-guide-channel/v1'
            $channelReferences[$rawChannelId] = $channelReference
        }
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
                ItemId = $itemId
                Kind = $null
                HasExplicitKind = $false
                KindConflict = $false
                Title = $title
                Subtitle = $subtitle
                Description = $description
                EpisodeNumber = $episodeNumber
                StartUtc = $startText
                StopUtc = $stopText
                StartUtcTicks = $start.UtcTicks
                StopUtcTicks = $stop.UtcTicks
                Status = $status
                HasGenericSports = $hasGenericSports
                HasSpecificSport = $hasSpecificSport
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
        if ($null -ne $declaredKind -and -not $group.KindConflict) {
            if (-not $group.HasExplicitKind) {
                $group.Kind = $declaredKind
                $group.HasExplicitKind = $true
            }
            elseif ($group.Kind -cne $declaredKind) {
                $group.Kind = 'Programme'
                $group.KindConflict = $true
            }
        }
        if ($hasGenericSports) { $group.HasGenericSports = $true }
        if ($hasSpecificSport) { $group.HasSpecificSport = $true }
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

        if ($null -ne $sport -and ($null -eq $group.Sport -or [StringComparer]::Ordinal.Compare($sport, [string]$group.Sport) -lt 0)) { $group.Sport = $sport }
        if ($null -ne $league -and ($null -eq $group.League -or [StringComparer]::Ordinal.Compare($league, [string]$group.League) -lt 0)) { $group.League = $league }
        if ($null -ne $homeParticipant -and ($null -eq $group.HomeParticipant -or [StringComparer]::Ordinal.Compare($homeParticipant, [string]$group.HomeParticipant) -lt 0)) { $group.HomeParticipant = $homeParticipant }
        if ($null -ne $awayParticipant -and ($null -eq $group.AwayParticipant -or [StringComparer]::Ordinal.Compare($awayParticipant, [string]$group.AwayParticipant) -lt 0)) { $group.AwayParticipant = $awayParticipant }
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
        $allOfferings = [object[]]@($group.Offerings.Values)
        if ($allOfferings.Count -gt 1) { [Array]::Sort($allOfferings, $offeringComparison) }
        $offeringCount = $allOfferings.Count
        $offeringLimit = [Math]::Min($offeringCount, 16)
        if ($offeringCount -gt $offeringLimit) {
            $offerings = [object[]]::new($offeringLimit)
            [Array]::Copy($allOfferings, $offerings, $offeringLimit)
        }
        else { $offerings = $allOfferings }
        if ($group.HasGenericSports -and $group.HasSpecificSport) {
            [void]$group.CategoryKeys.Remove('other-sports')
        }
        $orderedCategories = [System.Collections.Generic.List[string]]::new()
        foreach ($taxonomyKey in $taxonomyOrder) {
            if ($group.CategoryKeys.Contains($taxonomyKey)) { [void]$orderedCategories.Add($taxonomyKey) }
        }
        $finalKind = if ($group.HasExplicitKind -and -not $group.KindConflict) { $group.Kind } else { 'Programme' }
        $itemProjection = [ordered]@{
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
            OfferingCount = $offeringCount
            OfferingsTruncated = ($offeringCount -gt $offeringLimit)
            FreshnessState = 'Unknown'
            ConfidenceState = 'Unknown'
            ConfidenceScore = $null
        }
        if ($ReturnCatalogue) {
            $itemProjection.StartUtcTicks = $group.StartUtcTicks
            $itemProjection.StopUtcTicks = $group.StopUtcTicks
        }
        $items.Add([pscustomobject]$itemProjection)
    }
    $orderedItems = $items.ToArray()
    [Array]::Sort($orderedItems, $itemComparison)
    }
    if ($ReturnCatalogue) { return $orderedItems }
    if ($Query -eq 'Category') {
        if ([string]::IsNullOrWhiteSpace($CategoryKey)) { throw 'CategoryKey is required for a category query.' }
        $CategoryKey = $CategoryKey.ToLowerInvariant()
        if ($taxonomyOrder -cnotcontains $CategoryKey) { throw "Unsupported One Guide category '$CategoryKey'." }
    }
    if ($CurrentAndUpcomingOnly -and $Query -ne 'Category') { throw 'CurrentAndUpcomingOnly is valid only for a category query.' }
    if ($Query -eq 'Details' -and [string]::IsNullOrWhiteSpace($ItemId)) { throw 'ItemId is required for a details query.' }

    $selected = [System.Collections.Generic.List[object]]::new()
    $totalCount = 0
    $pageEnd = [int64]$Offset + [int64]$MaximumItems
    foreach ($item in $orderedItems) {
        $status = [string]$item.Status
        if ($UseCatalogue) {
            $startTicks = [long]$item.StartUtcTicks
            $stopTicks = [long]$item.StopUtcTicks
            $status = if ($startTicks -le $evaluation.UtcTicks -and $stopTicks -gt $evaluation.UtcTicks) { 'Live' }
                elseif ($startTicks -gt $evaluation.UtcTicks -and $startTicks -le $startingSoonEnd.UtcTicks) { 'StartingSoon' }
                elseif ($startTicks -gt $evaluation.UtcTicks) { 'Upcoming' }
                else { 'Past' }
        }
        $include = switch ($Query) {
            'LiveNow' { $status -ceq 'Live' }
            'StartingSoon' { $status -ceq 'StartingSoon' }
            'Category' {
                if ($CategoryKey -ceq 'live-now') { $status -ceq 'Live' }
                elseif ($CategoryKey -ceq 'starting-soon') { $status -ceq 'StartingSoon' }
                elseif ($CurrentAndUpcomingOnly -and $status -ceq 'Past') { $false }
                else { $item.CategoryKeys -ccontains $CategoryKey }
            }
            'Details' { [string]$item.ItemId -ceq $ItemId }
        }
        if ($include) {
            if ([int64]$totalCount -ge [int64]$Offset -and [int64]$totalCount -lt $pageEnd) { [void]$selected.Add($item) }
            $totalCount++
        }
    }
    $returned = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $selected.Count; $index++) {
        $item = $selected[$index]
        $itemStatus = [string]$item.Status
        if ($UseCatalogue) {
            $itemStatus = if ([long]$item.StartUtcTicks -le $evaluation.UtcTicks -and [long]$item.StopUtcTicks -gt $evaluation.UtcTicks) { 'Live' }
                elseif ([long]$item.StartUtcTicks -gt $evaluation.UtcTicks -and [long]$item.StartUtcTicks -le $startingSoonEnd.UtcTicks) { 'StartingSoon' }
                elseif ([long]$item.StartUtcTicks -gt $evaluation.UtcTicks) { 'Upcoming' }
                else { 'Past' }
            $categorySet = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($category in $item.CategoryKeys) {
                if ($category -notin @('live-now', 'starting-soon')) { [void]$categorySet.Add([string]$category) }
            }
            if ($itemStatus -eq 'Live') { [void]$categorySet.Add('live-now') }
            elseif ($itemStatus -eq 'StartingSoon') { [void]$categorySet.Add('starting-soon') }
            $categoriesForItem = @($taxonomyOrder | Where-Object { $categorySet.Contains($_) })
            $copy = [ordered]@{}
            foreach ($property in $item.PSObject.Properties) {
                if ($property.Name -notin @('StartUtcTicks', 'StopUtcTicks')) { $copy[$property.Name] = $property.Value }
            }
            $copy.Status = $itemStatus
            $copy.CategoryKeys = $categoriesForItem
            $item = [pscustomobject]$copy
        }
        [void]$returned.Add($item)
    }
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
