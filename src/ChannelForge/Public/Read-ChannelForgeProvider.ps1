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
            Name          = $source.name
            Group         = $source.group
            Url           = $source.url
            Enabled       = [bool]$source.enabled
            # Optional, local-only (issue #7 Phase 1); see schemas/provider.schema.json.
            # Empty string, never $null, so callers can test it with a plain if().
            LocalPlaylist = if ($source.local_playlist) { [string]$source.local_playlist } else { '' }
        }
    }
}