BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Read-ChannelForgeEpgSource' {
    It 'loads all configured EPG sources' {
        $path = Join-Path $RepoRoot 'data\epg\epg_sources.json'

        $sources = @(Read-ChannelForgeEpgSource -Path $path)

        $sources.Count | Should -Be 23
    }

    It 'sorts EPG sources by priority' {
        $path = Join-Path $RepoRoot 'data\epg\epg_sources.json'

        $sources = @(Read-ChannelForgeEpgSource -Path $path)

        $sources[0].Priority | Should -Be 10
        $sources[0].Name | Should -Be 'EPG Ripper ALL Sources'
    }

    It 'includes provider fallback EPGs' {
        $path = Join-Path $RepoRoot 'data\epg\epg_sources.json'

        $sources = @(Read-ChannelForgeEpgSource -Path $path)

        $sources.Role | Should -Contain 'provider-fallback'
        $sources.Name | Should -Contain 'Provider NFL'
    }

    It 'throws when the EPG source file is missing' {
        { Read-ChannelForgeEpgSource -Path '.\does-not-exist.json' } | Should -Throw
    }

    It 'throws when an EPG source URL uses an unsupported scheme' {
        $path = Join-Path $RepoRoot 'tests\fixtures\epg-invalid-url.json'

        { Read-ChannelForgeEpgSource -Path $path } | Should -Throw

        try {
            Read-ChannelForgeEpgSource -Path $path
        }
        catch {
            $_.Exception.Message | Should -Not -Match 'all-sources\.xml\.gz'
        }
    }
}