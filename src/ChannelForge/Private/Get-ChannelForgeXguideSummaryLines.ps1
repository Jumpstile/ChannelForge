function Get-ChannelForgeXguideSummaryLines {
    <#
    .SYNOPSIS
    Turns a cross-guide report into the few lines shown in the build summary (xguide-compare/v1).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Report)

    $withData = @($Report.Guides | Where-Object { $_.ProgrammeCount -gt 0 })
    if ($withData.Count -lt 2 -or $Report.SharedChannelCount -eq 0) { return @() }

    $problems = @($Report.Counts.PSObject.Properties | Where-Object { $_.Value -gt 0 })
    $head = "Guide comparison: $($withData.Count) guides, $($Report.SharedChannelCount) shared channels"
    if ($problems.Count -eq 0) { return @("$head, all programmes agree.") }

    $lines = @('', '## Guide Comparison', "$head, $($Report.AgreeCount) programmes agree.",
        ('Differences: ' + ((@($problems | ForEach-Object { "$($_.Name) $($_.Value)" })) -join ', ') + '.'))
    foreach ($kind in @($problems.Name)) {
        $shown = @($Report.Findings | Where-Object { $_.Kind -ceq $kind })
        foreach ($f in $shown) { $lines += "- $($f.Message)" }
        if ($Report.Counts.$kind -gt $shown.Count) { $lines += "- and $($Report.Counts.$kind - $shown.Count) more $kind" }
    }
    $lines += 'Check the guide source or remove the guide that is wrong. Nothing was changed.'
    return $lines
}
