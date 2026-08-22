function Import-ChannelForgeConfiguredXmltvSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [psobject]$Source,

        [long]$MaxDocumentBytes = 268435456
    )

    if ($null -eq $Source) {
        throw 'A normalized EPG source record is required.'
    }

    $propertyNames = @($Source.PSObject.Properties.Name)
    $rawFormat = if ($propertyNames -contains 'Format') { [string]$Source.Format } else { '' }
    $format = if ([string]::IsNullOrWhiteSpace($rawFormat)) { 'xmltv' } else { $rawFormat.Trim().ToLowerInvariant() }

    if ($format -ne 'xmltv') {
        throw "Configured EPG source has unsupported format '$($rawFormat.Trim())'; only xmltv is supported."
    }

    $supported = if ($propertyNames -contains 'Supported') { [bool]$Source.Supported } else { $true }
    $rawUrl = if ($propertyNames -contains 'Url') { [string]$Source.Url } else { '' }
    $rawPath = if ($propertyNames -contains 'Path') { [string]$Source.Path } else { '' }
    $sourceKind = if ($propertyNames -contains 'SourceKind' -and
        -not [string]::IsNullOrWhiteSpace([string]$Source.SourceKind)) {
        ([string]$Source.SourceKind).Trim().ToLowerInvariant()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($rawUrl)) {
        'remote'
    }
    else {
        'local'
    }

    $sourceId = if ($propertyNames -contains 'Name') { [string]$Source.Name } else { '' }
    $isRemote = $sourceKind -eq 'remote' -or -not [string]::IsNullOrWhiteSpace($rawUrl)

    if ($isRemote) {
        if (-not $supported) {
            throw 'Configured EPG source is unsupported.'
        }

        $opened = $null
        try {
            $opened = Open-ChannelForgeRemoteXmltvSourceStream `
                -Source $Source `
                -MaxDocumentBytes $MaxDocumentBytes

            return @(Read-ChannelForgeXmltvDocument `
                -Stream $opened.Stream `
                -SourceId $sourceId `
                -SourcePath '' `
                -SourceKind 'remote' `
                -SourceReference $opened.SourceReference `
                -Compression $opened.Compression `
                -TransportContractVersion $opened.TransportContract `
                -HttpStatusCode $opened.StatusCode `
                -ContentType $opened.ContentType `
                -ContentEncodings $opened.ContentEncodings `
                -RawContentLength $opened.RawContentLength `
                -MaxDocumentBytes $MaxDocumentBytes)
        }
        finally {
            if ($null -ne $opened) {
                if ($null -ne $opened.Stream) {
                    try { $opened.Stream.Dispose() } catch { }
                }

                foreach ($resource in @($opened.Resources)) {
                    try { $resource.Dispose() } catch { }
                }
            }
        }
    }

    if (-not $supported) {
        throw 'Configured EPG source is unsupported.'
    }

    if ([string]::IsNullOrWhiteSpace($rawPath)) {
        throw 'Configured EPG source has no local path.'
    }

    if ($rawPath -match '^[a-z][a-z0-9+.-]*://') {
        throw 'Configured XMLTV source accepts local file paths only; URL or network sources are not supported.'
    }

    return @(Import-ChannelForgeXmltvSource `
        -Path $rawPath.Trim() `
        -SourceId $sourceId `
        -MaxDocumentBytes $MaxDocumentBytes)
}
