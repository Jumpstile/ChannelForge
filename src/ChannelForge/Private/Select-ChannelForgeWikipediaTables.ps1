function Select-ChannelForgeWikipediaTables {
    # Tables read with -WithContext + a profile -> { Tables; Reason }. Each table is { Rows; Year; Heading }. The profile
    # picks tables by tableId, by tableHeading, by yearRange ([first, last]; every table whose year is in range and whose
    # first header is the date column), or else by tableIndex. Year comes from the nearest heading when it is a plain
    # year ("1985"), else from the end of the table id ("Past_events_1985"). A table with no year at all is kept (its dates must then carry a year). Reason is set when nothing can be read.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tables, [Parameter(Mandatory)][object]$Profile)

    $title = [string]$Profile.pageTitle
    $yearOf = {
        param($Table)
        if ($Table.Heading -match '^\d{4}$') { [int]$Table.Heading }
        elseif ($Table.Id -match '(?:^|_)(\d{4})$') { [int]$Matches[1] }
    }
    $pick = {
        param($Table)
        [pscustomobject]@{ Rows = @($Table.Rows); Year = (& $yearOf $Table); Heading = $Table.Heading }
    }
    $has = { param($Name) $null -ne $Profile.PSObject.Properties[$Name] }
    # A table that is not an event list (for example a one-row label) has no date column and is never part of a choice.
    # Optional "dateColumnAnywhere": true accepts a table whose date header is not first (AEW lists Event first).
    $dateHeader = ([string]$Profile.columns.date).ToLowerInvariant()
    $anywhere = $null -ne $Profile.PSObject.Properties['dateColumnAnywhere'] -and [bool]$Profile.dateColumnAnywhere
    $isEventTable = {
        param($Table)
        if ($null -eq $Table.Rows) { return $true }
        if ($Table.Rows.Count -eq 0) { return $false }
        if ($anywhere) { return @($Table.Rows[0] | ForEach-Object { $_.ToLowerInvariant() }) -contains $dateHeader }
        $Table.Rows[0][0].ToLowerInvariant() -eq $dateHeader
    }

    if (& $has 'tableId') { $found = @($Tables | Where-Object { $_.Id -eq [string]$Profile.tableId }); $what = "table id '$($Profile.tableId)'" }
    elseif (& $has 'tableHeading') { $found = @($Tables | Where-Object { $_.Heading -eq [string]$Profile.tableHeading -and (& $isEventTable $_) }); $what = "table under heading '$($Profile.tableHeading)'" }
    elseif (& $has 'yearRange') {
        $first = [int]$Profile.yearRange[0]; $last = [int]$Profile.yearRange[1]
        $found = @($Tables | Where-Object {
                $year = & $yearOf $_
                ($null -eq $year -or ($year -ge $first -and $year -le $last)) -and (& $isEventTable $_)
            })
        $what = "event tables for $first-$last"
    }
    else {
        $index = [int]$Profile.tableIndex
        if ($index -ge $Tables.Count -or $null -eq $Tables[$index].Rows) { return [pscustomobject]@{ Tables = @(); Reason = "'$title': table $index not found or not readable." } }
        $found = @($Tables[$index]); $what = "table $index"
    }
    if ($found.Count -eq 0) { return [pscustomobject]@{ Tables = @(); Reason = "'$title': $what not found." } }
    foreach ($table in $found) {
        if ($null -eq $table.Rows) { return [pscustomobject]@{ Tables = @(); Reason = "'$title': $what includes a table (heading '$($table.Heading)') that cannot be read." } }
        if ($table.Rows.Count -lt 2) { return [pscustomobject]@{ Tables = @(); Reason = "'$title': $what has no data rows." } }
    }
    [pscustomobject]@{ Tables = @($found | ForEach-Object { & $pick $_ }); Reason = $null }
}
