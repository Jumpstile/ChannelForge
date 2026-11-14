function Get-ChannelForgeEventProgrammeBlocks {
    # event-channel/v2, slice 3. Turns one channel's provider programs into ordered guide blocks with
    # no overlap and no hole across the window: real programs keep their title and times, every gap
    # shows the channel name (not provider filler). A title and a start are the minimum. A missing
    # stop runs to the next real program, or DefaultMinutes. Returns Blocks (Start, Stop, Title as UTC
    # datetime) or, when the channel must keep its normal guide, Reason. Pure.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Programme,
        [Parameter(Mandatory)][string]$ChannelName,
        [Parameter(Mandatory)][datetime]$WindowStart,
        [Parameter(Mandatory)][datetime]$WindowEnd,
        [int]$DefaultMinutes = 180
    )

    if ($Programme.Count -eq 0) { return [pscustomobject]@{ Blocks = @(); Reason = 'the provider guide has no programs for this channel' } }
    if (@($Programme | Where-Object { -not $_.Valid }).Count -gt 0) { return [pscustomobject]@{ Blocks = @(); Reason = 'a program time in the provider guide could not be read' } }

    $fillers = Get-ChannelForgeEventFillerTitle
    $nameKey = ConvertTo-ChannelForgeEventTitleKey -Text $ChannelName
    $real = @($Programme | Where-Object {
            $key = ConvertTo-ChannelForgeEventTitleKey -Text ([string]$_.Title)
            $key -and $fillers -notcontains $key -and $key -cne $nameKey
        } | Sort-Object { $_.Start.UtcDateTime } | Group-Object { $_.Start.UtcDateTime } | ForEach-Object { $_.Group[0] })

    $name = ConvertTo-ChannelForgeGuideSafeText -Value $ChannelName -MaximumLength 200
    $blocks = [System.Collections.Generic.List[object]]::new()
    $cursor = $WindowStart
    for ($i = 0; $i -lt $real.Count; $i++) {
        $start = [datetime]$real[$i].Start.UtcDateTime
        if ($start -lt $cursor) { $start = $cursor }
        $next = if ($i + 1 -lt $real.Count) { [datetime]$real[$i + 1].Start.UtcDateTime } else { $WindowEnd }
        $stop = if ($null -ne $real[$i].Stop) { [datetime]$real[$i].Stop.UtcDateTime } elseif ($i + 1 -lt $real.Count) { $next } else { $start.AddMinutes($DefaultMinutes) }
        if ($stop -gt $next) { $stop = $next }
        if ($stop -gt $WindowEnd) { $stop = $WindowEnd }
        if ($stop -le $start) { continue }
        if ($start -gt $cursor) { [void]$blocks.Add([pscustomobject]@{ Start = $cursor; Stop = $start; Title = $name }) }
        $title = ConvertTo-ChannelForgeGuideSafeText -Value $real[$i].Title -MaximumLength 200
        [void]$blocks.Add([pscustomobject]@{ Start = $start; Stop = $stop; Title = $(if ($title) { $title } else { $name }) })
        $cursor = $stop
    }
    if ($WindowEnd -gt $cursor) { [void]$blocks.Add([pscustomobject]@{ Start = $cursor; Stop = $WindowEnd; Title = $name }) }
    [pscustomobject]@{ Blocks = @($blocks.ToArray()); Reason = $null }
}
