BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Read-ChannelForgeProvider' {
    It 'loads all configured M3U sources' {
        $path = Join-Path $RepoRoot 'data\providers\mybunny.json'

        $sources = @(Read-ChannelForgeProvider -Path $path)

        $sources.Count | Should -Be 16
    }

    It 'includes the Sports source' {
        $path = Join-Path $RepoRoot 'data\providers\mybunny.json'

        $sources = @(Read-ChannelForgeProvider -Path $path)

        $sources.Name | Should -Contain 'Sports'
        ($sources | Where-Object Name -eq 'Sports').Url | Should -Be 'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports'
    }

    It 'defaults LocalPlaylist to an empty string when not configured' {
        $path = Join-Path $RepoRoot 'data\providers\mybunny.json'

        $sources = @(Read-ChannelForgeProvider -Path $path)

        ($sources | Where-Object Name -eq 'Sports').LocalPlaylist | Should -Be ''
    }

    It 'passes through an optional local_playlist field' {
        $path = Join-Path $TestDrive 'provider-with-playlist.json'
        @{
            provider = 'fixture'
            sources  = @(
                @{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true; local_playlist = 'data/playlists/sports.local.m3u' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8

        $sources = @(Read-ChannelForgeProvider -Path $path)

        $sources[0].LocalPlaylist | Should -Be 'data/playlists/sports.local.m3u'
    }

    It 'throws when the provider file is missing' {
        { Read-ChannelForgeProvider -Path '.\does-not-exist.json' } | Should -Throw
    }

    It 'throws when a provider source URL is malformed' {
        $path = Join-Path $RepoRoot 'tests\fixtures\provider-invalid-url.json'

        { Read-ChannelForgeProvider -Path $path } | Should -Throw

        try {
            Read-ChannelForgeProvider -Path $path
        }
        catch {
            $_.Exception.Message | Should -Not -Match 'not-a-valid-url'
        }
    }
}
