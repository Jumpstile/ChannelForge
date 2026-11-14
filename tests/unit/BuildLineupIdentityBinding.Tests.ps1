BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildScriptPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
    $script:IdentityPlaylistPath = Join-Path $RepoRoot 'tests\fixtures\identity-binding\playlist.m3u'
    $script:IdentityGuidePath = Join-Path $RepoRoot 'tests\fixtures\identity-binding\guide.xml'
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-IdentityBindingBuildRoot {
        param(
            [AllowNull()]
            [object]$PlaylistContent = $null,

            [AllowNull()]
            [object]$GuideContent = $null
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
        if ($null -eq $GuideContent) {
            Copy-Item -LiteralPath $script:IdentityGuidePath -Destination (Join-Path $dataDir 'epg\guide.xml')
        }
        else {
            $GuideContent | Set-Content -LiteralPath (Join-Path $dataDir 'epg\guide.xml') -Encoding utf8NoBOM
        }

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
        $candidateRoot = Join-Path $fixtureRoot ($summary.CandidateNamespacePath -replace '/', '\')
        $m3u = Get-Content -LiteralPath (Join-Path $candidateRoot 'merged.m3u') -Raw
        $xmltv = Get-Content -LiteralPath (Join-Path $candidateRoot 'merged.xml') -Raw

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
        Test-Path -LiteralPath (Join-Path $fixtureRoot 'output\merged.m3u') -PathType Leaf | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixtureRoot 'output\merged.xml') -PathType Leaf | Should -BeFalse
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

        $summary.CandidateNamespacePath | Should -Match '^output/candidates/[0-9a-f]{64}$'
        $candidateRoot = Join-Path $fixtureRoot ($summary.CandidateNamespacePath -replace '/', '\')
        $merged = Get-Content -LiteralPath (Join-Path $candidateRoot 'merged.m3u') -Raw
        ([regex]::Matches($merged, '#EXTINF:')).Count | Should -Be 1
        $merged | Should -Match 'tvg-id="zeta.us"'
        Test-Path -LiteralPath (Join-Path $fixtureRoot 'output\merged.m3u') -PathType Leaf | Should -BeFalse
    }

    It 'lists an exact channel whose guide has no programmes and keeps it in the playlist' {
        $guide = @(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<tv>'
            '<channel id="zeta.us"><display-name>Zeta</display-name></channel>'
            '<channel id="alpha.us"><display-name>Alpha</display-name></channel>'
            '<programme start="20260824080000 +0000" stop="20260824090000 +0000" channel="zeta.us"><title>Z1</title></programme>'
            '<programme start="20260824090000 +0000" stop="20260824100000 +0000" channel="zeta.us"><title>Z2</title></programme>'
            '</tv>'
        ) -join "`n"
        $fixtureRoot = New-IdentityBindingBuildRoot -GuideContent $guide

        & $script:BuildScriptPath -Root $fixtureRoot

        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\lineup-plan.md') -Raw
        $zeta = @($summary.M3UXmltvEpgCoverage | Where-Object { $_.TvgId -ceq 'zeta.us' })

        $summary.M3UXmltvEmptyGuideCount | Should -Be 1
        @($summary.M3UXmltvEmptyGuide.TvgId) | Should -Be @('alpha.us')
        $zeta[0].ProgrammeCount | Should -Be 2
        $zeta[0].FirstStartUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') | Should -Be '2026-08-24T08:00:00Z'
        $zeta[0].LastStopUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') | Should -Be '2026-08-24T10:00:00Z'
        $plan | Should -Match 'Channels with a guide but no programmes: 1'
        $plan | Should -Match "tvg-id 'alpha\.us'"
        $plan | Should -Not -Match "tvg-id 'zeta\.us' /"

        @($summary.M3UXmltvExactBindings | Where-Object { $_.M3UChannel.TvgId -ceq 'alpha.us' }).Count | Should -Be 1
        $candidateRoot = Join-Path $fixtureRoot ($summary.CandidateNamespacePath -replace '/', '\')
        (Get-Content -LiteralPath (Join-Path $candidateRoot 'merged.m3u') -Raw) | Should -Match 'tvg-id="alpha.us"'
    }

    It 'publishes the same bytes as before when no guide is empty' {
        $fixtureRoot = New-IdentityBindingBuildRoot

        & $script:BuildScriptPath -Root $fixtureRoot

        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.M3UXmltvEmptyGuideCount | Should -Be 0
        # Hashes recorded from this fixture before the coverage report existed.
        $summary.M3USha256 | Should -Be '1266e1683fc4b0a1adc74949308c503c0849dfb1c5ab65aa9e365bdebe1d506f'
        $summary.XMLTVSha256 | Should -Be '7ba3745695cb5782d120e953edde2e28ace39158dc1d5e22d02f7ecd621ed77c'
        $summary.CandidateBuildIdentity | Should -Be '430a96b5c21d5c5cc92d5ebff0abd50d77b5151b47d3f886d3af2a81a4df9bc2'
    }
}

Describe 'Build-Lineup.ps1 guide end date and age warning' {
    BeforeAll {
        $script:GuideEndGuide = @(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<tv>'
            '<channel id="zeta.us"><display-name>Zeta</display-name></channel>'
            '<programme start="20260824080000 +0000" stop="20260824100000 +0000" channel="zeta.us"><title>Z1</title></programme>'
            '</tv>'
        ) -join "`n"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:BuildScriptPath, [ref]$null, [ref]$null)
        $def = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ChannelForgeGuideEnd' }, $true)
        . ([scriptblock]::Create($def.Extent.Text))
    }

    It 'gives no warning when the guide ends well after build time' {
        $fixtureRoot = New-IdentityBindingBuildRoot -GuideContent $script:GuideEndGuide
        & $script:BuildScriptPath -Root $fixtureRoot -BuildTimeUtc ([datetime]'2026-08-20T00:00:00Z')
        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\lineup-plan.md') -Raw
        $summary.GuideEndsUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') | Should -Be '2026-08-24T10:00:00Z'
        $summary.GuideAgeWarning | Should -BeFalse
        @($summary.GuideEndsUtcBySource).Count | Should -Be 1
        $plan | Should -Not -Match 'WARNING: the guide ends'
    }

    It 'warns but still builds when the guide ends within 48 hours of build time' {
        $fixtureRoot = New-IdentityBindingBuildRoot -GuideContent $script:GuideEndGuide
        & $script:BuildScriptPath -Root $fixtureRoot -BuildTimeUtc ([datetime]'2026-08-23T00:00:00Z')
        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\lineup-plan.md') -Raw
        $summary.GuideAgeWarning | Should -BeTrue
        $summary.M3UXmltvExactBindingCount | Should -Be 1
        $plan | Should -Match 'WARNING: the guide ends 2026-08-24T10:00:00Z.*Get a newer guide file'
    }

    It 'warns when the guide already ended' {
        $fixtureRoot = New-IdentityBindingBuildRoot -GuideContent $script:GuideEndGuide
        & $script:BuildScriptPath -Root $fixtureRoot -BuildTimeUtc ([datetime]'2026-09-30T00:00:00Z')
        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.GuideAgeWarning | Should -BeTrue
    }

    It 'returns a null end date and no warning when there are no programmes' {
        $r = Get-ChannelForgeGuideEnd -Programme @() -NowUtc ([datetime]'2026-08-20T00:00:00Z')
        $r.GuideEndsUtc | Should -BeNullOrEmpty
        $r.GuideAgeWarning | Should -BeFalse
    }

    It 'leaves published bytes, hashes and build identity unchanged whatever the clock says' {
        $fixtureRoot = New-IdentityBindingBuildRoot
        & $script:BuildScriptPath -Root $fixtureRoot -BuildTimeUtc ([datetime]'2030-01-01T00:00:00Z')
        $summary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.GuideAgeWarning | Should -BeTrue
        $summary.M3USha256 | Should -Be '1266e1683fc4b0a1adc74949308c503c0849dfb1c5ab65aa9e365bdebe1d506f'
        $summary.XMLTVSha256 | Should -Be '7ba3745695cb5782d120e953edde2e28ace39158dc1d5e22d02f7ecd621ed77c'
        $summary.CandidateBuildIdentity | Should -Be '430a96b5c21d5c5cc92d5ebff0abd50d77b5151b47d3f886d3af2a81a4df9bc2'
    }
}
