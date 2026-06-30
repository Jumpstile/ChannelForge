BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
}

Describe 'Build-Lineup.ps1 (no local playlists configured)' {
    BeforeAll {
        $script:FixtureRoot = Join-Path $TestDrive 'project'
        $dataDir = Join-Path $script:FixtureRoot 'data'

        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null

        @{
            provider = 'fixture-provider'
            sources  = @(
                @{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports'; enabled = $true }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        @{
            epg_sources = @(
                @{ name = 'Public EPG'; priority = 10; url = 'https://example.invalid/epg/public/all-sources.xml.gz'; enabled = $true; role = 'primary' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8

        @{
            locals = @(
                @{ number = 2; station = 'WCBS'; network = 'CBS'; market = 'New York'; display = 'WCBS CBS New York' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8

        @{
            blocks = @(
                @{ start = 100; end = 199; category = 'Sports'; notes = 'fixture block' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8

        & $script:ScriptPath -Root $script:FixtureRoot
    }

    It 'writes the build summary report inside output/' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        Test-Path -LiteralPath $summaryPath -PathType Leaf | Should -BeTrue
    }

    It 'reports M3U and XMLTV as not generated, with a clear deferred reason for XMLTV' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json

        $summary.M3UGenerated | Should -BeFalse
        $summary.M3UPath | Should -BeNullOrEmpty
        $summary.M3USha256 | Should -BeNullOrEmpty
        $summary.XMLTVGenerated | Should -BeFalse
        $summary.XMLTVDeferredReason | Should -Match 'programme'
        $summary.Status | Should -Be 'SOURCE_OF_TRUTH_VALIDATED'
    }

    It 'does not claim output files exist that were never generated' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        $raw = Get-Content -LiteralPath $summaryPath -Raw

        $raw | Should -Not -Match 'merged\.m3u'
        $raw | Should -Not -Match 'merged\.xmltv'
    }

    It 'notes in the human-readable plan that M3U was not generated and lists all three deferred limitations' {
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'
        $plan = Get-Content -LiteralPath $planPath -Raw

        $plan | Should -Match 'Merged M3U: not generated'
        $plan | Should -Match 'XMLTV output: deferred'
        $plan | Should -Match 'HTTP provider/EPG fetch: deferred'
        $plan | Should -Match 'Plex EPG/guide binding: deferred'
    }

    It 'does not leak full provider or EPG URLs into the human-readable report' {
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'
        $plan = Get-Content -LiteralPath $planPath -Raw

        $plan | Should -Not -Match 'https?://'
        $plan | Should -Not -Match 'example\.invalid'
    }

    It 'does not leak token- or account-shaped values into the human-readable report' {
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'
        $plan = Get-Content -LiteralPath $planPath -Raw

        $plan | Should -Not -Match 'ACCOUNT_ID'
        $plan | Should -Not -Match 'API_TOKEN'
    }

    It 'still identifies provider sources by name, enabled state, and local-playlist state without their URLs' {
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'
        $plan = Get-Content -LiteralPath $planPath -Raw

        $plan | Should -Match 'Sports \(enabled, no local playlist\)'
    }

    It 'does not leak full provider or EPG URLs into the machine-readable summary' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        $raw = Get-Content -LiteralPath $summaryPath -Raw

        $raw | Should -Not -Match 'https?://'
        $raw | Should -Not -Match 'ACCOUNT_ID'
        $raw | Should -Not -Match 'API_TOKEN'
    }

    It 'throws when a required source file is missing' {
        $brokenRoot = Join-Path $TestDrive 'broken-project'
        New-Item -ItemType Directory -Force -Path (Join-Path $brokenRoot 'data\providers') | Out-Null

        { & $script:ScriptPath -Root $brokenRoot } | Should -Throw
    }
}

Describe 'Build-Lineup.ps1 (with local playlists configured)' {
    BeforeAll {
        $script:FixtureRoot = Join-Path $TestDrive 'project-with-playlists'
        $dataDir = Join-Path $script:FixtureRoot 'data'
        $playlistDir = Join-Path $dataDir 'playlists'

        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'rules') | Out-Null
        New-Item -ItemType Directory -Force -Path $playlistDir | Out-Null

        # "Sports" is enabled and has a local playlist: its channels must
        # appear in the merged output.
        @'
#EXTM3U
#EXTINF:-1 tvg-id="espn.us" tvg-name="ESPN" tvg-logo="https://example.invalid/logos/espn.png" group-title="Sports",ESPN HD
https://example.invalid/live/espn
#EXTINF:-1 tvg-id="fs1.us" tvg-name="FS1" group-title="Sports",FOX Sports 1
https://example.invalid/live/fs1
'@ | Set-Content -LiteralPath (Join-Path $playlistDir 'sports.m3u') -Encoding utf8NoBOM

        # "Disabled" has a local playlist too, but enabled=false: its
        # channels must NOT appear in the merged output.
        @'
#EXTM3U
#EXTINF:-1 tvg-id="disabledchannel.us" tvg-name="Disabled Channel" group-title="Sports",Disabled Channel
https://example.invalid/live/disabled-channel
'@ | Set-Content -LiteralPath (Join-Path $playlistDir 'disabled.m3u') -Encoding utf8NoBOM

        @{
            provider = 'fixture-provider'
            sources  = @(
                @{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports'; enabled = $true; local_playlist = 'data/playlists/sports.m3u' }
                @{ name = 'Disabled'; group = 'Sports'; url = 'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Disabled'; enabled = $false; local_playlist = 'data/playlists/disabled.m3u' }
                @{ name = 'NoPlaylist'; group = 'Movies'; url = 'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/NoPlaylist'; enabled = $true }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        @{
            epg_sources = @(
                @{ name = 'Public EPG'; priority = 10; url = 'https://example.invalid/epg/public/all-sources.xml.gz'; enabled = $true; role = 'primary' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8

        @{
            locals = @(
                @{ number = 2; station = 'WCBS'; network = 'CBS'; market = 'New York'; display = 'WCBS CBS New York' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8

        @{
            blocks = @(
                @{ start = 400; end = 410; category = 'Sports'; notes = 'fixture sports block' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8

        @{
            aliases = @(
                @{ canonical = 'FS1'; aliases = @('FS1', 'FOX Sports 1') }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding UTF8

        & $script:ScriptPath -Root $script:FixtureRoot
    }

    It 'generates output/merged.m3u' {
        $m3uPath = Join-Path $script:FixtureRoot 'output\merged.m3u'
        Test-Path -LiteralPath $m3uPath -PathType Leaf | Should -BeTrue
    }

    It 'confines the merged playlist to the project output/ folder (write guardrail)' {
        $outDir = Join-Path $script:FixtureRoot 'output'
        $m3uPath = Join-Path $outDir 'merged.m3u'

        (Resolve-Path $m3uPath).Path.StartsWith((Resolve-Path $outDir).Path, [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
    }

    It 'includes only the enabled source with a local playlist, not the disabled source or the source with no playlist' {
        $m3uPath = Join-Path $script:FixtureRoot 'output\merged.m3u'
        $content = Get-Content -LiteralPath $m3uPath -Raw

        $content | Should -Match 'ESPN'
        $content | Should -Match 'FS1'
        $content | Should -Not -Match 'Disabled Channel'
        $content | Should -Not -Match 'disabledchannel\.us'
    }

    It 'resolves the FOX Sports 1 alias to FS1 in the merged output' {
        $m3uPath = Join-Path $script:FixtureRoot 'output\merged.m3u'
        $content = Get-Content -LiteralPath $m3uPath -Raw

        $content | Should -Not -Match 'FOX Sports 1'
        $content | Should -Match ',FS1'
    }

    It 'assigns deterministic channel numbers and includes tvg-chno in the merged output' {
        $m3uPath = Join-Path $script:FixtureRoot 'output\merged.m3u'
        $content = Get-Content -LiteralPath $m3uPath -Raw

        $content | Should -Match 'tvg-chno="400"'
        $content | Should -Match 'tvg-chno="401"'
    }

    It 'preserves the real stream URL in merged.m3u (the one place URLs belong)' {
        $m3uPath = Join-Path $script:FixtureRoot 'output\merged.m3u'
        $content = Get-Content -LiteralPath $m3uPath -Raw

        $content | Should -Match 'https://example\.invalid/live/espn'
        $content | Should -Match 'https://example\.invalid/live/fs1'
    }

    It 'reports M3UGenerated=true with a project-relative path and a checksum that matches the real file' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        $m3uPath = Join-Path $script:FixtureRoot 'output\merged.m3u'
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json

        $summary.M3UGenerated | Should -BeTrue
        $summary.M3UPath | Should -Be 'output/merged.m3u'
        $summary.M3USha256 | Should -Be (Get-FileHash -LiteralPath $m3uPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $summary.ChannelCount | Should -Be 2
        $summary.DuplicateCount | Should -Be 0
        $summary.XMLTVGenerated | Should -BeFalse
    }

    It 'never leaks a stream URL, provider URL, or token into either report, even though merged.m3u contains them' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'

        $summaryRaw = Get-Content -LiteralPath $summaryPath -Raw
        $planRaw = Get-Content -LiteralPath $planPath -Raw

        foreach ($raw in @($summaryRaw, $planRaw)) {
            $raw | Should -Not -Match 'https?://'
            $raw | Should -Not -Match 'ACCOUNT_ID'
            $raw | Should -Not -Match 'API_TOKEN'
        }
    }

    It 'produces a byte-identical merged.m3u when rebuilt from the same inputs' {
        $firstHash = (Get-FileHash -LiteralPath (Join-Path $script:FixtureRoot 'output\merged.m3u') -Algorithm SHA256).Hash

        & $script:ScriptPath -Root $script:FixtureRoot

        $secondHash = (Get-FileHash -LiteralPath (Join-Path $script:FixtureRoot 'output\merged.m3u') -Algorithm SHA256).Hash
        $secondHash | Should -Be $firstHash
    }
}

Describe 'Build-Lineup.ps1 (local_playlist path-safety guardrail)' {
    BeforeAll {
        function New-MinimalFixture {
            param([string]$LocalPlaylistValue)

            $fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $dataDir = Join-Path $fixtureRoot 'data'

            New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'rules') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'playlists') | Out-Null

            @{
                provider = 'fixture'
                sources  = @(
                    @{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true; local_playlist = $LocalPlaylistValue }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

            @{ epg_sources = @(@{ name = 'x'; priority = 1; url = 'https://example.invalid/y'; enabled = $true; role = 'primary' }) } |
                ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
            @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
            @{ blocks = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8
            @{ aliases = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding UTF8

            return $fixtureRoot
        }
    }

    It 'rejects a local_playlist value that traverses outside data/playlists' {
        $fixtureRoot = New-MinimalFixture -LocalPlaylistValue '../../../../Windows/System32/drivers/etc/hosts'

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw '*approved location*'
        Test-Path -LiteralPath (Join-Path $fixtureRoot 'output\merged.m3u') | Should -BeFalse
    }

    It 'rejects a local_playlist value that is an absolute path elsewhere on disk' {
        $fixtureRoot = New-MinimalFixture -LocalPlaylistValue 'C:\Windows\System32\drivers\etc\hosts'

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw '*approved location*'
    }

    It 'rejects a local_playlist value that is a UNC path' {
        $fixtureRoot = New-MinimalFixture -LocalPlaylistValue '\\server\share\file.m3u'

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw '*approved location*'
    }
}

Describe 'Build-Lineup.ps1 (does not bypass source URL validation)' {
    It 'throws when a provider source has a malformed URL, via the centralized Read-ChannelForgeProvider reader' {
        $fixtureRoot = Join-Path $TestDrive 'invalid-url-project'
        $dataDir = Join-Path $fixtureRoot 'data'

        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null

        @{
            provider = 'fixture'
            sources  = @(
                @{ name = 'Sports'; group = 'Sports'; url = 'not-a-valid-url'; enabled = $true }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        @{ epg_sources = @(@{ name = 'x'; priority = 1; url = 'https://example.invalid/y'; enabled = $true; role = 'primary' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw
    }

    It 'throws when an EPG source has an unsupported URL scheme, via the centralized Read-ChannelForgeEpgSource reader' {
        $fixtureRoot = Join-Path $TestDrive 'invalid-epg-url-project'
        $dataDir = Join-Path $fixtureRoot 'data'

        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null

        @{
            provider = 'fixture'
            sources  = @(
                @{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        @{ epg_sources = @(@{ name = 'x'; priority = 1; url = 'ftp://example.invalid/y'; enabled = $true; role = 'primary' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw
    }
}

Describe 'Build-Lineup.ps1 (provider config resolution, issue #20)' {
    BeforeAll {
        function New-MinimalProviderFixtureRoot {
            param([string]$RootName)

            $fixtureRoot = Join-Path $TestDrive $RootName
            $dataDir = Join-Path $fixtureRoot 'data'

            New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null

            @{ epg_sources = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
            @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
            @{ blocks = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8

            return $fixtureRoot
        }
    }

    It 'uses a single local provider file instead of the tracked file' {
        $fixtureRoot = New-MinimalProviderFixtureRoot -RootName 'local-preferred'
        $dataDir = Join-Path $fixtureRoot 'data'

        @{ provider = 'tracked-should-not-be-used'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8
        @{ provider = 'local-provider'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\provider.local.json') -Encoding UTF8

        & $script:ScriptPath -Root $fixtureRoot

        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.Provider | Should -Be 'local-provider'
    }

    It 'fails the build with no fallback when the selected local provider file is malformed JSON' {
        $fixtureRoot = New-MinimalProviderFixtureRoot -RootName 'local-malformed'
        $dataDir = Join-Path $fixtureRoot 'data'

        @{ provider = 'tracked-should-not-be-used'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dataDir 'providers\provider.local.json') -Value '{ this is not valid json' -Encoding UTF8

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw

        Test-Path -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -PathType Leaf | Should -BeFalse
    }

    It 'fails clearly when neither an override, a local file, nor the tracked fallback file exists' {
        $fixtureRoot = New-MinimalProviderFixtureRoot -RootName 'no-provider-file'

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw '*Provider file not found*'
    }

    It 'uses an explicit -ProviderPath override even when a local file also exists' {
        $fixtureRoot = New-MinimalProviderFixtureRoot -RootName 'override-precedence'
        $dataDir = Join-Path $fixtureRoot 'data'

        @{ provider = 'tracked-should-not-be-used'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8
        @{ provider = 'local-should-not-be-used'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\provider.local.json') -Encoding UTF8
        @{ provider = 'override-provider'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\chosen.local.json') -Encoding UTF8

        & $script:ScriptPath -Root $fixtureRoot -ProviderPath 'chosen.local.json'

        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.Provider | Should -Be 'override-provider'
    }

    It 'fails the build when multiple local provider files exist and no override is given' {
        $fixtureRoot = New-MinimalProviderFixtureRoot -RootName 'ambiguous-local'
        $dataDir = Join-Path $fixtureRoot 'data'

        @{ provider = 'tracked'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8
        @{ provider = 'a'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\a.local.json') -Encoding UTF8
        @{ provider = 'b'; sources = @(@{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/x'; enabled = $true }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\b.local.json') -Encoding UTF8

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw '*Multiple local provider files*'
    }
}

Describe 'Build-Lineup.ps1 (no provider URLs or tokens in console output)' {
    It 'never writes a provider URL, account ID, or token to the console' {
        $fixtureRoot = Join-Path $TestDrive 'console-output-project'
        $dataDir = Join-Path $fixtureRoot 'data'

        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null

        @{
            provider = 'fixture-provider'
            sources  = @(
                @{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports'; enabled = $true }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        @{ epg_sources = @(@{ name = 'x'; priority = 1; url = 'https://example.invalid/epg/ACCOUNT_ID/API_TOKEN/y.xml'; enabled = $true; role = 'primary' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8

        $output = & $script:ScriptPath -Root $fixtureRoot *>&1 | Out-String

        $output | Should -Not -Match 'https?://'
        $output | Should -Not -Match 'ACCOUNT_ID'
        $output | Should -Not -Match 'API_TOKEN'
    }
}
