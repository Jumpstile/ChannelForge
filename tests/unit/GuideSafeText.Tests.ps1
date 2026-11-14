BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Guide safe text' {
    It 'keeps normal event title <Title> unchanged' -ForEach @(
        @{ Title = 'UFC 300: Main Card' }
        @{ Title = 'Round 1/Final' }
        @{ Title = 'Night 1 / Night 2' }
        @{ Title = 'WWE Raw 8/7c' }
        @{ Title = 'PPV 1 - Fight Night' }
        @{ Title = 'Home/Away Highlights' }
    ) {
        InModuleScope ChannelForge -Parameters @{ Title = $Title } {
            param($Title)
            ConvertTo-ChannelForgeGuideSafeText -Value $Title | Should -BeExactly $Title
        }
    }

    It 'redacts secret <Text>' -ForEach @(
        @{ Text = 'Bearer abc.DEF-123_xyz== live' }
        @{ Text = 'Authorization: Bearer abc123 live' }
        @{ Text = 'Authorization: "Basic dXNlcjpwdw==" live' }
        @{ Text = 'C:\Users\name\file.txt' }
        @{ Text = '/home/name/file.txt' }
        @{ Text = 'mail name@example.com now' }
        @{ Text = 'api_key=abc' }
        @{ Text = 'my_client_secret_v2: "abc def"' }
    ) {
        InModuleScope ChannelForge -Parameters @{ Text = $Text } {
            param($Text)
            $out = ConvertTo-ChannelForgeGuideSafeText -Value $Text
            $out | Should -Match '\[redacted-'
            $out | Should -Not -Match 'abc|name|dXNl'
        }
    }
}
