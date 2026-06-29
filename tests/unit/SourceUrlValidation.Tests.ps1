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

    It 'accepts a well-formed http placeholder URL' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'http://example.invalid/epg/public/all-sources.xml.gz' | Should -BeTrue
        }
    }

    It 'rejects localhost' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'https://localhost/iptv' | Should -BeFalse
        }
    }

    It 'rejects IPv4 loopback' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'http://127.0.0.1/iptv' | Should -BeFalse
        }
    }

    It 'rejects IPv6 loopback' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'http://[::1]/iptv' | Should -BeFalse
        }
    }

    It 'rejects private IPv4 ranges' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'http://10.1.2.3/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'http://172.16.0.5/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'http://172.31.255.255/iptv' | Should -BeFalse
            Test-ChannelForgeSourceUrl -Url 'http://192.168.1.1/iptv' | Should -BeFalse
        }
    }

    It 'accepts a public IPv4 address just outside the 172.16.0.0/12 range' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'http://172.32.0.1/iptv' | Should -BeTrue
        }
    }

    It 'rejects IPv4 link-local addresses' {
        InModuleScope ChannelForge {
            Test-ChannelForgeSourceUrl -Url 'http://169.254.1.1/iptv' | Should -BeFalse
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
