function Write-ChannelForgeChannelDecisions {
    # Writes the whole record list to a temp file, then swaps it in, so a crash never
    # leaves a half-written decisions file.
    # A v1 file stays v1 (a bare array) unless NumberRecord is given: the v2 object is written
    # only when the user saves a channel number. A file that is already v2 stays v2 and keeps
    # its saved numbers when only the guide choices change.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Record,
        [AllowEmptyCollection()][object[]]$NumberRecord
    )

    $guideRows = @($Record | Sort-Object { [string]$_.key } | ForEach-Object {
            $row = [ordered]@{ key = [string]$_.key; name = [string]$_.name; choice = [string]$_.choice }
            if (-not [string]::IsNullOrEmpty([string]$_.guideId)) { $row.guideId = [string]$_.guideId }
            $row.decidedAt = [string]$_.decidedAt
            $row
        })
    $isV2 = $PSBoundParameters.ContainsKey('NumberRecord')
    if (-not $isV2 -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $isV2 = [System.IO.File]::ReadAllText($Path).TrimStart().StartsWith('{')
        if ($isV2) { $NumberRecord = @(Read-ChannelForgeChannelDecisions -Path $Path -Section ChannelNumbers) }
    }
    $out = if ($isV2) {
        $numberRows = @($NumberRecord | Sort-Object { [string]$_.channelKey } | ForEach-Object {
                [ordered]@{ channelKey = [string]$_.channelKey; name = [string]$_.name; number = [int]$_.number; decidedAt = [string]$_.decidedAt }
            })
        [ordered]@{ schemaVersion = 'channel-decisions/v2'; guideChoices = $guideRows; channelNumbers = $numberRows }
    }
    else { $guideRows }
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $out -Depth 5), [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}
