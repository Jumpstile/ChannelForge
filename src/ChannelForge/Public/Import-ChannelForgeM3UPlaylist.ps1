function Import-ChannelForgeM3UPlaylist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Provider = '',

        [string]$Playlist = ''
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "M3U playlist not found: $Path"
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fileStream = $null
    $reader = $null
    try {
        $fileStream = [System.IO.FileStream]::new(
            $fullPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read,
            8192,
            [System.IO.FileOptions]::SequentialScan)
        $reader = [System.IO.StreamReader]::new(
            $fileStream,
            [System.Text.UTF8Encoding]::new($false, $true),
            $true,
            8192,
            $false)

        return @(Read-ChannelForgeM3UReader `
            -Reader $reader `
            -Provider $Provider `
            -Playlist $Playlist)
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $fileStream) {
            $fileStream.Dispose()
        }
    }
}
