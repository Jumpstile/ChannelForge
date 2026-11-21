function Get-ChannelForgeCatchupShape {
    <#
    .SYNOPSIS
    Classifies the catch-up shape each M3U stream declares. Report only.

    .DESCRIPTION
    Side read of the raw #EXTINF attributes. It does not use or change the M3U
    reader, so the raw digest is not affected. Ordinal counts completed streams
    the same way the reader does (SourceLocalOrdinal). Output never contains a
    URL, user, password or query text.

    Shape: path-template, query-template, declared-only or none.
    Family: the catchup mode word when it is a known one, else 'other' or ''.
    DeclaredDays: whole number from catchup-days, timeshift or tvg-rec, else $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.TextReader]$Reader
    )

    $knownFamilies = @('default', 'append', 'shift', 'flussonic', 'flussonic-ts', 'fs', 'xc', 'vod')
    $getAttribute = {
        param([string]$Line, [string]$Name)
        $m = [regex]::Match($Line, '(?i)(?<![\w-])' + [regex]::Escape($Name) + '="([^"]*)"')
        if ($m.Success) { return $m.Groups[1].Value }
        return $null
    }

    $ordinal = 0
    $lineNumber = 0
    $pendingLine = $null
    $header = $false
    while ($null -ne ($line = $Reader.ReadLine())) {
        $lineNumber++
        $trimmed = $line.TrimStart([char]0xFEFF).Trim()
        if ($trimmed.Length -eq 0) { continue }
        if (-not $header) { $header = $true; continue }
        if ($trimmed.StartsWith('#EXTINF:', [System.StringComparison]::OrdinalIgnoreCase)) {
            $pendingLine = [pscustomobject]@{ Text = $trimmed; Number = $lineNumber }
            continue
        }
        if ($trimmed.StartsWith('#') -or $null -eq $pendingLine) { continue }

        $mode = & $getAttribute $pendingLine.Text 'catchup'
        $source = & $getAttribute $pendingLine.Text 'catchup-source'
        $dayText = $null
        foreach ($name in 'catchup-days', 'timeshift', 'tvg-rec') {
            $dayText = & $getAttribute $pendingLine.Text $name
            if ($null -ne $dayText) { break }
        }

        $shape = 'none'
        if ($source) {
            $split = $source.IndexOf('?')
            $pathPart = if ($split -lt 0) { $source } else { $source.Substring(0, $split) }
            $queryPart = if ($split -lt 0) { '' } else { $source.Substring($split + 1) }
            $shape = if ($queryPart -match '\{[^}]*\}') { 'query-template' }
            elseif ($pathPart -match '\{[^}]*\}') { 'path-template' }
            else { 'declared-only' }
        }
        elseif ($null -ne $mode -or $null -ne $dayText) {
            $shape = 'declared-only'
        }

        $family = ''
        if ($null -ne $mode) {
            $family = if ($mode.ToLowerInvariant() -in $knownFamilies) { $mode.ToLowerInvariant() } else { 'other' }
        }
        $days = $null
        if ($null -ne $dayText -and $dayText -match '^\d{1,4}$') { $days = [int]$dayText }

        [pscustomobject][ordered]@{
            Ordinal      = $ordinal
            LineNumber   = $pendingLine.Number
            Shape        = $shape
            Family       = $family
            DeclaredDays = $days
        }
        $ordinal++
        $pendingLine = $null
    }
}
