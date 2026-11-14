function Get-ChannelForgeEventChannelSummaryLines {
    <#
    .SYNOPSIS
    Turns event channel candidates into the few lines shown in the build summary (event-channel/v2, report only).
    #>
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Candidate = @(), [int]$Cap = 5)

    $found = @($Candidate)
    if ($found.Count -eq 0) { return @() }
    $high = @($found | Where-Object { $_.Confidence -ceq 'high' })
    $medium = @($found | Where-Object { $_.Confidence -ceq 'medium' })
    $low = @($found | Where-Object { $_.Confidence -ceq 'low' })
    $lines = @('', '## Event Channels',
        "$($found.Count) channels look like event channels: $($high.Count) high, $($medium.Count) medium, $($low.Count) low. Nothing was changed.")
    foreach ($row in @($high | Select-Object -First $Cap)) {
        $lines += "- $($row.DisplayName) (group '$($row.GroupTitle)', high): $(@($row.Reasons) -join '; ')"
    }
    if ($high.Count -gt $Cap) { $lines += "- and $($high.Count - $Cap) more" }
    return $lines
}
