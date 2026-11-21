function Compare-ChannelForgeScheduleEvidence {
    # Compares one event channel's day plan with the saved schedule evidence for the same day. Channel: Name
    # and Blocks (Start, Title). Date: the day to check; without it, the day of the first event block.
    # Returns $null when there is nothing to compare (no evidence for that day, or no game title), else
    # Status Confirmed | NoEvidence | GuideMissing | Review, and one plain Question (none when Confirmed).
    # A team name without sport context is Review, never a guess. Pure.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Channel,
        [AllowEmptyCollection()][object[]]$Evidence = @(),
        [Nullable[datetime]]$Date = $null
    )

    $name = [string]$Channel.Name
    $eventBlocks = @(@($Channel.Blocks) | Where-Object { $_.Title -cne $name })
    # Block times are UTC; evidence dates are calendar days in the build time zone (the one the guide is written in).
    $localDay = { param($Utc) [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::SpecifyKind([datetime]$Utc, [DateTimeKind]::Utc), [TimeZoneInfo]::Local) }
    $day = if ($null -ne $Date) { $Date } elseif ($eventBlocks.Count -gt 0) { & $localDay $eventBlocks[0].Start } else { return $null }
    $dayText = ([datetime]$day).ToString('yyyy-MM-dd')
    $eventBlocks = @($eventBlocks | Where-Object { (& $localDay $_.Start).ToString('yyyy-MM-dd') -ceq $dayText })
    $dayRecord = @($Evidence | Where-Object { $_.Date -ceq $dayText -and (-not $_.Kind -or $_.Kind -eq 'game') })
    if ($dayRecord.Count -eq 0) { return $null }

    $resolve = {
        param([string]$Team, [string]$Opponent, [string]$Sport, [string]$Group)
        Resolve-ChannelForgeTeamAlias -Name $Team -Opponent $Opponent -Sport $Sport -Group $Group
    }
    $made = { param($Status, $Question) [pscustomobject]@{ Status = $Status; Date = $dayText; Question = $Question } }
    $recordKey = {
        param($Record)
        $homeSide = & $resolve $Record.Home $Record.Away $Record.Sport ''
        $awaySide = & $resolve $Record.Away $Record.Home $Record.Sport ''
        if ($homeSide.Status -eq 'Resolved' -and $awaySide.Status -eq 'Resolved') { (@($homeSide.Team, $awaySide.Team) | Sort-Object) -join '|' }
    }
    $evidenceKey = @($dayRecord | ForEach-Object { & $recordKey $_ } | Where-Object { $_ })

    if ($eventBlocks.Count -eq 0) {
        $unknown = @($dayRecord | Where-Object { $a = & $resolve $_.Home $_.Away $_.Sport $name; $a.Status -eq 'Resolved' })
        if ($unknown.Count -eq 0) { return $null }
        return & $made 'GuideMissing' "Schedule has a game for $($unknown[0].Home) and $($unknown[0].Away) on $dayText, but the guide has none. Keep the guide as is, or add the game?"
    }

    $first = $null
    foreach ($block in $eventBlocks) {
        if ([string]$block.Title -notmatch '^\s*(.+?)\s+(?:vs\.?|v|at|@)\s+(.+?)\s*$') { continue }
        $one = $Matches[1]; $two = $Matches[2]
        $a = & $resolve $one $two '' $name
        $b = & $resolve $two $one '' $name
        foreach ($unclear in @($a, $b | Where-Object { $_.Status -ne 'Resolved' })) {
            $who = if ($unclear -eq $a) { $one } else { $two }
            return & $made 'Review' "Cannot tell which team '$who' is on $dayText. $($unclear.Reason) Keep the guide as is, or pick the team?"
        }
        if ($evidenceKey -contains ((@($a.Team, $b.Team) | Sort-Object) -join '|')) { return & $made 'Confirmed' $null }
        if ($null -eq $first) { $first = "$($a.Team) and $($b.Team)" }
    }
    if ($null -eq $first) { return $null }
    & $made 'NoEvidence' "Schedule has no game for $first on $dayText. Keep the guide as is, or mark it cancelled?"
}
