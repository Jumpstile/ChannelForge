BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $root 'src\ChannelForge\Private\Get-ChannelForgeNetworkHttpWarning.ps1')
}

Describe 'Plain HTTP network warning' {
    It 'gives no warning for <Address>' -ForEach @(
        @{ Address = '127.0.0.1' }, @{ Address = 'localhost' }, @{ Address = '::1' }, @{ Address = '[::1]' }
    ) {
        Get-ChannelForgeNetworkHttpWarning -BindAddress $Address | Should -BeNullOrEmpty
    }
    It 'warns in plain words for <Address>' -ForEach @(
        @{ Address = '0.0.0.0' }, @{ Address = '192.168.1.20' }, @{ Address = '::' }, @{ Address = '2001:db8::5' }
    ) {
        $text = Get-ChannelForgeNetworkHttpWarning -BindAddress $Address
        $text | Should -Match 'plain HTTP'
        $text | Should -Match 'reverse proxy with HTTPS'
    }
    It 'is called by the server launcher before it starts' {
        $launcher = Get-Content -LiteralPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts\Start-ChannelForgeServer.ps1') -Raw
        $launcher | Should -Match 'Get-ChannelForgeNetworkHttpWarning -BindAddress \$BindAddress'
    }
}
