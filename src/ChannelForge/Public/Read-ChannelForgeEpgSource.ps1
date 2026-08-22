function Read-ChannelForgeEpgSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "EPG source file not found: $Path"
    }

    $epgConfig = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    $configPath = [System.IO.Path]::GetFullPath($Path)
    $configDirectory = [System.IO.Path]::GetDirectoryName($configPath)

    $rawSources = @($epgConfig.epg_sources)
    $indexedSources = @(
        for ($index = 0; $index -lt $rawSources.Count; $index++) {
            [pscustomobject]@{
                Index  = $index
                Source = $rawSources[$index]
            }
        }
    )

    foreach ($indexedSource in @(
        $indexedSources | Sort-Object `
            @{ Expression = { [int]$_.Source.priority }; Ascending = $true }, `
            @{ Expression = { [int]$_.Index }; Ascending = $true }
    )) {
        $source = $indexedSource.Source
        $propertyNames = @($source.PSObject.Properties.Name)
        $rawPath = if ($propertyNames -contains 'path') { [string]$source.path } else { '' }
        $rawUrl = if ($propertyNames -contains 'url') { [string]$source.url } else { '' }
        $rawFormat = if ($propertyNames -contains 'format') { [string]$source.format } else { '' }

        $hasPath = -not [string]::IsNullOrWhiteSpace($rawPath)
        $hasUrl = -not [string]::IsNullOrWhiteSpace($rawUrl)

        if ($hasPath -eq $hasUrl) {
            throw "EPG source '$($source.name)' must specify exactly one of path or url."
        }

        $format = if ([string]::IsNullOrWhiteSpace($rawFormat)) {
            'xmltv'
        }
        else {
            $rawFormat.Trim().ToLowerInvariant()
        }

        if ($format -ne 'xmltv') {
            throw "EPG source '$($source.name)' has unsupported format '$($rawFormat.Trim())'; only xmltv is supported."
        }

        $resolvedPath = ''
        $supported = $false
        $unsupportedReason = ''
        $sourceKind = 'local'

        if ($hasUrl) {
            # EPG URLs are an untrusted ingestion boundary; validate shape, never log the value.
            if (-not (Test-ChannelForgeSourceUrl -Url $rawUrl)) {
                throw "EPG source '$($source.name)' has a malformed or unsupported URL."
            }

            $sourceKind = 'remote'
            $supported = $true
        }
        else {
            $resolvedPath = if ([System.IO.Path]::IsPathRooted($rawPath.Trim())) {
                [System.IO.Path]::GetFullPath($rawPath.Trim())
            }
            else {
                [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($configDirectory, $rawPath.Trim()))
            }

            $supported = $true
        }

        [pscustomobject]@{
            Name              = $source.name
            Priority          = [int]$source.priority
            Url               = $rawUrl
            ConfiguredPath    = $rawPath.Trim()
            Path              = $resolvedPath
            SourceKind        = $sourceKind
            Format            = $format
            Enabled           = [bool]$source.enabled
            Role              = $source.role
            Supported         = $supported
            UnsupportedReason = $unsupportedReason
            ConfigurationIndex = [int]$indexedSource.Index
        }
    }
}
