function Open-ChannelForgeXmltvSourceStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [long]$MaxDocumentBytes = 268435456
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'XMLTV source Path cannot be empty.'
    }

    if ($Path -match '^[a-z][a-z0-9+.-]*://') {
        throw 'XMLTV ingestion accepts local file paths only; URL or network sources are not supported.'
    }

    if ($MaxDocumentBytes -le 0) {
        throw 'MaxDocumentBytes must be greater than zero.'
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "XMLTV source not found: $Path"
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    $compression = 'none'
    $resources = [System.Collections.Generic.List[System.IDisposable]]::new()

    try {
        $fileStream = [System.IO.FileStream]::new(
            $fullPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read,
            65536,
            [System.IO.FileOptions]::SequentialScan
        )
        [void]$resources.Add($fileStream)

        switch ($extension) {
            '.xml' {
                if ($fileStream.Length -gt $MaxDocumentBytes) {
                    throw "XMLTV document exceeds the configured maximum of $MaxDocumentBytes bytes."
                }

                $contentStream = $fileStream
            }

            '.gz' {
                $compression = 'gzip'
                $contentStream = [System.IO.Compression.GZipStream]::new(
                    $fileStream,
                    [System.IO.Compression.CompressionMode]::Decompress,
                    $true
                )
                [void]$resources.Add($contentStream)
            }

            '.zip' {
                $compression = 'zip'
                $archive = [System.IO.Compression.ZipArchive]::new(
                    $fileStream,
                    [System.IO.Compression.ZipArchiveMode]::Read,
                    $true
                )
                [void]$resources.Add($archive)

                $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) })
                if ($entries.Count -ne 1) {
                    throw 'XMLTV zip sources must contain exactly one file entry.'
                }

                if ($entries[0].Length -gt $MaxDocumentBytes) {
                    throw "XMLTV document exceeds the configured maximum of $MaxDocumentBytes bytes."
                }

                $contentStream = $entries[0].Open()
                [void]$resources.Add($contentStream)
            }

            default {
                throw "Unsupported XMLTV source extension '$extension'. Use .xml, .gz, or .zip."
            }
        }

        $boundedStream = [BoundedStream]::new($contentStream, $MaxDocumentBytes)

        return [pscustomobject][ordered]@{
            Stream       = $boundedStream
            SourcePath   = $fullPath
            Compression  = $compression
            Resources    = @($resources)
        }
    }
    catch {
        for ($i = $resources.Count - 1; $i -ge 0; $i--) {
            try {
                $resources[$i].Dispose()
            }
            catch {
                # Preserve the original source-open failure.
            }
        }

        throw
    }
}
