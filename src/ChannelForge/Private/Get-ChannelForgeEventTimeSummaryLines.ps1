function Get-ChannelForgeEventTimeSummaryLines {
    <#
    .SYNOPSIS
    Turns the event time agreement into the few lines shown in the build summary (event-channel/v2, report only).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Agreement, [int]$Cap = 5)

    $events = @($Agreement.Events)
    if ($events.Count -eq 0 -and $Agreement.SkippedCount -eq 0) { return @() }
    $zone = try { [System.TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time') } catch { [System.TimeZoneInfo]::FindSystemTimeZoneById('America/New_York') }
    $eastern = {
        param([datetimeoffset]$Instant)
        $local = [System.TimeZoneInfo]::ConvertTime($Instant, $zone)
        $label = if ($zone.IsDaylightSavingTime($local)) { 'EDT' } else { 'EST' }
        '{0} {1}' -f $local.ToString('MMM d h:mm tt', [System.Globalization.CultureInfo]::InvariantCulture), $label
    }
    $agreed = @($events | Where-Object { $_.Status -ceq 'agreed' })
    $conflict = @($events | Where-Object { $_.Status -ceq 'conflict' })
    $single = @($events | Where-Object { $_.Status -ceq 'single-source' })
    $lines = @('', '## Event Times',
        "$($events.Count) events: $($agreed.Count) agreed, $($conflict.Count) conflict, $($single.Count) single-source. $($Agreement.SkippedCount) entries skipped (no usable start time or placeholder title). Nothing was changed.")
    foreach ($event in @($conflict | Select-Object -First $Cap)) {
        $times = @($event.Starts | ForEach-Object { "$($_.DisplayName) $(& $eastern $_.Start)" }) -join '; '
        $lines += "- Conflict: $($event.Title): $times"
    }
    if ($conflict.Count -gt $Cap) { $lines += "- and $($conflict.Count - $Cap) more conflicts" }
    return $lines
}
