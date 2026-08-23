function Read-ChannelForgeM3UReader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.TextReader]$Reader,

        [string]$Provider = '',

        [string]$Playlist = ''
    )

    if ($null -eq $Reader) {
        throw 'M3U reader cannot be empty.'
    }

    $channels = [System.Collections.Generic.List[Channel]]::new()
    $sawHeader = $false
    $pending = $null
    $lineNumber = 0

    while ($null -ne ($line = $Reader.ReadLine())) {
        $lineNumber++

        # StreamReader normally consumes a UTF-8 BOM. Removing it here as well
        # keeps the shared core correct for StringReader and injected streams.
        if ($line.Length -gt 0 -and $line[0] -eq [char]0xFEFF) {
            $line = $line.Substring(1)
        }

        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if (-not $sawHeader) {
            if ($trimmed -cne '#EXTM3U') {
                throw "M3U playlist must begin with #EXTM3U (line $lineNumber)."
            }

            $sawHeader = $true
            continue
        }

        if ($trimmed.StartsWith('#EXTINF:', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($null -ne $pending) {
                throw "M3U playlist contains an #EXTINF without a stream URI (line $lineNumber)."
            }

            $displayName = ''
            $commaIndex = $trimmed.LastIndexOf(',')
            if ($commaIndex -ge 0 -and $commaIndex -lt ($trimmed.Length - 1)) {
                $displayName = $trimmed.Substring($commaIndex + 1).Trim()
            }

            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $displayName = 'Unknown Channel'
            }

            $tvgId = ''
            $tvgName = ''
            $logo = ''
            $group = ''

            if ($trimmed -match 'tvg-id="([^"]*)"') {
                $tvgId = $Matches[1]
            }

            if ($trimmed -match 'tvg-name="([^"]*)"') {
                $tvgName = $Matches[1]
            }

            if ($trimmed -match 'tvg-logo="([^"]*)"') {
                $logo = $Matches[1]
            }

            if ($trimmed -match 'group-title="([^"]*)"') {
                $group = $Matches[1]
            }

            $pending = [pscustomobject]@{
                DisplayName = $displayName
                TvgId       = $tvgId
                TvgName     = $tvgName
                Logo        = $logo
                Group       = $group
                LineNumber  = $lineNumber
            }
            continue
        }

        # M3U comments and directives may occur between a record and its URI.
        # A second EXTINF is handled above as an incomplete previous record.
        if ($trimmed.StartsWith('#')) {
            continue
        }

        if ($null -eq $pending) {
            # Preserve the local parser's permissive treatment of text outside
            # a record while still requiring a valid header and complete pairs.
            continue
        }

        $channel = New-ChannelForgeChannel `
            -Provider $Provider `
            -Playlist $Playlist `
            -OriginalName $pending.DisplayName `
            -DisplayName $pending.DisplayName `
            -TvgId $pending.TvgId `
            -TvgName $pending.TvgName `
            -Logo $pending.Logo `
            -Group $pending.Group `
            -Url $trimmed

        [void]$channels.Add($channel)
        $pending = $null
    }

    if (-not $sawHeader) {
        throw 'M3U playlist is empty or has no #EXTM3U header.'
    }

    if ($null -ne $pending) {
        throw "M3U playlist ends with an #EXTINF without a stream URI (line $($pending.LineNumber))."
    }

    return @($channels.ToArray())
}
