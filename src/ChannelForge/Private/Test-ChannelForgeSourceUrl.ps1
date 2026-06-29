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

    # Reject embedded credentials (e.g. https://example.invalid/REDACTED so secrets
    # never travel as part of the URL's userinfo component.
    if (-not [string]::IsNullOrEmpty($parsedUri.UserInfo)) {
        return $false
    }

    # Provider/EPG sources must be reachable public hosts, not the local
    # machine or internal network, to reduce SSRF risk once an HTTP fetch
    # is implemented (see Roadmap Milestone 4).
    if ($parsedUri.Host -ieq 'localhost') {
        return $false
    }

    $hostAddress = $null
    if ([System.Net.IPAddress]::TryParse($parsedUri.Host, [ref]$hostAddress)) {
        if (Test-ChannelForgeDisallowedIpAddress -Address $hostAddress) {
            return $false
        }
    }

    return $true
}
