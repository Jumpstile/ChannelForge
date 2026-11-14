function Get-ChannelForgeCategorySummaryLines {
    <#
    .SYNOPSIS
    Turns a category report into the few lines shown in the build summary (category-summary/v1).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Report)

    $summary = $Report.Summary
    $counts = @($summary.Categories.PSObject.Properties | Where-Object { $_.Value -gt 0 } | ForEach-Object { "$($_.Name) $($_.Value)" })
    $countsLine = "Categories: $($Report.ChannelCount) channels; $(if ($counts.Count) { $counts -join ', ' } else { 'none sorted' }); no category $($summary.Ungrouped)."

    $conflicts = @($Report.Rows | Where-Object { $_.Decision -ceq 'conflict' })
    $guesses = @($Report.Rows | Where-Object { $_.Confidence -ceq 'medium' })
    if ($conflicts.Count -eq 0 -and $guesses.Count -eq 0) { return @($countsLine) }

    $lines = @('', '## Category Check', $countsLine,
        "Low confidence: $($guesses.Count) (guessed from one word or a generic group). Conflicting evidence: $($conflicts.Count).")
    $suspects = @($conflicts + $guesses)
    foreach ($row in @($suspects | Select-Object -First 5)) {
        $lines += "- $($row.DisplayName) (group '$($row.ProviderGroup)'): $($row.Decision)"
    }
    if ($suspects.Count -gt 5) { $lines += "- and $($suspects.Count - 5) more" }
    $lines += 'To fix one, run Set-ChannelForgeCategoryOverride with its ChannelKey from Get-ChannelForgeCategoryReport.'
    return $lines
}
