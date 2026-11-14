function Get-ChannelForgeXguideReport {
    <#
    .SYNOPSIS
    Compares the guides of one build where they overlap (xguide-compare/v1). Report only.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Programme = @(),
        [Parameter(Mandatory)][datetime]$BuildTimeUtc,
        [string[]]$GuideSourceId = @(),
        [int]$MaxPerKind = 5
    )

    $tolerance = [timespan]::FromMinutes(15)   # same value as NearTimeWindow in Compare-ChannelForgeXmltvGuides
    $behindBy = [timespan]::FromHours(24)
    $kindOrder = @('MissingChannel', 'StartShift', 'TitleDiffers', 'Unmatched', 'GuideBehind')
    $stamp = { param($t) $t.UtcDateTime.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
    $gapOf = { param($x, $y) [math]::Abs(($x.Start - $y.Start).Ticks) }

    # guide -> channel -> programmes. Channel key is RawChannelId, else ChannelId (as in Resolve-ChannelForgeM3UXmltvBinding).
    $guides = @{}
    foreach ($p in @($Programme)) {
        $key = if ([string]::IsNullOrEmpty($p.RawChannelId)) { [string]$p.ChannelId } else { [string]$p.RawChannelId }
        if ([string]::IsNullOrEmpty($key) -or $p.End -le $p.Start) { continue }
        $sid = [string]$p.SourceId
        if (-not $guides.ContainsKey($sid)) { $guides[$sid] = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal) }
        if (-not $guides[$sid].ContainsKey($key)) { $guides[$sid][$key] = [Collections.Generic.List[object]]::new() }
        $title = [string]$p.Title
        $guides[$sid][$key].Add([pscustomobject]@{ Start = $p.Start; End = $p.End; Title = $title; Norm = [regex]::Replace($title.Trim().ToLowerInvariant(), '\s+', ' ') })
    }
    $carriers = [Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
    $guideRows = foreach ($sid in @(@($guides.Keys) + @($GuideSourceId | Where-Object { $_ -and -not $guides.ContainsKey($_) }) | Sort-Object -Unique -CaseSensitive)) {
        $first = $null; $last = $null; $total = 0
        if ($guides.ContainsKey($sid)) {
            foreach ($key in $guides[$sid].Keys) {
                $guides[$sid][$key].Sort({ param($x, $y) $x.Start.CompareTo($y.Start) })
                if (-not $carriers.ContainsKey($key)) { $carriers[$key] = [Collections.Generic.List[string]]::new() }
                $carriers[$key].Add($sid)
                $total += $guides[$sid][$key].Count
                foreach ($x in $guides[$sid][$key]) {
                    if ($null -eq $first -or $x.Start -lt $first) { $first = $x.Start }
                    if ($null -eq $last -or $x.End -gt $last) { $last = $x.End }
                }
            }
        }
        [pscustomobject][ordered]@{
            SourceId = $sid; ProgrammeCount = $total
            ChannelCount = if ($guides.ContainsKey($sid)) { $guides[$sid].Count } else { 0 }
            FirstStart = $first; LastEnd = $last
            State = if ($total -eq 0) { 'empty' } elseif ($last.UtcDateTime -lt $BuildTimeUtc.ToUniversalTime()) { 'ended' } else { 'ok' }
        }
    }
    $guideRows = @($guideRows)
    $shared = @($carriers.Keys | Where-Object { $carriers[$_].Count -gt 1 })
    $counts = [ordered]@{}
    foreach ($k in $kindOrder) { $counts[$k] = 0 }
    $found = [Collections.Generic.List[object]]::new()
    $agree = 0
    $add = {
        param($kind, $channel, $sources, $start, $text)
        $counts[$kind]++
        $found.Add([pscustomobject][ordered]@{ Kind = $kind; ChannelId = $channel; SourceIds = @($sources); Start = $start; Message = $text })
    }

    if ($shared.Count -gt 0) {
        foreach ($key in $shared) {
            $ids = @($carriers[$key])
            for ($i = 0; $i -lt $ids.Count; $i++) {
                for ($j = $i + 1; $j -lt $ids.Count; $j++) {
                    $a = $ids[$i]; $b = $ids[$j]
                    $la = $guides[$a][$key]; $lb = $guides[$b][$key]
                    # Only the window both guides cover (widened by the tolerance so a shifted first programme still matches).
                    $from = $(if ($la[0].Start -gt $lb[0].Start) { $la[0].Start } else { $lb[0].Start }) - $tolerance
                    $endA = ($la | ForEach-Object { $_.End } | Sort-Object -Descending | Select-Object -First 1)
                    $endB = ($lb | ForEach-Object { $_.End } | Sort-Object -Descending | Select-Object -First 1)
                    $to = if ($endA -lt $endB) { $endA } else { $endB }
                    foreach ($side in @(@($a, $b, $la, $lb), @($b, $a, $lb, $la))) {
                        $me, $other, $mine, $theirs = $side
                        $isFirst = $me -ceq $a
                        $mine = @($mine | Where-Object { $_.Start -ge $from -and $_.Start -lt $to })
                        $theirs = @($theirs | Where-Object { $_.Start -ge $from -and $_.Start -lt $to })
                        $lo = 0
                        foreach ($m in $mine) {
                            while ($lo -lt $theirs.Count -and $theirs[$lo].Start -lt ($m.Start - $tolerance)) { $lo++ }
                            $exact = $null; $same = $null; $diff = $null
                            for ($n = $lo; $n -lt $theirs.Count -and $theirs[$n].Start -le ($m.Start + $tolerance); $n++) {
                                $t = $theirs[$n]
                                if ($t.Norm -ceq $m.Norm) {
                                    if ($t.Start -eq $m.Start) { $exact = $t; break }
                                    if ($null -eq $same -or (& $gapOf $t $m) -lt (& $gapOf $same $m)) { $same = $t }
                                }
                                elseif ($null -eq $diff -or (& $gapOf $t $m) -lt (& $gapOf $diff $m)) { $diff = $t }
                            }
                            if ($exact) { if ($isFirst) { $agree++ }; continue }
                            if ($same -or $diff) {
                                if (-not $isFirst) { continue }   # the first guide's pass already reported this pair
                                if ($same) { & $add 'StartShift' $key @($a, $b) $m.Start ('channel {0}: "{1}" starts {2} in {3}, {4} in {5}' -f $key, $m.Title, (& $stamp $m.Start), $me, (& $stamp $same.Start), $other) }
                                else { & $add 'TitleDiffers' $key @($a, $b) $m.Start ('channel {0}: {1} is "{2}" in {3}, "{4}" in {5}' -f $key, (& $stamp $m.Start), $m.Title, $me, $diff.Title, $other) }
                                continue
                            }
                            $near = $null
                            foreach ($t in $theirs) { if ($null -eq $near -or (& $gapOf $t $m) -lt (& $gapOf $near $m)) { $near = $t } }
                            $tail = if ($near) { 'nearest in {0} is "{1}" at {2}' -f $other, $near.Title, (& $stamp $near.Start) } else { "nothing in $other" }
                            & $add 'Unmatched' $key @($a, $b) $m.Start ('channel {0}: "{1}" at {2} in {3}; {4}' -f $key, $m.Title, (& $stamp $m.Start), $me, $tail)
                        }
                    }
                }
            }
        }
        $filled = @($guideRows | Where-Object { $_.ProgrammeCount -gt 0 })
        foreach ($key in @($carriers.Keys)) {
            $missing = @($filled | Where-Object { $carriers[$key] -cnotcontains $_.SourceId } | ForEach-Object { $_.SourceId })
            if ($missing.Count -gt 0) { & $add 'MissingChannel' $key @($carriers[$key]) $null ('channel {0}: in {1}, not in {2}' -f $key, (@($carriers[$key]) -join ', '), ($missing -join ', ')) }
        }
        $sharing = @($shared | ForEach-Object { $carriers[$_] } | ForEach-Object { $_ } | Sort-Object -Unique -CaseSensitive)
        $newest = $null
        foreach ($g in $guideRows) { if ($g.SourceId -cin $sharing -and ($null -eq $newest -or $g.LastEnd -gt $newest)) { $newest = $g.LastEnd } }
        foreach ($g in $guideRows) {
            $text = if ($g.State -eq 'empty') { "guide $($g.SourceId) has no programmes" }
            elseif ($g.State -eq 'ended') { "guide $($g.SourceId) ended $(& $stamp $g.LastEnd), before this build" }
            elseif ($g.SourceId -cin $sharing -and ($newest - $g.LastEnd) -gt $behindBy) {
                'guide {0} ends {1}, the newest guide ends {2} ({3} h behind)' -f $g.SourceId, (& $stamp $g.LastEnd), (& $stamp $newest), [int][math]::Floor(($newest - $g.LastEnd).TotalHours)
            }
            if ($text) { & $add 'GuideBehind' '' @($g.SourceId) $null $text }
        }
    }

    $seen = @{}
    $kept = foreach ($f in @($found | Sort-Object { $kindOrder.IndexOf($_.Kind) }, ChannelId, Start, { $_.SourceIds -join '|' })) {
        $seen[$f.Kind] = 1 + [int]$seen[$f.Kind]
        if ($seen[$f.Kind] -le $MaxPerKind) { $f }
    }
    return [pscustomobject][ordered]@{
        Contract = 'xguide-compare/v1'
        Guides = $guideRows
        SharedChannelCount = $shared.Count
        AgreeCount = $agree
        Counts = [pscustomobject]$counts
        Findings = @($kept)
        Truncated = (@($counts.Values | Where-Object { $_ -gt $MaxPerKind }).Count -gt 0)
    }
}
