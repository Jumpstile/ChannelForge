function Get-ChannelForgeEventChannelCandidate {
    # event-channel/v2, slice 1: report only. One record per channel that looks like an event
    # channel (PPV 1 and similar), with a confidence and plain reasons. Pure: no file access,
    # nothing stored, nothing hashed. Rules and measured counts are in
    # docs\planning\EVENT-AWARE-CHANNELS-DESIGN-NOTE.md (part A).
    # Each Channel needs Key, DisplayName, GroupTitle, Category and Programmes (Title, Start, Stop).
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Channel)

    $fillers = Get-ChannelForgeEventFillerTitle
    $ppvWords = @([pscustomobject]@{ Key = 'ppv'; Aliases = @('ppv', 'pay per view') })
    $eventWords = @([pscustomobject]@{ Key = 'event'; Aliases = @('ppv', 'pay per view', 'event', 'events', 'ufc', 'wwe', 'aew', 'boxing', 'fight', 'wrestling', 'live event') })
    $sportsKeys = @(Get-ChannelForgeOneGuideCategoryRegistry | Where-Object { $_.Group -ceq 'sports' } | ForEach-Object { [string]$_.Key })
    $normalize = { param([string]$Text) ConvertTo-ChannelForgeEventTitleKey -Text $Text }

    foreach ($item in $Channel) {
        $name = & $normalize ([string]$item.DisplayName)
        $ppvHit = @(Find-ChannelForgeCategoryWord -Text $name -Registry $ppvWords -Property Aliases)
        # The shared matcher is whole-word only; also accept ppv plus digits (PPV1, PPV2). Not SKYPPV.
        if ($ppvHit.Count -eq 0) {
            $ppvDigits = [regex]::Match($name, '(?<![\p{L}\p{N}])ppv\d+(?![\p{L}\p{N}])')
            if ($ppvDigits.Success) { $ppvHit = @([pscustomobject]@{ Key = 'ppv'; Word = $ppvDigits.Value }) }
        }
        $eventHit = @(Find-ChannelForgeCategoryWord -Text $name -Registry $eventWords -Property Aliases)
        $programmes = @($item.Programmes)

        $total = 0.0; $placeholder = 0.0; $long = 0.0; $realTitles = @{}
        foreach ($programme in $programmes) {
            $hours = ([datetimeoffset]$programme.Stop - [datetimeoffset]$programme.Start).TotalHours
            if ($hours -le 0) { continue }
            $title = & $normalize ([string]$programme.Title)
            $total += $hours
            # A title that echoes the channel name (equal, or one starts with the other, shorter side 4+ chars) is a placeholder.
            $short = [math]::Min($title.Length, $name.Length)
            $echo = $short -ge 4 -and ($name.StartsWith($title, [StringComparison]::Ordinal) -or $title.StartsWith($name, [StringComparison]::Ordinal))
            if ($fillers -contains $title -or $title -ceq $name -or $echo) { $placeholder += $hours }
            else { $realTitles[$title] = $true; if ($hours -ge 6) { $long += $hours } }
        }
        $share = if ($total -gt 0) { $placeholder / $total } else { 0.0 }
        $percent = [int][math]::Round($share * 100)
        $reasons = [System.Collections.Generic.List[string]]::new()
        $confidence = $null

        if ($ppvHit.Count -gt 0) {
            $reasons.Add("name has `"$($ppvHit[0].Word)`"")
            # Always high, unless the guide shows several different real programmes.
            if ($realTitles.Count -ge 3 -and $share -le 0.5) { $confidence = 'medium'; $reasons.Add("$($realTitles.Count) different real programmes, so the normal guide is likely fine") }
            else { $confidence = 'high'; if ($total -gt 0) { $reasons.Add("$percent% of guide time is placeholder titles") } }
        }
        elseif ($eventHit.Count -gt 0) {
            $reasons.Add("name has `"$($eventHit[0].Word)`"")
            if ($total -eq 0) { $confidence = 'medium'; $reasons.Add('no guide data') }
            elseif ($share -gt 0.5) { $confidence = 'high'; $reasons.Add("$percent% of guide time is placeholder titles") }
            else { $confidence = 'medium'; $reasons.Add('real programmes in the guide') }
        }
        elseif ($sportsKeys -contains [string]$item.Category -and $total -gt 0 -and $long / $total -gt 0.5) {
            $confidence = 'low'
            $reasons.Add("category $($item.Category); most guide time is in blocks of 6 hours or more")
        }
        if ($null -eq $confidence) { continue }

        [pscustomobject][ordered]@{
            Key         = [string]$item.Key
            DisplayName = [string]$item.DisplayName
            GroupTitle  = [string]$item.GroupTitle
            Confidence  = $confidence
            Reasons     = @($reasons)
        }
    }
}

function Get-ChannelForgeEventFillerTitle {
    # Placeholder titles, compared after ConvertTo-ChannelForgeEventTitleKey. Extend here.
    @('next event coming soon', 'sign off', 'channel no longer available', 'to be announced', 'tba', 'tbd',
        'no event', 'no events', 'no live event', 'event not started', 'coming soon', 'event offline',
        'pay per view', 'ppv', 'event', 'events')
}

function ConvertTo-ChannelForgeEventTitleKey {
    # Lowercase, punctuation to single spaces. The one title comparison rule for event channels.
    [CmdletBinding()]
    param([string]$Text)
    ((($Text.ToLowerInvariant() -replace '[^\p{L}\p{N}]+', ' ')).Trim())
}

function Get-ChannelForgeEventChannelInput {
    # Joins the candidate channels, their category and their provider programmes into the
    # shape Get-ChannelForgeEventChannelCandidate reads. Programmes join on the exact tvg-id.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [Parameter(Mandatory)][object]$CategoryReport,
        [AllowEmptyCollection()][object[]]$Programme = @()
    )

    $categoryOf = @{}
    foreach ($row in $CategoryReport.Rows) { if ($null -ne $row.Category) { $categoryOf[[string]$row.ChannelKey] = [string]$row.Category } }
    $byGuideId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $Programme) {
        $guideId = [string]$entry.RawChannelId
        if (-not $byGuideId.ContainsKey($guideId)) { $byGuideId[$guideId] = [System.Collections.Generic.List[object]]::new() }
        $byGuideId[$guideId].Add([pscustomobject]@{ Title = [string]$entry.Title; Start = $entry.Start; Stop = $entry.End })
    }
    foreach ($channel in @(Read-ChannelForgeCandidateChannels -Directory $CandidateDirectory)) {
        $key = Get-ChannelForgeChannelKey -Url ([string]$channel.Url)
        $guideId = [string]$channel.TvgId
        [pscustomobject]@{
            Key = $key; DisplayName = [string]$channel.DisplayName; GroupTitle = [string]$channel.Group
            Category = $categoryOf[$key]
            Programmes = $(if ($guideId -and $byGuideId.ContainsKey($guideId)) { @($byGuideId[$guideId]) } else { @() })
        }
    }
}
