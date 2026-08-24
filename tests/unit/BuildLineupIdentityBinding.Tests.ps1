BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildScriptPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
    $script:IdentityPlaylistPath = Join-Path $RepoRoot 'tests\fixtures\identity-binding\playlist.m3u'
    $script:IdentityGuidePath = Join-Path $RepoRoot 'tests\fixtures\identity-binding\guide.xml'
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-IdentityBindingBuildRoot {
        param(
            [AllowNull()]
            [object]$PlaylistContent = $null
        )

        $fixtureRoot = Join-Path $TestDrive 'identity-binding-build'
        $dataDir = Join-Path $fixtureRoot 'data'
        $playlistDir = Join-Path $dataDir 'playlists'

        New-Item -ItemType Directory -Force -Path `
            (Join-Path $dataDir 'providers'),
            (Join-Path $dataDir 'epg'),
            (Join-Path $dataDir 'lineup'),
            (Join-Path $dataDir 'rules'),
            $playlistDir | Out-Null

        if ($null -eq $PlaylistContent) {
            Copy-Item -LiteralPath $script:IdentityPlaylistPath -Destination (Join-Path $playlistDir 'playlist.m3u')
        }
        else {
            $PlaylistContent | Set-Content -LiteralPath (Join-Path $playlistDir 'playlist.m3u') -Encoding utf8NoBOM
        }
        Copy-Item -LiteralPath $script:IdentityGuidePath -Destination (Join-Path $dataDir 'epg\guide.xml')

        @{
            provider = 'fixture-provider'
            sources  = @(
                @{ name = 'Identity Playlist'; group = 'News'; url = 'https://example.invalid/iptv/fixture'; enabled = $true; local_playlist = 'data/playlists/playlist.m3u' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        @{ epg_sources = @(
                @{ name = 'Identity Guide'; priority = 10; path = 'guide.xml'; enabled = $true; role = 'primary' }
            ) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @(@{ start = 1; end = 9999; category = 'News'; notes = 'identity binding fixture' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding UTF8

        return $fixtureRoot
    }
}

Describe 'Build-Lineup.ps1 M3U/XMLTV identity binding report' {
    It 'records exact, unbound, review-needed, and XMLTV-only identities without rewriting canonical outputs' {
        $fixtureRoot = New-IdentityBindingBuildRoot
        & $script:BuildScriptPath -Root $fixtureRoot

        $summaryPath = Join-Path $fixtureRoot 'output\reports\build-summary.json'
        $planPath = Join-Path $fixtureRoot 'output\reports\lineup-plan.md'
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $plan = Get-Content -LiteralPath $planPath -Raw
        $m3u = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\merged.m3u') -Raw
        $xmltv = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\merged.xml') -Raw

        $summary.M3UXmltvBindingStatus | Should -Be 'EVALUATED_WITH_REVIEW'
        $summary.M3UXmltvExactBindingCount | Should -Be 2
        $summary.M3UXmltvUnboundChannelCount | Should -Be 2
        $summary.M3UXmltvReviewNeededCount | Should -Be 1
        $summary.M3UXmltvOrphanedXmltvCount | Should -Be 1
        @($summary.M3UXmltvExactBindings.M3UChannel.TvgId) | Should -Be @('alpha.us', 'zeta.us')
        $summary.M3UXmltvExactBindings[0].Evidence[0].SourceId | Should -Be 'Identity Guide'
        $summary.M3UXmltvExactBindings[0].Evidence[0].ChannelCount | Should -Be 4
        $summary.M3UXmltvReviewNeeded[0].Candidates[0].DeclarationCount | Should -Be 2
        $summary.M3UXmltvOrphanedXmltvChannels[0].XmltvChannelId | Should -Be 'orphan.us'

        $plan | Should -Match 'M3U/XMLTV Identity Binding'
        $plan | Should -Match "EXACT: tvg-id 'alpha.us'"
        $plan | Should -Match 'REVIEW NEEDED: tvg-id ''ambiguous.us'''
        $plan | Should -Match 'XMLTV-ONLY: channel ''orphan.us'''
        $plan | Should -Not -Match 'https?://|example\.invalid|[A-Z]:\\|^\\\\'
        $summary = Get-Content -LiteralPath $summaryPath -Raw
        $summary | Should -Not -Match 'https?://|example\.invalid|[A-Z]:\\|^\\\\'

        $m3u | Should -Match 'tvg-id="alpha.us"'
        $xmltv | Should -Match '<channel id='
        $xmltv | Should -Not -Match 'tvg-id='
    }

    It 'does not exact-bind a normalized pre-dedup M3U collision through Build-Lineup' {
        $playlist = @(
            '#EXTM3U'
            '#EXTINF:-1 tvg-id="zeta.us" group-title="News",Zeta Primary'
            'https://example.invalid/live/zeta-primary'
            '#EXTINF:-1 tvg-id=" ZETA.US " group-title="News",Zeta Colliding'
            'https://example.invalid/live/zeta-colliding'
        ) -join "`n"
        $fixtureRoot = New-IdentityBindingBuildRoot -PlaylistContent $playlist

        & $script:BuildScriptPath -Root $fixtureRoot

        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\lineup-plan.md') -Raw
        $review = @($summary.M3UXmltvReviewNeeded | Where-Object {
                $_.M3UChannel.TvgId -ceq 'zeta.us'
            })

        $summary.M3UXmltvExactBindingCount | Should -Be 0
        $review.Count | Should -Be 1
        $review[0].Reason | Should -Be 'MultipleM3UChannelsShareNormalizedIdentity'
        @($review[0].M3UIdentityCollision.Channels).Count | Should -Be 2
        @($review[0].M3UIdentityCollision.Channels.TvgId) | Should -Be @('zeta.us', ' ZETA.US ')
        $plan | Should -Match 'M3U COLLISION'
        $plan | Should -Match ' ZETA\.US '

        $merged = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\merged.m3u') -Raw
        ([regex]::Matches($merged, '#EXTINF:')).Count | Should -Be 1
        $merged | Should -Match 'tvg-id="zeta.us"'
    }
}
