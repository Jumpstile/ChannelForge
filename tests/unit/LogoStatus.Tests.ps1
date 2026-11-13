BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Get-ChannelForgeLogoStatus' {
    It 'returns <Expected> for <Url>' -ForEach @(
        @{ Url = 'https://img.example.com/logos/espn.png'; Expected = 'Public' }
        @{ Url = 'https://img.example.com:8443/logo.png?size=64&v=2'; Expected = 'Public' }
        @{ Url = 'https://172.32.1.1/a.png'; Expected = 'Public' }
        @{ Url = 'http://img.example.com/a.png'; Expected = 'NotHttps' }
        @{ Url = '/logos/a.png'; Expected = 'NotHttps' }
        @{ Url = ''; Expected = 'Empty' }
        @{ Url = '   '; Expected = 'Empty' }
        @{ Url = 'https://localhost/a.png'; Expected = 'PrivateAddress' }
        @{ Url = 'https://10.0.0.5/a.png'; Expected = 'PrivateAddress' }
        @{ Url = 'https://192.168.1.9/a.png'; Expected = 'PrivateAddress' }
        @{ Url = 'https://172.20.1.1/a.png'; Expected = 'PrivateAddress' }
        @{ Url = 'https://[::1]/a.png'; Expected = 'PrivateAddress' }
        @{ Url = 'https://tv.lan/a.png'; Expected = 'PrivateAddress' }
        @{ Url = 'https://nas/a.png'; Expected = 'PrivateAddress' }
    ) {
        InModuleScope ChannelForge -Parameters @{ Url = $Url; Expected = $Expected } {
            Get-ChannelForgeLogoStatus -Url $Url | Should -BeExactly $Expected
        }
    }
}
