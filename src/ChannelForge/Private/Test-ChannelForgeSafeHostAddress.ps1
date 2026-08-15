function Test-ChannelForgeSafeHostAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$HostName
    )

    # Host-level safety check for provider/EPG source URLs (see ADR 0005,
    # docs/reference/SECURITY.md). Only literal IP hosts are evaluated here;
    # a DNS name is accepted at this stage because resolved-address
    # validation (DNS-rebinding-safe pinning to the address actually used
    # for the connection) is deferred until the HTTP fetch work lands
    # (Roadmap Milestone 4 / issue #89) -- this function is the isolated,
    # unit-testable building block that step will call into, not the full
    # resolved-address check itself.
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return $false
    }

    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($HostName, [ref]$address)) {
        # Not a literal IP address (a DNS hostname) -- literal-address
        # checks do not apply; accept at this stage.
        return $true
    }

    return -not (Test-ChannelForgeDisallowedIpAddress -Address $address)
}
