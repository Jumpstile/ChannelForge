function ConvertFrom-ChannelForgeWikipediaEvidence {
    # Saved Wikipedia page (HTML or wikitext) + a profile file -> { Status, Reason, Records }. The profile (JSON) names
    # the page title, which wikitable (tableIndex, from 0), the header text of each column (columns: date, name and
    # optionally venue, city) and the record Kind. A new league or show is a new profile, not new code. If the page
    # does not fit the profile, Status is PageChanged with the reason and no records; nothing is guessed. Wikipedia
    # has no start times, so Time is $null. A row whose date is not a real date (TBA) is skipped and counted in Skipped.
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
    $tables = @(Get-ChannelForgeWikipediaTableRows -Text $Text)
    $index = [int]$profile.tableIndex
    if ($index -ge $tables.Count -or $null -eq $tables[$index]) { return & $changed "'$title': table $index not found or not readable." }
    $rows = @($tables[$index])
    if ($rows.Count -lt 2) { return & $changed "'$title': table $index has no data rows." }

    $position = @{}
    foreach ($column in $profile.columns.PSObject.Properties) {
        $at = [array]::IndexOf(@($rows[0] | ForEach-Object { $_.ToLowerInvariant() }), ([string]$column.Value).ToLowerInvariant())
        if ($at -lt 0) { return & $changed "'$title': column '$($column.Value)' ($($column.Name)) not found." }
        $position[$column.Name] = $at
    }
    $formats = [string[]]@('MMMM d, yyyy', 'MMM d, yyyy', 'd MMMM yyyy', 'yyyy-MM-dd')
    $cell = { param($Row, $Name) if ($position.ContainsKey($Name) -and $position[$Name] -lt $Row.Count) { $Row[$position[$Name]] } }
    $records = @(); $skipped = 0
    foreach ($row in @($rows | Select-Object -Skip 1)) {
        $parsed = [datetime]::MinValue
        $name = & $cell $row 'name'
        if (-not $name -or -not [datetime]::TryParseExact((& $cell $row 'date'), $formats, [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$parsed)) { $skipped++; continue }
        $date = $parsed.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $records += New-ChannelForgeEventEvidenceRecord -Kind ([string]$profile.kind) -Name $name -Date $date -Venue (& $cell $row 'venue') -City (& $cell $row 'city') `
            -Source "en.wikipedia.org/wiki/$($title -replace ' ', '_')" -License 'CC BY-SA 4.0' -Attribution 'Wikipedia' -FetchedAt $FetchedAt `
            -Id "wikipedia:$($title -replace ' ', '_')#$date|$name" -Revision $Revision
    }
    if ($records.Count -eq 0) { return & $changed "'$title': no row had a readable date and name." }
    [pscustomobject]@{ Status = 'Ok'; Reason = $null; Records = $records; Skipped = $skipped }
}
