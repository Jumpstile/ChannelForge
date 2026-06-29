BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'New-ChannelForgeChannel' {
    It 'creates a channel with basic identity fields' {
        $channel = New-ChannelForgeChannel `
            -Provider 'mybunny' `
            -Playlist 'Sports' `
            -OriginalName 'ESPN HD' `
            -TvgId 'espn.us' `
            -Group 'Sports'

        $channel.Provider | Should -Be 'mybunny'
        $channel.Playlist | Should -Be 'Sports'
        $channel.OriginalName | Should -Be 'ESPN HD'
        $channel.NormalizedName | Should -Be 'ESPN HD'
        $channel.DisplayName | Should -Be 'ESPN HD'
        $channel.TvgId | Should -Be 'espn.us'
        $channel.Group | Should -Be 'Sports'
    }

    It 'uses DisplayName when provided' {
        $channel = New-ChannelForgeChannel `
            -OriginalName 'WABC HD' `
            -DisplayName 'WABC ABC New York'

        $channel.DisplayName | Should -Be 'WABC ABC New York'
    }

    It 'defaults Url to an empty string and accepts an explicit stream URL' {
        $withoutUrl = New-ChannelForgeChannel -OriginalName 'Test Channel'
        $withUrl = New-ChannelForgeChannel -OriginalName 'Test Channel' -Url 'https://example.invalid/live/test'

        $withoutUrl.Url | Should -Be ''
        $withUrl.Url | Should -Be 'https://example.invalid/live/test'
    }

    It 'initializes classification and flags safely' {
        $channel = New-ChannelForgeChannel -OriginalName 'Test Channel'

        $channel.Category | Should -Be ''
        $channel.IsLocal | Should -BeFalse
        $channel.IsAdult | Should -BeFalse
        $channel.IsDuplicate | Should -BeFalse
        $channel.Confidence | Should -Be 0
        $channel.Warnings.Count | Should -Be 0
    }
}