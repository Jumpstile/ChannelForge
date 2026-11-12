function Write-ChannelForgeChannelDecisions {
    # Writes the whole record list to a temp file, then swaps it in, so a crash never
    # leaves a half-written decisions file.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Record
    )

    $out = @($Record | Sort-Object { [string]$_.key } | ForEach-Object {
            $row = [ordered]@{ key = [string]$_.key; name = [string]$_.name; choice = [string]$_.choice }
            if (-not [string]::IsNullOrEmpty([string]$_.guideId)) { $row.guideId = [string]$_.guideId }
            $row.decidedAt = [string]$_.decidedAt
            $row
        })
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $out -Depth 4), [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}
