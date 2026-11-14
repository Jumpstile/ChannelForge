function Get-ChannelForgeEventTimeAgreement {
    # event-channel/v2, slice 2: report only. For channels the detector rated (any level), reads
    # each channel's own programmes and compares the same event across channels. Same normalized
    # title with starts inside the window is one event. Starts are compared as instants. Each
    # channel keeps its own start; a difference is flagged, never resolved. Pure: nothing is
    # stored or hashed. A programme with no parseable start, or a placeholder title, is skipped
    # and counted. Channel is the detector input (Key, DisplayName, Programmes with Title, Start).
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Candidate = @(),
        [AllowEmptyCollection()][object[]]$Channel = @(),
        [int]$WindowMinutes = 15
    )

    # Filler titles: Test-ChannelForgeEventFillerKey
    $rated = @{}
    foreach ($row in $Candidate) { $rated[[string]$row.Key] = $true }
    $entries = [System.Collections.Generic.List[object]]::new()
    $skipped = 0
    foreach ($item in $Channel) {
        if (-not $rated.ContainsKey([string]$item.Key)) { continue }
        $name = ConvertTo-ChannelForgeEventTitleKey -Text ([string]$item.DisplayName)
        foreach ($programme in @($item.Programmes)) {
            $titleKey = ConvertTo-ChannelForgeEventTitleKey -Text ([string]$programme.Title)
            $start = [datetimeoffset]::MinValue
            $hasStart = $programme.Start -is [datetimeoffset] -or [datetimeoffset]::TryParse([string]$programme.Start, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$start)
            if ($programme.Start -is [datetimeoffset]) { $start = $programme.Start }
            if (-not $hasStart -or $start -eq [datetimeoffset]::MinValue -or -not $titleKey -or (Test-ChannelForgeEventFillerKey -Key $titleKey) -or $titleKey -ceq $name) { $skipped++; continue }
            $entries.Add([pscustomobject]@{ TitleKey = $titleKey; Title = ([string]$programme.Title).Trim(); ChannelKey = [string]$item.Key; DisplayName = [string]$item.DisplayName; Start = $start })
        }
    }

    $events = [System.Collections.Generic.List[object]]::new()
    $window = [timespan]::FromMinutes($WindowMinutes)
    foreach ($group in @($entries | Group-Object TitleKey | Sort-Object Name)) {
        $cluster = [System.Collections.Generic.List[object]]::new()
        $flush = {
            if ($cluster.Count -eq 0) { return }
            $starts = @($cluster | Sort-Object { $_.Start.UtcDateTime }, ChannelKey | ForEach-Object { [pscustomobject][ordered]@{ ChannelKey = $_.ChannelKey; DisplayName = $_.DisplayName; Start = $_.Start } })
            $channelKeys = @($starts | ForEach-Object { $_.ChannelKey } | Sort-Object -Unique)
            $distinct = @($starts | ForEach-Object { $_.Start.UtcDateTime } | Sort-Object -Unique)
            $status = if ($channelKeys.Count -lt 2) { 'single-source' } elseif ($distinct.Count -gt 1) { 'conflict' } else { 'agreed' }
            $events.Add([pscustomobject][ordered]@{ Title = $cluster[0].Title; Status = $status; ChannelKeys = $channelKeys; Starts = $starts })
        }
        foreach ($entry in @($group.Group | Sort-Object { $_.Start.UtcDateTime }, ChannelKey)) {
            if ($cluster.Count -gt 0 -and ($entry.Start - $cluster[0].Start) -gt $window) { & $flush; $cluster.Clear() }
            $cluster.Add($entry)
        }
        & $flush
    }
    [pscustomobject][ordered]@{ Events = @($events | Sort-Object { $_.Starts[0].Start.UtcDateTime }, Title); SkippedCount = $skipped }
}
