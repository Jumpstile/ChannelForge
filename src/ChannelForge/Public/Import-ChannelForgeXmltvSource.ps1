function Import-ChannelForgeXmltvSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$SourceId = '',

        [long]$MaxDocumentBytes = 268435456
    )

    if ($Path -match '^[a-z][a-z0-9+.-]*://') {
        throw 'XMLTV ingestion accepts local file paths only; URL or network sources are not supported.'
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "XMLTV source not found: $Path"
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedSourceId = if ([string]::IsNullOrWhiteSpace($SourceId)) { $fullPath } else { $SourceId.Trim() }
    $opened = $null

    try {
        $opened = Open-ChannelForgeXmltvSourceStream `
            -Path $fullPath `
            -MaxDocumentBytes $MaxDocumentBytes

        return @(Read-ChannelForgeXmltvDocument `
            -Stream $opened.Stream `
            -SourceId $resolvedSourceId `
            -SourcePath $opened.SourcePath `
            -Compression $opened.Compression `
            -MaxDocumentBytes $MaxDocumentBytes)
    }
    finally {
        if ($null -ne $opened) {
            try {
                $opened.Stream.Dispose()
            }
            catch {
                # Preserve the parse/open result while still attempting all cleanup.
            }

            for ($i = $opened.Resources.Count - 1; $i -ge 0; $i--) {
                try {
                    $opened.Resources[$i].Dispose()
                }
                catch {
                    # Preserve the parse/open result while still attempting all cleanup.
                }
            }
        }
    }
}
