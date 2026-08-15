BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Test-ChannelForgeSourceUrl' {
    It 'accepts a well-formed https placeholder URL' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports' | Should -BeTrue
        }
    }

    It 'rejects a plain http URL (HTTPS-only policy)' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'http://example.invalid/epg/public/all-sources.xml.gz' | Should -BeFalse
        }
    }

    It 'rejects localhost' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://localhost/iptv' | Should -BeFalse
        }
    }

    It 'rejects IPv4 loopback' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://127.0.0.1/iptv' | Should -BeFalse
        }
    }

    It 'rejects IPv6 loopback, including literal bracketed host syntax' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://[::1]/iptv' | Should -BeFalse
        }
    }

    It 'rejects IPv6 link-local addresses (fe80::/10)' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://[fe80::1]/iptv' | Should -BeFalse
        }
    }

    It 'rejects IPv6 unique local addresses (fc00::/7)' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://[fc00::1]/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://[fd12:3456:789a::1]/iptv' | Should -BeFalse
        }
    }

    It 'accepts a public IPv6 address outside the ULA/link-local/documentation ranges' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://[2606:4700:4700::1111]/iptv' | Should -BeTrue
        }
    }

    It 'rejects the IPv6 documentation range (2001:db8::/32)' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://[2001:db8::1]/iptv' | Should -BeFalse
        }
    }

    It 'rejects private IPv4 ranges' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://10.1.2.3/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://172.16.0.5/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://172.31.255.255/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://192.168.1.1/iptv' | Should -BeFalse
        }
    }

    It 'accepts a public IPv4 address just outside the 172.16.0.0/12 range' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://172.32.0.1/iptv' | Should -BeTrue
        }
    }

    It 'rejects IPv4 link-local addresses' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://169.254.1.1/iptv' | Should -BeFalse
        }
    }

    It 'rejects reserved IPv4 ranges' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://0.0.0.1/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://100.64.0.1/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://192.0.2.1/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://198.51.100.1/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://203.0.113.1/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://224.0.0.1/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'https://255.255.255.255/iptv' | Should -BeFalse
        }
    }

    It 'rejects credentialed URLs' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://example.invalid/REDACTED' | Should -BeFalse
        }
    }

    It 'rejects UNC paths' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url '\\server\share\provider.json' | Should -BeFalse
        }
    }

    It 'rejects file URLs' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'file:///C:/secrets.json' | Should -BeFalse
        }
    }

    It 'rejects unsupported schemes' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'ftp://example.invalid/iptv' | Should -BeFalse
        }
    }

    It 'rejects empty and malformed values' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url '' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'not-a-valid-url' | Should -BeFalse
        }
    }
}

Describe 'Test-ChannelForgeSafeHostAddress' {
    It 'accepts a DNS hostname (literal-address checks do not apply)' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSafeHostAddress -HostName 'example.invalid' | Should -BeTrue
        }
    }

    It 'rejects loopback literal addresses' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSafeHostAddress -HostName '127.0.0.1' | Should -BeFalse
            Test-ChannelForgeSafeHostAddress -HostName '::1' | Should -BeFalse
        }
    }

    It 'rejects private and link-local IPv4 literal addresses' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSafeHostAddress -HostName '10.0.0.1' | Should -BeFalse
            Test-ChannelForgeSafeHostAddress -HostName '172.16.0.1' | Should -BeFalse
            Test-ChannelForgeSafeHostAddress -HostName '192.168.0.1' | Should -BeFalse
            Test-ChannelForgeSafeHostAddress -HostName '169.254.0.1' | Should -BeFalse
        }
    }

    It 'rejects IPv6 link-local and ULA literal addresses' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSafeHostAddress -HostName 'fe80::1' | Should -BeFalse
            Test-ChannelForgeSafeHostAddress -HostName 'fc00::1' | Should -BeFalse
        }
    }

    It 'accepts a public literal IP address' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSafeHostAddress -HostName '8.8.8.8' | Should -BeTrue
            Test-ChannelForgeSafeHostAddress -HostName '2606:4700:4700::1111' | Should -BeTrue
        }
    }

    It 'rejects a reserved literal IPv4 address' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSafeHostAddress -HostName '203.0.113.1' | Should -BeFalse
        }
    }

    It 'rejects a literal IPv6 documentation-range address (2001:db8::/32)' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSafeHostAddress -HostName '2001:db8::1' | Should -BeFalse
        }
    }

    It 'rejects an empty host name' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSafeHostAddress -HostName '' | Should -BeFalse
        }
    }
}

Describe 'Test-ChannelForgeDisallowedIpAddress' {
    It 'rejects reserved IPv4 ranges' {
        InModuleScope ChannelForge {
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('0.0.0.1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('100.64.0.1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('192.0.0.1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('192.0.2.1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('198.18.0.1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('198.51.100.1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('203.0.113.1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('224.0.0.1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('255.255.255.255')) | Should -BeTrue
        }
    }

    It 'rejects the IPv6 ULA range (fc00::/7) across both halves' {
        InModuleScope ChannelForge {
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('fc00::1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('fd00::1')) | Should -BeTrue
        }
    }

    It 'rejects the IPv6 documentation range (2001:db8::/32)' {
        InModuleScope ChannelForge {
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('2001:db8::1')) | Should -BeTrue
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('2001:db8:ffff::1')) | Should -BeTrue
        }
    }

    It 'accepts a public IPv4 and IPv6 address' {
        InModuleScope ChannelForge {
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('8.8.8.8')) | Should -BeFalse
            Test-ChannelForgeDisallowedIpAddress -Address ([System.Net.IPAddress]::Parse('2606:4700:4700::1111')) | Should -BeFalse
        }
    }
}
