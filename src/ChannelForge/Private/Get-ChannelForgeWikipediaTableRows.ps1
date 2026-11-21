function Get-ChannelForgeWikipediaTableRows {
    # Saved Wikipedia page text (HTML or wikitext) -> one array per table, each an array of rows, each row an array of
    # plain cell text. The header row comes first. A cell with rowspan or colspan is repeated in every row and column it
    # covers. Returns $null for a table whose spans do not form a clean rectangle (cannot be read safely).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $plain = {
        param([string]$Cell)
        $Cell = [regex]::Replace($Cell, '(?s)<sup[^>]*>.*?</sup>|<ref[^>]*>.*?</ref>|\{\{.*?\}\}|\[\d+\]', '')
        $Cell = [regex]::Replace($Cell, '\[\[(?:[^\]|]*\|)?([^\]]*)\]\]', '$1')
        $Cell = [regex]::Replace($Cell, "<[^>]+>|'{2,}", '')
        ([regex]::Replace([System.Net.WebUtility]::HtmlDecode($Cell), '\s+', ' ')).Trim()
    }
    # One cell: its plain text plus the rowspan and colspan found in its attribute text (1 when absent).
    $cellOf = {
        param([string]$Attributes, [string]$Body)
        $span = { param($Name) $m = [regex]::Match($Attributes, "(?i)\b$Name\s*=\s*[`"']?(\d+)"); if ($m.Success) { [Math]::Min([int]$m.Groups[1].Value, 100) } else { 1 } }
        [pscustomobject]@{ Text = (& $plain $Body); RowSpan = [Math]::Max(1, (& $span 'rowspan')); ColSpan = [Math]::Max(1, (& $span 'colspan')) }
    }
    if ($Text -match '<table') {
        foreach ($table in [regex]::Matches($Text, '(?is)<table[^>]*wikitable[^>]*>.*?</table>')) {
            $rows = foreach ($row in [regex]::Matches($table.Value, '(?is)<tr[^>]*>(.*?)</tr>')) {
                , @([regex]::Matches($row.Groups[1].Value, '(?is)<t([hd])([^>]*)>(.*?)</t\1>') | ForEach-Object { & $cellOf $_.Groups[2].Value $_.Groups[3].Value })
            }
            Expand-ChannelForgeTableSpans -Rows @($rows)
        }
        return
    }
    foreach ($table in [regex]::Matches($Text, '(?s)\{\|.*?\n\|\}')) {
        $rows = foreach ($chunk in ($table.Value -split '(?m)^\|-.*$')) {
            $cells = foreach ($line in ($chunk -split "`r?`n" | Where-Object { $_ -match '^[|!]' -and $_ -notmatch '^\|[+}]' })) {
                foreach ($cell in ($line.Substring(1) -split '(?:\|\||!!)')) {
                    # A leading attribute part such as: rowspan="2" style="x" | text
                    if ($cell -match '(?s)^\s*((?:[\w-]+\s*=\s*(?:"[^"]*"|''[^'']*'')\s*)+)\|(?!\|)(.*)$') { & $cellOf $Matches[1] $Matches[2] }
                    else { & $cellOf '' $cell }
                }
            }
            if (@($cells).Count -gt 0) { , @($cells) }
        }
        Expand-ChannelForgeTableSpans -Rows @($rows)
    }
}
