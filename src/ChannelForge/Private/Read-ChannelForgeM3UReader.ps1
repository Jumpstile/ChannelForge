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
            $rawDisplayName = ''
            $commaIndex = $trimmed.LastIndexOf(',')
            if ($commaIndex -ge 0 -and $commaIndex -lt ($trimmed.Length - 1)) {
                $displayName = $trimmed.Substring($commaIndex + 1).Trim()
                $rawDisplayName = $trimmed.Substring($commaIndex + 1)
            }

            if ([string]::IsNullOrWhiteSpace($displayName)) {
                $displayName = 'Unknown Channel'
            }

$tvgId = ''
$tvgIdPresence = 'Missing'
$tvgName = ''
$logo = ''
$group = ''
$channelNumber = ''

if ($trimmed -match '(?i)tvg-id="([^"]*)"') {
    $tvgIdPresence = 'Present'
    $tvgId = $Matches[1]
}

if ($trimmed -match '(?i)tvg-name="([^"]*)"') {
    $tvgName = $Matches[1]
}

if ($trimmed -match '(?i)tvg-logo="([^"]*)"') {
    $logo = $Matches[1]
}

if ($trimmed -match '(?i)group-title="([^"]*)"') {
    $group = $Matches[1]
}

if ($trimmed -match '(?i)tvg-chno="([^"]*)"') {
    $channelNumber = $Matches[1]
}

$pending = [pscustomobject]@{
    DisplayName   = $displayName
    RawDisplayName = $rawDisplayName
    TvgId         = $tvgId
    TvgIdPresence = $tvgIdPresence
    TvgName       = $tvgName
    Logo          = $logo
    Group         = $group
    ChannelNumber = $channelNumber
    LineNumber    = $lineNumber
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

# Raw occurrence data is additive evidence for candidate projections.  The
# Channel runtime object remains the semantic domain contract.
$channel | Add-Member -NotePropertyName RawTvgIdPresence -NotePropertyValue $pending.TvgIdPresence -Force
$channel | Add-Member -NotePropertyName RawTvgId -NotePropertyValue $(if ($pending.TvgIdPresence -eq 'Present') { $pending.TvgId } else { $null }) -Force
$channel | Add-Member -NotePropertyName RawTvgName -NotePropertyValue $pending.TvgName -Force
$channel | Add-Member -NotePropertyName RawGroupTitle -NotePropertyValue $pending.Group -Force
$channel | Add-Member -NotePropertyName RawLogo -NotePropertyValue $pending.Logo -Force
$channel | Add-Member -NotePropertyName RawChannelNumber -NotePropertyValue $pending.ChannelNumber -Force
$channel | Add-Member -NotePropertyName RawM3UOccurrence -NotePropertyValue ([pscustomobject][ordered]@{
        Version          = 'blocker-2-contract/v1'
        LogicalSourceId  = ''
        RawTvgIdPresence = $pending.TvgIdPresence
        RawTvgId         = if ($pending.TvgIdPresence -eq 'Present') { $pending.TvgId } else { $null }
        TvgName          = $pending.TvgName
        DisplayName      = $pending.RawDisplayName
        GroupTitle       = $pending.Group
        Logo             = $pending.Logo
        ChannelNumber    = $pending.ChannelNumber
        StreamUrl        = $trimmed
    }) -Force
$channel | Add-Member -NotePropertyName SourceLocalOrdinal -NotePropertyValue ($channels.Count) -Force
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
