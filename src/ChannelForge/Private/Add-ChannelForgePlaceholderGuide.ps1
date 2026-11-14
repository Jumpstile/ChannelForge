function Add-ChannelForgePlaceholderGuide {
    # OwnPlaceholder guide: for each channel, one name-only program per local day,
    # covering the same window as the programs already in the guide. Day boundaries
    # are local midnight in TimeZone, so a daylight saving day is 23 or 25 hours long
    # with no gap and no overlap. Returns the extended XMLTV bytes (as one byte[] item).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$XmltvBytes,
        [Parameter(Mandatory)][object[]]$Channel,
        [Parameter(Mandatory)][System.TimeZoneInfo]$TimeZone
    )

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $utf8.GetString($XmltvBytes)
    $stamp = [regex]::Matches($text, '<programme start="(\d{14}) \+0000" stop="(\d{14}) \+0000"')
    if ($stamp.Count -eq 0) { throw 'The guide has no programs, so a name-only guide cannot be built for it.' }
    $first = ($stamp | ForEach-Object { $_.Groups[1].Value } | Sort-Object | Select-Object -First 1)
    $last = ($stamp | ForEach-Object { $_.Groups[2].Value } | Sort-Object | Select-Object -Last 1)
    $format = 'yyyyMMddHHmmss'
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $windowStart = [datetime]::SpecifyKind([datetime]::ParseExact($first, $format, $culture), [System.DateTimeKind]::Utc)
    $windowEnd = [datetime]::SpecifyKind([datetime]::ParseExact($last, $format, $culture), [System.DateTimeKind]::Utc)

    $toUtc = {
        param([datetime]$localMidnight)
        $unspecified = [datetime]::SpecifyKind($localMidnight, [System.DateTimeKind]::Unspecified)
        if ($TimeZone.IsInvalidTime($unspecified)) { $unspecified = $unspecified.AddHours(1) }
        [datetime]::SpecifyKind([System.TimeZoneInfo]::ConvertTimeToUtc($unspecified, $TimeZone), [System.DateTimeKind]::Utc)
    }
    $blocks = [System.Collections.Generic.List[object]]::new()
    $day = [System.TimeZoneInfo]::ConvertTimeFromUtc($windowStart, $TimeZone).Date
    while ($true) {
        $dayStart = & $toUtc $day
        if ($dayStart -ge $windowEnd) { break }
        $dayEnd = & $toUtc $day.AddDays(1)
        $blockStart = if ($dayStart -gt $windowStart) { $dayStart } else { $windowStart }
        $blockEnd = if ($dayEnd -lt $windowEnd) { $dayEnd } else { $windowEnd }
        if ($blockEnd -gt $blockStart) { [void]$blocks.Add(@($blockStart, $blockEnd)) }
        $day = $day.AddDays(1)
    }

    $channelXml = [System.Text.StringBuilder]::new()
    $programmeXml = [System.Text.StringBuilder]::new()
    $stampFormat = "yyyyMMddHHmmss '+0000'"
    foreach ($item in @($Channel | Sort-Object { [string]$_.Id } -Unique)) {
        $id = [System.Security.SecurityElement]::Escape([string]$item.Id)
        $name = [System.Security.SecurityElement]::Escape([string]$item.Name)
        [void]$channelXml.Append("  <channel id=`"$id`"><display-name>$name</display-name></channel>`n")
        foreach ($block in $blocks) {
            [void]$programmeXml.Append("  <programme start=`"$($block[0].ToString($stampFormat, $culture))`" stop=`"$($block[1].ToString($stampFormat, $culture))`" channel=`"$id`"><title>$name</title></programme>`n")
        }
    }

    $open = [regex]::Match($text, '<tv(\s[^>]*)?>')
    $close = $text.LastIndexOf('</tv>', [System.StringComparison]::Ordinal)
    if (-not $open.Success -or $close -lt 0) { throw 'The guide could not be extended with name-only guides.' }
    $afterOpen = $open.Index + $open.Length
    $result = $text.Substring(0, $afterOpen) + "`n" + $channelXml.ToString() + $text.Substring($afterOpen, $close - $afterOpen) + $programmeXml.ToString() + $text.Substring($close)
    return , $utf8.GetBytes($result)
}
