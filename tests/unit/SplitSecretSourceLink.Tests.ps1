BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Split-ChannelForgeSecretSourceLink' {
    It 'splits a query-style login link' {
        InModuleScope ChannelForge {
            $link = 'https://tv.example.invalid/get.php?username=demo&password=demo-not-real&type=m3u_plus'
            $r = Split-ChannelForgeSecretSourceLink -Link $link
            $r.Succeeded | Should -BeTrue
            $r.DisplayHost | Should -Be 'https://tv.example.invalid'
            $r.SecretLink | Should -Be $link
        }
    }

    It 'splits a path-style login link' {
        InModuleScope ChannelForge {
            $r = Split-ChannelForgeSecretSourceLink -Link 'https://tv.example.invalid:443/live/demo/demo-not-real/list.m3u'
            $r.Succeeded | Should -BeTrue
            $r.DisplayHost | Should -Be 'https://tv.example.invalid'
        }
    }

    It 'refuses user info with a plain message' {
        InModuleScope ChannelForge {
            $r = Split-ChannelForgeSecretSourceLink -Link 'https://demo:demo-not-real@tv.example.invalid/list.m3u'
            $r.Succeeded | Should -BeFalse
            $r.FailureCategory | Should -Be 'UserInfoNotSupported'
            $r.Message | Should -BeLike '*not supported yet*'
        }
    }

    It 'refuses <Name>' -ForEach @(
        @{ Name = 'http'; Link = 'http://tv.example.invalid/get.php?password=demo-not-real'; Category = 'SchemeRejected' }
        @{ Name = 'a fragment'; Link = 'https://tv.example.invalid/get.php?password=demo-not-real#x'; Category = 'FragmentRejected' }
        @{ Name = 'port 8080'; Link = 'https://tv.example.invalid:8080/get.php?password=demo-not-real'; Category = 'PortRejected' }
        @{ Name = 'an empty host'; Link = 'https:///get.php?password=demo-not-real'; Category = $null }
        @{ Name = 'loopback'; Link = 'https://127.0.0.1/get.php?password=demo-not-real'; Category = 'HostRejected' }
        @{ Name = 'a private host'; Link = 'https://192.168.1.5/get.php?password=demo-not-real'; Category = 'HostRejected' }
        @{ Name = 'text that is not a link'; Link = 'demo-not-real'; Category = 'LinkUnreadable' }
    ) {
        InModuleScope ChannelForge -Parameters @{ Link = $Link; Category = $Category } {
            $r = Split-ChannelForgeSecretSourceLink -Link $Link 4>&1 5>&1 3>&1 2>&1
            $r.Succeeded | Should -BeFalse
            if ($Category) { $r.FailureCategory | Should -Be $Category }
            $r.SecretLink | Should -BeNullOrEmpty
            ($r | Out-String) | Should -Not -BeLike '*demo-not-real*'
            ($r | Out-String) | Should -Not -BeLike '*get.php*'
        }
    }
}
