function Import-ChannelForgeM3UPlaylist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Provider = '',

        [string]$Playlist = ''
    )

    # M3U playlists are external input and must be treated as untrusted.
    # This parser only reads from disk and returns Channel domain objects.
    # It does not modify production data.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "M3U playlist not found: $Path"
    }

    $lines = Get-Content -LiteralPath $Path
    $channels = [System.Collections.ArrayList]::new()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        if ($line -notlike '#EXTINF:*') {
            continue
        }

        # The display name appears after the final comma in the EXTINF line.
        $displayName = ''
        $commaIndex = $line.LastIndexOf(',')
        if ($commaIndex -ge 0 -and $commaIndex -lt ($line.Length - 1)) {
            $displayName = $line.Substring($commaIndex + 1).Trim()
        }

        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $displayName = 'Unknown Channel'
        }

        # Extract common M3U attributes. Missing attributes are allowed.
        $tvgId = ''
        $tvgName = ''
        $logo = ''
        $group = ''

        if ($line -match 'tvg-id="([^"]*)"') {
            $tvgId = $Matches[1]
        }

        if ($line -match 'tvg-name="([^"]*)"') {
            $tvgName = $Matches[1]
        }

        if ($line -match 'tvg-logo="([^"]*)"') {
            $logo = $Matches[1]
        }

        if ($line -match 'group-title="([^"]*)"') {
            $group = $Matches[1]
        }

        $channel = New-ChannelForgeChannel `
            -Provider $Provider `
            -Playlist $Playlist `
            -OriginalName $displayName `
            -DisplayName $displayName `
            -TvgId $tvgId `
            -TvgName $tvgName `
            -Logo $logo `
            -Group $group

        [void]$channels.Add($channel)
    }

    return $channels
}