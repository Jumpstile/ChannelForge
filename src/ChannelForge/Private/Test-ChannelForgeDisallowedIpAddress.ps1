function Test-ChannelForgeDisallowedIpAddress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.IPAddress]$Address
    )

    # Blocks loopback, link-local, and RFC1918 private ranges so provider/EPG
    # sources cannot point at the local machine or internal network (SSRF
    # hardening ahead of the HTTP fetch work in Roadmap Milestone 4).
    if ([System.Net.IPAddress]::IsLoopback($Address)) {
        return $true
    }

    if ($Address.IsIPv4MappedToIPv6) {
        $Address = $Address.MapToIPv4()
    }

    if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        # fe80::/10 link-local.
        if ($Address.IsIPv6LinkLocal) {
            return $true
        }

        return $false
    }

    $octets = $Address.GetAddressBytes()

    # 10.0.0.0/8
    if ($octets[0] -eq 10) {
        return $true
    }

    # 172.16.0.0/12
    if ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) {
        return $true
    }

    # 192.168.0.0/16
    if ($octets[0] -eq 192 -and $octets[1] -eq 168) {
        return $true
    }

    # 169.254.0.0/16 link-local.
    if ($octets[0] -eq 169 -and $octets[1] -eq 254) {
        return $true
    }

    return $false
}
