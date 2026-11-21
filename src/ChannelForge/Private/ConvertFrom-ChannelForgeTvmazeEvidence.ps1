function ConvertFrom-ChannelForgeTvmazeEvidence {
    # Saved TVmaze JSON (an episode list, or a schedule where each item carries its show) -> event evidence records.
    # Date and Time are the show's local air date and time, converted from airstamp (UTC) with the show's zone, so
    # EST/EDT is right on the day. Time is $null when TVmaze gives no air time. TimeZone (IANA or Windows id) wins over
    # the zone TVmaze names for the network; with neither, America/New_York. No network; the caller saved the text.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string]$FetchedAt,
        [string]$TimeZone
    )

    foreach ($episode in @($Json | ConvertFrom-Json)) {
        $show = $episode.PSObject.Properties['show']
        $show = if ($show) { $show.Value } else { $null }
        $zoneId = if ($TimeZone) { $TimeZone } elseif ($show -and $show.network -and $show.network.country.timezone) { [string]$show.network.country.timezone } else { 'America/New_York' }
        $date = [string]$episode.airdate
        $time = $null
        if ($episode.airstamp -and $episode.airtime) {
            $stamp = [DateTimeOffset]::Parse([string]$episode.airstamp, [Globalization.CultureInfo]::InvariantCulture)
            $local = [TimeZoneInfo]::ConvertTime($stamp, [TimeZoneInfo]::FindSystemTimeZoneById($zoneId))
            $date = $local.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            $time = $local.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        }
        if (-not $date -or -not $episode.name) { continue }
        $kind = if ([string]$episode.type -like '*special') { 'special' } else { 'episode' }
        $name = if ($show -and $show.name) { "$($show.name): $($episode.name)" } else { [string]$episode.name }
        New-ChannelForgeEventEvidenceRecord -Kind $kind -Name $name -Date $date -Time $time -Source 'tvmaze.com' -License 'CC BY-SA 4.0' `
            -Attribution 'TVmaze' -FetchedAt $FetchedAt -Id "tvmaze:$($episode.id)"
    }
}
