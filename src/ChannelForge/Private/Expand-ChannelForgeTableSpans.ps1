function Expand-ChannelForgeTableSpans {
    # Table rows of cells { Text; RowSpan; ColSpan } -> rows of plain text with each spanned cell repeated in every
    # row and column it covers. Returns $null when the result is not a clean rectangle (rows of different width, or a
    # rowspan running past the last row), so the caller reports a changed page instead of guessing.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows)

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
            $start = $line.Count; if ($cell.ColSpan -gt 1) { $spanned = $true }
            for ($i = 0; $i -lt $cell.ColSpan; $i++) {
                $line.Add($cell.Text)
                if ($cell.RowSpan -gt 1) { $spanned = $true; $pending[$start + $i] = @{ Text = $cell.Text; Left = $cell.RowSpan - 1 } }
            }
        }
        & $place
        $result.Add(@($line))
    }
    if ($pending.Count -gt 0) { return $null }
    if ($spanned -and @($result | ForEach-Object { $_.Count } | Sort-Object -Unique).Count -gt 1) { return $null }
    , @($result)
}
