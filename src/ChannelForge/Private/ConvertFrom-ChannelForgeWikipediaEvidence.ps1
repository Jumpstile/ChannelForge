function ConvertFrom-ChannelForgeWikipediaEvidence {
    # Saved Wikipedia page (HTML or wikitext) + a profile file -> { Status, Reason, Records }. The profile (JSON) names
    # the page title, which wikitable (tableIndex, from 0; or tableId, tableHeading, or yearRange - see
    # Select-ChannelForgeWikipediaTables), the header text of each column (columns: date, name and optionally venue,
    # city) and the record Kind. Optional: "yearFrom": "heading" lets a Date cell without a year ("March 31") take the
    # year of its table; "allowShortRows": true accepts rows that lack their last cells (rows too short for a named
    # column are skipped and counted). A new league or show is a new profile, not new code. If the page does not fit
    # the profile, Status is PageChanged with the reason and no records; nothing is guessed. Wikipedia has no start
    # times, so Time is $null. A row whose date is not a real date (TBA) is skipped and counted in Skipped. A trailing
    # "(aired ...)" note on a date is dropped: the event date is the date before it.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$Revision,
        [Parameter(Mandatory)][string]$FetchedAt
    )

    $changed = { param($Why) [pscustomobject]@{ Status = 'PageChanged'; Reason = $Why; Records = @(); Skipped = 0 } }
    $profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    $title = [string]$profile.pageTitle
    $shortRows = $null -ne $profile.PSObject.Properties['allowShortRows'] -and [bool]$profile.allowShortRows
    $selection = Select-ChannelForgeWikipediaTables -Tables @(Get-ChannelForgeWikipediaTableRows -Text $Text -WithContext -AllowShortRows:$shortRows) -Profile $profile
    if ($selection.Reason) { return & $changed $selection.Reason }
    $yearFromHeading = $profile.PSObject.Properties['yearFrom'] -and [string]$profile.yearFrom -eq 'heading'
    $formats = [string[]]@('MMMM d, yyyy', 'MMM d, yyyy', 'd MMMM yyyy', 'yyyy-MM-dd')

    $records = @(); $skipped = 0
    foreach ($table in $selection.Tables) {
        $rows = $table.Rows
        $position = @{}
        foreach ($column in $profile.columns.PSObject.Properties) {
            $at = [array]::IndexOf(@($rows[0] | ForEach-Object { $_.ToLowerInvariant() }), ([string]$column.Value).ToLowerInvariant())
            if ($at -lt 0) { return & $changed "'$title': column '$($column.Value)' ($($column.Name)) not found." }
            $position[$column.Name] = $at
        }
        $cell = { param($Row, $Name) if ($position.ContainsKey($Name) -and $position[$Name] -lt $Row.Count) { $Row[$position[$Name]] } }
        foreach ($row in @($rows | Select-Object -Skip 1)) {
            $parsed = [datetime]::MinValue
            $name = & $cell $row 'name'
            $dateText = ([regex]::Replace([string](& $cell $row 'date'), '\s*\(aired\b[^)]*\)', '')).Trim()
            if ($yearFromHeading -and $table.Year -and $dateText -notmatch '\d{4}') { $dateText = "$dateText, $($table.Year)" }
            if (-not $name -or -not [datetime]::TryParseExact($dateText, $formats, [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$parsed)) { $skipped++; continue }
            $date = $parsed.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            $records += New-ChannelForgeEventEvidenceRecord -Kind ([string]$profile.kind) -Name $name -Date $date -Venue (& $cell $row 'venue') -City (& $cell $row 'city') `
                -Source "en.wikipedia.org/wiki/$($title -replace ' ', '_')" -License 'CC BY-SA 4.0' -Attribution 'Wikipedia' -FetchedAt $FetchedAt `
                -Id "wikipedia:$($title -replace ' ', '_')#$date|$name" -Revision $Revision
        }
    }
    if ($records.Count -eq 0) { return & $changed "'$title': no row had a readable date and name." }
    [pscustomobject]@{ Status = 'Ok'; Reason = $null; Records = $records; Skipped = $skipped }
}
