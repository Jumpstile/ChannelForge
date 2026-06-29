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

    foreach ($source in $epgConfig.epg_sources | Sort-Object priority) {
        # EPG URLs are an untrusted ingestion boundary; validate shape, never log the value.
        if (-not (Test-ChannelForgeSourceUrl -Url $source.url)) {
            throw "EPG source '$($source.name)' has a malformed or unsupported URL."
        }

        [pscustomobject]@{
            Name     = $source.name
            Priority = [int]$source.priority
            Url      = $source.url
            Enabled  = [bool]$source.enabled
            Role     = $source.role
        }
    }
}