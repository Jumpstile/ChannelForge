function Test-ChannelForgeSourceUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url
    )

    # Provider and EPG source URLs are treated as secrets (see docs/reference/SECURITY.md)
    # and as an untrusted ingestion boundary (see ADR 0005). Validate shape only;
    # never log or return the URL value from this function.
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsedUri)) {
        return $false
    }

    if ($parsedUri.Scheme -notin @('http', 'https')) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($parsedUri.Host)) {
        return $false
    }

    return $true
}
