function Read-ChannelForgeProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Provider file not found: $Path"
    }

    $provider = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    foreach ($source in $provider.sources) {
        # Provider URLs are an untrusted ingestion boundary and may contain
        # secret-like account/token data; validate shape, never log the value.
        if (-not (Test-ChannelForgeSourceUrl -Url $source.url)) {
            throw "Provider source '$($source.name)' has a malformed or unsupported URL."
        }

        [pscustomobject]@{
            Name    = $source.name
            Group   = $source.group
            Url     = $source.url
            Enabled = [bool]$source.enabled
        }
    }
}