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

    if (-not $supported -or -not [string]::IsNullOrWhiteSpace($rawUrl)) {
        throw 'Configured EPG source is remote or otherwise unsupported in the local-only XMLTV slice.'
    }

    if ([string]::IsNullOrWhiteSpace($rawPath)) {
        throw 'Configured EPG source has no local path.'
    }

    if ($rawPath -match '^[a-z][a-z0-9+.-]*://') {
        throw 'Configured XMLTV source accepts local file paths only; URL or network sources are not supported.'
    }

    $sourceId = if ($propertyNames -contains 'Name') { [string]$Source.Name } else { '' }

    return @(Import-ChannelForgeXmltvSource `
        -Path $rawPath.Trim() `
        -SourceId $sourceId `
        -MaxDocumentBytes $MaxDocumentBytes)
}
