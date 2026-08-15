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

    # HTTPS-only: no downgrade path exists for provider/EPG source URLs
    # (locked security policy for the Milestone 4 XMLTV fetch slice, see
    # issue #89).
    if ($parsedUri.Scheme -ne 'https') {
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

    if (-not (Test-ChannelForgeSafeHostAddress -HostName $parsedUri.Host)) {
        return $false
    }

    return $true
}
