function Expand-ChannelForgeTableSpans {
    # Table rows of cells { Text; RowSpan; ColSpan } -> rows of plain text with each spanned cell repeated in every
    # row and column it covers. Returns $null when the result is not a clean rectangle (rows of different width, or a
    # rowspan running past the last row), so the caller reports a changed page instead of guessing. With
    # -AllowShortRows, rows shorter than the header row are accepted (a row that simply lacks its last cells); a row
    # wider than the header still returns $null, except a one-cell note row, which is cut to the header width.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows, [switch]$AllowShortRows)

    $pending = @{}; $spanned = $false
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $Rows) {
        $line = [System.Collections.Generic.List[string]]::new()
        $place = {
            while ($pending.ContainsKey($line.Count)) {
                $held = $pending[$line.Count]
                $line.Add($held.Text)
                if (--$held.Left -le 0) { $pending.Remove($line.Count - 1) }
            }
        }
        foreach ($cell in $row) {
            & $place
            $width = $cell.ColSpan
            # A note row (one cell across the table, such as a legend) may overshoot the header; it is cut to the header width.
            if ($AllowShortRows -and @($row).Count -eq 1 -and $result.Count -gt 0) { $width = [Math]::Min($width, $result[0].Count) }
            $start = $line.Count; if ($width -gt 1) { $spanned = $true }
            for ($i = 0; $i -lt $width; $i++) {
                $line.Add($cell.Text)
                if ($cell.RowSpan -gt 1) { $spanned = $true; $pending[$start + $i] = @{ Text = $cell.Text; Left = $cell.RowSpan - 1 } }
            }
        }
        & $place
        $result.Add(@($line))
    }
    if ($pending.Count -gt 0) { return $null }
    $widths = @($result | ForEach-Object { $_.Count } | Sort-Object -Unique)
    if ($spanned -and $widths.Count -gt 1 -and (-not $AllowShortRows -or $widths[-1] -gt $result[0].Count)) { return $null }
    , @($result)
}
