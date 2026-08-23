BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
    $script:FixturePlaylist = Join-Path $RepoRoot 'tests\fixtures\tiny.m3u'
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-BuildFixture {
        param(
            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter(Mandatory)]
            [object[]]$Sources,

            [switch]$IncludeLocalPlaylist
        )

        $dataDir = Join-Path $Root 'data'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $dataDir 'providers'),
            (Join-Path $dataDir 'epg'),
            (Join-Path $dataDir 'lineup'),
            (Join-Path $dataDir 'rules'),
            (Join-Path $dataDir 'playlists') | Out-Null

        if ($IncludeLocalPlaylist) {
            Copy-Item -LiteralPath $script:FixturePlaylist -Destination (Join-Path $dataDir 'playlists\local.m3u')
        }

        @{
            provider = 'fixture-provider'
            sources = $Sources
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        @{ epg_sources = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @(@{ start = 1; end = 9999; category = 'General'; notes = 'fixture' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding UTF8
    }

    function Set-RemoteBuildMock {
        param(
            [Parameter(Mandatory)]
            [string]$FixturePath,

            [string]$RawETag = '',

            [string]$RawLastModified = ''
        )

        $global:ChannelForgeBuildFixturePath = $FixturePath
        Mock -CommandName Import-ChannelForgeConfiguredM3USource -MockWith {
            param($Source,$Provider,$MaxDocumentBytes,$MaxRawResponseBytes,$CacheRoot,$AcquisitionStatus)
            $channels = @(Import-ChannelForgeM3UPlaylist -Path $global:ChannelForgeBuildFixturePath -Provider $Provider -Playlist $Source.Name)
            if ($null -ne $AcquisitionStatus) {
                $AcquisitionStatus['ProviderId'] = $Provider
                $AcquisitionStatus['SourceId'] = $Source.Name
                $AcquisitionStatus['Outcome'] = 'Fetched'
                $AcquisitionStatus['Reason'] = 'FreshFetched'
                $AcquisitionStatus['CacheKey'] = ('a' * 64)
                $AcquisitionStatus['StatusCode'] = 200
                $AcquisitionStatus['ContentType'] = 'application/vnd.apple.mpegurl'
                $AcquisitionStatus['ContentEncodings'] = @()
                $AcquisitionStatus['RawContentLength'] = $null
                $AcquisitionStatus['DecompressedBytes'] = 1
                $AcquisitionStatus['ChannelCount'] = $channels.Count
                $AcquisitionStatus['HasETag'] = -not [string]::IsNullOrWhiteSpace($RawETag)
                $AcquisitionStatus['HasLastModified'] = -not [string]::IsNullOrWhiteSpace($RawLastModified)
                if (-not [string]::IsNullOrWhiteSpace($RawETag)) {
                    $AcquisitionStatus['ETag'] = $RawETag
                }
                if (-not [string]::IsNullOrWhiteSpace($RawLastModified)) {
                    $AcquisitionStatus['LastModified'] = $RawLastModified
                }
            }
            return $channels
        }
    }
}

Describe 'Build-Lineup.ps1 remote provider M3U integration' {
    It 'acquires a configured remote source, merges it, and writes only safe remote evidence' {
        $root = Join-Path $TestDrive 'remote-success'
        New-BuildFixture -Root $root -Sources @(
            @{ name = 'Remote'; group = 'General'; url = 'https://example.invalid/iptv/fixture'; enabled = $true }
        )
        $rawETag = '"build-report-etag-sentinel"'
        $rawLastModified = '2026-08-22T12:34:56.0000000+00:00'
        Set-RemoteBuildMock -FixturePath $script:FixturePlaylist -RawETag $rawETag -RawLastModified $rawLastModified

        & $script:ScriptPath -Root $root

        $m3uPath = Join-Path $root 'output\merged.m3u'
        $summaryPath = Join-Path $root 'output\reports\build-summary.json'
        $planPath = Join-Path $root 'output\reports\lineup-plan.md'
        Test-Path -LiteralPath $m3uPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $m3uPath -Raw) | Should -Match '#EXTM3U'
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $summary.M3UStatus | Should -Be 'GENERATED'
        $summary.M3URemoteSourceCount | Should -Be 1
        $summary.M3UAcquisitionStatus[0].Outcome | Should -Be 'Fetched'
        $summary.M3UAcquisitionStatus[0].CacheKey | Should -Match '^[0-9a-f]{64}$'
        $summary.M3UAcquisitionStatus[0].HasETag | Should -BeTrue
        $summary.M3UAcquisitionStatus[0].HasLastModified | Should -BeTrue
        $summaryStatusJson = $summary.M3UAcquisitionStatus[0] | ConvertTo-Json -Depth 10 -Compress
        $summaryStatusJson | Should -Not -Match ([regex]::Escape($rawETag))
        $summaryStatusJson | Should -Not -Match ([regex]::Escape($rawLastModified))
        foreach ($raw in @(
            (Get-Content -LiteralPath $summaryPath -Raw),
            (Get-Content -LiteralPath $planPath -Raw)
        )) {
            $raw | Should -Not -Match 'https?://'
            $raw | Should -Not -Match 'live/'
            $raw | Should -Not -Match 'ACCOUNT_ID|API_TOKEN'
            $raw | Should -Not -Match ([regex]::Escape($rawETag))
            $raw | Should -Not -Match ([regex]::Escape($rawLastModified))
        }
        $outputFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'output') -File -Recurse)
        $outputText = @(
            $outputFiles | ForEach-Object {
                Get-Content -LiteralPath $_.FullName -Raw
            }
        ) -join ([Environment]::NewLine)
        $outputText | Should -Not -Match ([regex]::Escape($rawETag))
        $outputText | Should -Not -Match ([regex]::Escape($rawLastModified))
        (@($outputFiles | ForEach-Object { $_.FullName }) -join ([Environment]::NewLine)) |
            Should -Not -Match ([regex]::Escape($rawETag))
        (@($outputFiles | ForEach-Object { $_.FullName }) -join ([Environment]::NewLine)) |
            Should -Not -Match ([regex]::Escape($rawLastModified))
    }

    It 'produces byte-identical merged output for identical local and remote M3U bytes' {
        $localRoot = Join-Path $TestDrive 'local-equivalence'
        New-BuildFixture -Root $localRoot -IncludeLocalPlaylist -Sources @(
            @{ name = 'Source'; group = 'General'; url = 'https://example.invalid/iptv/fixture'; enabled = $true; local_playlist = 'data/playlists/local.m3u' }
        )
        & $script:ScriptPath -Root $localRoot
        $localHash = (Get-FileHash -LiteralPath (Join-Path $localRoot 'output\merged.m3u') -Algorithm SHA256).Hash

        $remoteRoot = Join-Path $TestDrive 'remote-equivalence'
        New-BuildFixture -Root $remoteRoot -Sources @(
            @{ name = 'Source'; group = 'General'; url = 'https://example.invalid/iptv/fixture'; enabled = $true }
        )
        Set-RemoteBuildMock -FixturePath $script:FixturePlaylist
        & $script:ScriptPath -Root $remoteRoot
        $remoteHash = (Get-FileHash -LiteralPath (Join-Path $remoteRoot 'output\merged.m3u') -Algorithm SHA256).Hash

        $remoteHash | Should -Be $localHash
    }

    It 'treats local_playlist as authoritative and does not invoke remote acquisition' {
        $root = Join-Path $TestDrive 'local-authoritative'
        New-BuildFixture -Root $root -IncludeLocalPlaylist -Sources @(
            @{ name = 'Source'; group = 'General'; url = 'https://example.invalid/iptv/fixture'; enabled = $true; local_playlist = 'data/playlists/local.m3u' }
        )
        Mock -CommandName Import-ChannelForgeConfiguredM3USource -MockWith {
            throw 'remote acquisition must not be called when local_playlist is configured'
        }

        & $script:ScriptPath -Root $root
        Should -Invoke Import-ChannelForgeConfiguredM3USource -Times 0 -Exactly
    }

    It 'fails closed and leaves no public M3U when a required remote source fails' {
        $root = Join-Path $TestDrive 'remote-failure'
        New-BuildFixture -Root $root -Sources @(
            @{ name = 'Remote'; group = 'General'; url = 'https://example.invalid/iptv/fixture'; enabled = $true }
        )
        Mock -CommandName Import-ChannelForgeConfiguredM3USource -MockWith {
            throw 'deterministic remote fixture failure'
        }

        { & $script:ScriptPath -Root $root } | Should -Throw '*Configured provider M3U input could not be acquired or parsed*'
        Test-Path -LiteralPath (Join-Path $root 'output\merged.m3u') -PathType Leaf | Should -BeFalse
        $summary = Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.M3UStatus | Should -Be 'FAILED'
        $summary.Status | Should -Be 'FAILED'
        (Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw) | Should -Not -Match 'https?://|live/'
    }
}
