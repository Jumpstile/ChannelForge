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

    It 'normalizes a local XMLTV source and resolves relative paths against its config directory' {
        $path = Join-Path $RepoRoot 'tests\fixtures\epg-local-source.json'

        $source = @(Read-ChannelForgeEpgSource -Path $path)

        $source.Count | Should -Be 1
        $source[0].Name | Should -Be 'Local XMLTV Fixture'
        $source[0].Format | Should -Be 'xmltv'
        $source[0].Path | Should -Be ([io.path]::GetFullPath((Join-Path (Split-Path $path) 'xmltv\sample.xml')))
        $source[0].ConfiguredPath | Should -Be 'xmltv/sample.xml'
        $source[0].ConfigurationIndex | Should -Be 0
        $source[0].Url | Should -Be ''
        $source[0].Supported | Should -BeTrue
        $source[0].UnsupportedReason | Should -Be ''
    }

    It 'defaults an omitted source format to xmltv at runtime' {
        $path = Join-Path $RepoRoot 'tests\fixtures\epg-local-source.json'

        (Read-ChannelForgeEpgSource -Path $path).Format | Should -Be 'xmltv'
    }

    It 'uses ConfigurationIndex as the deterministic tie-breaker for equal source keys' {
        $path = Join-Path $TestDrive 'epg-equal-source-keys.json'
        $config = @{
            epg_sources = @(
                @{
                    name = 'Same Source'
                    priority = 10
                    path = 'guide.xml'
                    enabled = $true
                    role = 'primary'
                }
                @{
                    name = 'Same Source'
                    priority = 10
                    path = 'guide.xml'
                    enabled = $true
                    role = 'primary'
                }
            )
        }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path

        $firstRun = @(Read-ChannelForgeEpgSource -Path $path)
        $secondRun = @(Read-ChannelForgeEpgSource -Path $path)

        $firstRun.Count | Should -Be 2
        $firstRun[0].Priority | Should -Be 10
        $firstRun[1].Priority | Should -Be 10
        $firstRun[0].Name | Should -Be 'Same Source'
        $firstRun[1].Name | Should -Be 'Same Source'
        $firstRun[0].ConfiguredPath | Should -Be 'guide.xml'
        $firstRun[1].ConfiguredPath | Should -Be 'guide.xml'
        $firstRun[0].ConfigurationIndex | Should -Be 0
        $firstRun[1].ConfigurationIndex | Should -Be 1
        (@($firstRun | ForEach-Object { $_.ConfigurationIndex }) -join ',') | Should -Be '0,1'
        (@($secondRun | ForEach-Object { $_.ConfigurationIndex }) -join ',') | Should -Be '0,1'
        (@($secondRun | ForEach-Object { $_.ConfigurationIndex }) -join ',') | Should -Be ((@($firstRun | ForEach-Object { $_.ConfigurationIndex }) -join ','))
    }

    It 'returns URL sources as structurally valid remote XMLTV sources' {
        $path = Join-Path $RepoRoot 'data\epg\epg_sources.json'

        $source = @(Read-ChannelForgeEpgSource -Path $path)[0]

        $source.Format | Should -Be 'xmltv'
        $source.Supported | Should -BeTrue
        $source.Path | Should -Be ''
        $source.SourceKind | Should -Be 'remote'
        $source.UnsupportedReason | Should -Be ''
    }

    It 'rejects an unsupported source format' {
        $path = Join-Path $TestDrive 'epg-unsupported-format.json'
        $config = @{
            epg_sources = @(@{
                name = 'Unsupported Format'
                priority = 1
                path = 'guide.json'
                format = 'json'
                enabled = $true
                role = 'primary'
            })
        }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path

        { Read-ChannelForgeEpgSource -Path $path } | Should -Throw '*unsupported format*'
    }

    It 'rejects a source that specifies both a local path and a URL' {
        $path = Join-Path $TestDrive 'epg-both-path-and-url.json'
        $config = @{
            epg_sources = @(@{
                name = 'Ambiguous Source'
                priority = 1
                path = 'sample.xml'
                url = 'https://example.invalid/guide.xml'
                enabled = $true
                role = 'primary'
            })
        }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path

        { Read-ChannelForgeEpgSource -Path $path } | Should -Throw '*exactly one*'
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
