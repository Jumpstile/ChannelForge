BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'ConvertTo-ChannelForgeNormalizedChannel' {
    It 'removes common quality tags from channel names' {
        $channel = New-ChannelForgeChannel -OriginalName 'ESPN HD'

        $result = $channel | ConvertTo-ChannelForgeNormalizedChannel

        $result.OriginalName | Should -Be 'ESPN HD'
        $result.NormalizedName | Should -Be 'ESPN'
    }

    It 'removes bracketed quality tags' {
        $channel = New-ChannelForgeChannel -OriginalName 'HBO East [FHD]'

        $result = $channel | ConvertTo-ChannelForgeNormalizedChannel

        $result.NormalizedName | Should -Be 'HBO East'
    }

    It 'collapses extra whitespace after normalization' {
        $channel = New-ChannelForgeChannel -OriginalName 'FOX Sports 1   1080p'

        $result = $channel | ConvertTo-ChannelForgeNormalizedChannel

        $result.NormalizedName | Should -Be 'FOX Sports 1'
    }

    It 'does not change OriginalName' {
        $channel = New-ChannelForgeChannel -OriginalName 'WABC HD'

        $result = $channel | ConvertTo-ChannelForgeNormalizedChannel

        $result.OriginalName | Should -Be 'WABC HD'
    }
}
