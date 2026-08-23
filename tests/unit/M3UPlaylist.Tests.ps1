BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Import-ChannelForgeM3UPlaylist' {
    It 'parses channels from a tiny M3U playlist' {
        $path = Join-Path $RepoRoot 'tests\fixtures\tiny.m3u'

        $channels = @(Import-ChannelForgeM3UPlaylist -Path $path -Provider 'fixture' -Playlist 'tiny')

        $channels.Count | Should -Be 3
    }

    It 'parses channel identity and guide metadata' {
        $path = Join-Path $RepoRoot 'tests\fixtures\tiny.m3u'

        $channels = @(Import-ChannelForgeM3UPlaylist -Path $path -Provider 'fixture' -Playlist 'tiny')
        $wcbs = $channels | Where-Object DisplayName -eq 'WCBS CBS New York'

        $wcbs.Provider | Should -Be 'fixture'
        $wcbs.Playlist | Should -Be 'tiny'
        $wcbs.TvgId | Should -Be 'wcbs.us'
        $wcbs.TvgName | Should -Be 'WCBS'
        $wcbs.Group | Should -Be 'ABC'
        $wcbs.Logo | Should -Be 'https://example.com/wcbs.png'
    }

    It 'captures the stream URL from the line following #EXTINF' {
        $path = Join-Path $RepoRoot 'tests\fixtures\tiny.m3u'

        $channels = @(Import-ChannelForgeM3UPlaylist -Path $path -Provider 'fixture' -Playlist 'tiny')
        $wcbs = $channels | Where-Object DisplayName -eq 'WCBS CBS New York'
        $espn = $channels | Where-Object DisplayName -eq 'ESPN HD'

        $wcbs.Url | Should -Be 'https://example.com/live/wcbs'
        $espn.Url | Should -Be 'https://example.com/live/espn'
    }

    It 'throws when the playlist file is missing' {
        { Import-ChannelForgeM3UPlaylist -Path '.\missing.m3u' } | Should -Throw
    }

    It 'requires #EXTM3U and rejects the same incomplete records as remote input' {
        foreach ($content in @(
            "not-m3u`n#EXTINF:-1,Channel`nhttps://example.invalid/live/channel`n",
            "#EXTM3U`n#EXTINF:-1,Channel`n",
            "#EXTM3U`n#EXTINF:-1,First`n#EXTINF:-1,Second`nhttps://example.invalid/live/second`n"
        )) {
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.m3u')
            [io.file]::WriteAllText($path, $content, [text.utf8encoding]::new($false))

            { Import-ChannelForgeM3UPlaylist -Path $path -Provider 'fixture' -Playlist 'invalid' } |
                Should -Throw
        }
    }
}
