function Get-ChannelForgeWikipediaTableRows {
    # Saved Wikipedia page text (HTML or wikitext) -> one array per table, each an array of rows, each row an array of
    # plain cell text. The header row comes first. Returns $null for a table when a row spans rows (cannot be read safely).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $plain = {
        param([string]$Cell)
        $Cell = [regex]::Replace($Cell, '(?s)<sup[^>]*>.*?</sup>|<ref[^>]*>.*?</ref>|\{\{.*?\}\}|\[\d+\]', '')
        $Cell = [regex]::Replace($Cell, '\[\[(?:[^\]|]*\|)?([^\]]*)\]\]', '$1')
        $Cell = [regex]::Replace($Cell, "<[^>]+>|'{2,}", '')
        ([regex]::Replace([System.Net.WebUtility]::HtmlDecode($Cell), '\s+', ' ')).Trim()
    }
    if ($Text -match '<table') {
        foreach ($table in [regex]::Matches($Text, '(?is)<table[^>]*wikitable[^>]*>.*?</table>')) {
            if ($table.Value -match '(?i)(row|col)span') { , $null; continue }
            , @(foreach ($row in [regex]::Matches($table.Value, '(?is)<tr[^>]*>(.*?)</tr>')) {
                    , @([regex]::Matches($row.Groups[1].Value, '(?is)<t([hd])[^>]*>(.*?)</t\1>') | ForEach-Object { & $plain $_.Groups[2].Value })
                })
        }
        return
    }
    foreach ($table in [regex]::Matches($Text, '(?s)\{\|.*?\n\|\}')) {
        if ($table.Value -match '(?i)(row|col)span') { , $null; continue }
        , @(foreach ($chunk in ($table.Value -split '(?m)^\|-.*$')) {
                $cells = foreach ($line in ($chunk -split "`r?`n" | Where-Object { $_ -match '^[|!]' -and $_ -notmatch '^\|[+}]' })) {
                    foreach ($cell in ($line.Substring(1) -split '(?:\|\||!!)') ) {
                        $clean = & $plain $cell
                        # Drop a leading attribute part such as: style="x" | text
                        if ($clean -match '^[\w-]+="[^"]*"\s*\|\s*(.*)$') { $clean = $Matches[1] }
                        $clean
                    }
                }
                if (@($cells).Count -gt 0) { , @($cells) }
            })
    }
}
