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

        # fc00::/7 unique local addresses (ULA) -- not globally routable,
        # same SSRF rationale as RFC1918 IPv4 space.
        $addressBytes = $Address.GetAddressBytes()
        if (($addressBytes[0] -band 0xFE) -eq 0xFC) {
            return $true
        }

        # 2001:db8::/32 documentation range (RFC 3849) -- reserved for
        # examples and never a legitimate dereference target.
        if ($addressBytes[0] -eq 0x20 -and $addressBytes[1] -eq 0x01 -and
            $addressBytes[2] -eq 0x0D -and $addressBytes[3] -eq 0xB8) {
            return $true
        }

        return $false
    }

    $octets = $Address.GetAddressBytes()

    # 0.0.0.0/8 "this network".
    if ($octets[0] -eq 0) {
        return $true
    }

    # 10.0.0.0/8
    if ($octets[0] -eq 10) {
        return $true
    }

    # 100.64.0.0/10 shared address space (carrier-grade NAT).
    if ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127) {
        return $true
    }

    # 172.16.0.0/12
    if ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) {
        return $true
    }

    # 192.0.0.0/24 IETF protocol assignments.
    if ($octets[0] -eq 192 -and $octets[1] -eq 0 -and $octets[2] -eq 0) {
        return $true
    }

    # 192.0.2.0/24 TEST-NET-1 (documentation).
    if ($octets[0] -eq 192 -and $octets[1] -eq 0 -and $octets[2] -eq 2) {
        return $true
    }

    # 192.168.0.0/16
    if ($octets[0] -eq 192 -and $octets[1] -eq 168) {
        return $true
    }

    # 198.18.0.0/15 benchmarking.
    if ($octets[0] -eq 198 -and ($octets[1] -eq 18 -or $octets[1] -eq 19)) {
        return $true
    }

    # 198.51.100.0/24 TEST-NET-2 (documentation).
    if ($octets[0] -eq 198 -and $octets[1] -eq 51 -and $octets[2] -eq 100) {
        return $true
    }

    # 203.0.113.0/24 TEST-NET-3 (documentation).
    if ($octets[0] -eq 203 -and $octets[1] -eq 0 -and $octets[2] -eq 113) {
        return $true
    }

    # 169.254.0.0/16 link-local.
    if ($octets[0] -eq 169 -and $octets[1] -eq 254) {
        return $true
    }

    # 224.0.0.0/4 multicast.
    if ($octets[0] -ge 224 -and $octets[0] -le 239) {
        return $true
    }

    # 240.0.0.0/4 reserved for future use, including 255.255.255.255 broadcast.
    if ($octets[0] -ge 240) {
        return $true
    }

    return $false
}
