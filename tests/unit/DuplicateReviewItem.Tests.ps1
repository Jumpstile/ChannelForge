BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    $fixtureDir = Join-Path $RepoRoot 'tests\fixtures\lineup'
    $script:AliasPath = Join-Path $fixtureDir 'aliases.json'
    $script:BlocksPath = Join-Path $fixtureDir 'numbering_blocks.json'
    $script:TwoSources = @(
        [pscustomobject]@{ Path = Join-Path $fixtureDir 'sources-a.m3u'; Provider = 'fixture'; Playlist = 'a' }
        [pscustomobject]@{ Path = Join-Path $fixtureDir 'sources-b.m3u'; Provider = 'fixture'; Playlist = 'b' }
    )
    $script:WithDuplicate = $script:TwoSources + [pscustomobject]@{
        Path = Join-Path $fixtureDir 'sources-dup.m3u'; Provider = 'fixture'; Playlist = 'dup'
    }
}

Describe 'Duplicate channels become a review item' {
    It 'keeps the first copy, lists the dropped copy, and publishes the same M3U bytes' {
        $with = Merge-ChannelForgeLineup -Source $script:WithDuplicate -AliasPath $script:AliasPath -NumberingBlocksPath $script:BlocksPath
        $without = Merge-ChannelForgeLineup -Source $script:TwoSources -AliasPath $script:AliasPath -NumberingBlocksPath $script:BlocksPath

        $with.DuplicateReview.Count | Should -Be 1
        $item = $with.DuplicateReview[0]
        $item.Name | Should -Be 'ESPN'
        $item.Kept.Playlist | Should -Be 'a'
        $item.Dropped.Playlist | Should -Be 'dup'
        $item.State | Should -Be 'ReviewNeeded'
        $item.Question | Should -BeLike '*Which copy do you want?'
        $item.Choices.Count | Should -Be 6
        ($item | ConvertTo-Json -Depth 5) | Should -Not -BeLike '*example.invalid*'

        $withPath = Join-Path $TestDrive 'with.m3u'
        $withoutPath = Join-Path $TestDrive 'without.m3u'
        $with.Channels | Export-ChannelForgeM3UPlaylist -Path $withPath
        $without.Channels | Export-ChannelForgeM3UPlaylist -Path $withoutPath
        [System.IO.File]::ReadAllBytes($withPath) | Should -Be ([System.IO.File]::ReadAllBytes($withoutPath))
    }

    It 'returns an empty list when nothing is duplicated' {
        $result = Merge-ChannelForgeLineup -Source $script:TwoSources -AliasPath $script:AliasPath -NumberingBlocksPath $script:BlocksPath
        @($result.DuplicateReview).Count | Should -Be 0
    }
}
