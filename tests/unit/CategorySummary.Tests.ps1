BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    $script:GuideFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\guide.xml'
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    $script:CleanPlaylist = @(
        '#EXTM3U'
        '#EXTINF:-1 tvg-id="wwe.us" tvg-name="WWE" group-title="Sports",WWE Network'
        'https://example.invalid/live/wwe'
        '#EXTINF:-1 tvg-id="misc.us" tvg-name="Misc" group-title="Misc",Mystery Channel'
        'https://example.invalid/live/misc'
    )
    $script:FlaggedPlaylist = $script:CleanPlaylist + @(
        '#EXTINF:-1 tvg-id="bally.us" tvg-name="Bally" group-title="Sports",Bally Plus'
        'https://example.invalid/live/bally'
        '#EXTINF:-1 tvg-id="ufc.us" tvg-name="UFC" group-title="Boxing",UFC Fight Pass'
        'https://example.invalid/live/ufc'
    )

    function New-CategoryBuildRoot {
        param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$Playlist)
        $root = Join-Path $TestDrive $Name
        $data = Join-Path $root 'data'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $data 'providers'), (Join-Path $data 'epg'),
            (Join-Path $data 'lineup'), (Join-Path $data 'rules'),
            (Join-Path $data 'playlists') | Out-Null
        [IO.File]::WriteAllText((Join-Path $data 'playlists\playlist.m3u'), (($Playlist -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
        Copy-Item -LiteralPath $script:GuideFixture -Destination (Join-Path $data 'epg\guide.xml')
        @{ provider = 'category-summary-fixture'; sources = @(@{ name = 'Playlist'; group = 'General'; url = 'https://example.invalid/fixture'; enabled = $true; local_playlist = 'data/playlists/playlist.m3u' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'providers\mybunny.json') -Encoding UTF8
        @{ epg_sources = @(@{ name = 'Guide'; priority = 10; path = 'guide.xml'; enabled = $true; role = 'primary' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @(@{ start = 1; end = 9999; category = 'General'; notes = 'fixture' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'rules\aliases.json') -Encoding UTF8
        return $root
    }

    function Invoke-CategoryBuild {
        param([Parameter(Mandatory)][string]$Root)
        $captured = @()
        $captured = @(& $script:BuildPath -Root $Root 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        [pscustomobject]@{
            Hash     = [string]$summary.CandidateManifestHash
            Markdown = @(Get-Content -LiteralPath (Join-Path $Root 'output\reports\lineup-plan.md'))
            Warnings = @($captured | ForEach-Object { [string]$_.Message })
        }
    }
}

Describe 'Build summary category section' {
    It 'shows counts, names the channels to check and gives the override hint once' {
        $result = Invoke-CategoryBuild -Root (New-CategoryBuildRoot -Name 'flagged' -Playlist $script:FlaggedPlaylist)
        $text = $result.Markdown -join "`n"
        $text | Should -BeLike '*## Category Check*'
        $text | Should -BeLike '*wrestling 1*'
        $text | Should -BeLike '*Low confidence: 1*'
        $text | Should -BeLike '*Bally Plus*'
        $text | Should -BeLike '*UFC Fight Pass*'
        @($result.Markdown | Where-Object { $_ -like '*Set-ChannelForgeCategoryOverride*' }).Count | Should -Be 1
    }

    It 'adds at most one counts line when nothing needs a look' {
        $result = Invoke-CategoryBuild -Root (New-CategoryBuildRoot -Name 'clean' -Playlist $script:CleanPlaylist)
        $text = $result.Markdown -join "`n"
        $text | Should -Not -BeLike '*## Category Check*'
        $text | Should -Not -BeLike '*Set-ChannelForgeCategoryOverride*'
        @($result.Markdown | Where-Object { $_ -like 'Categories:*' }).Count | Should -Be 1
    }

    It 'turns a report failure into one warning, keeps the build, and leaves the candidate hash alone' {
        $clean = New-CategoryBuildRoot -Name 'hash-ok' -Playlist $script:FlaggedPlaylist
        $broken = New-CategoryBuildRoot -Name 'hash-broken' -Playlist $script:FlaggedPlaylist
        New-Item -ItemType Directory -Force -Path (Join-Path $broken 'state') | Out-Null
        [IO.File]::WriteAllText((Join-Path $broken 'state\category-overrides.json'), '{ not json')

        $good = Invoke-CategoryBuild -Root $clean
        $bad = Invoke-CategoryBuild -Root $broken

        @($bad.Warnings | Where-Object { $_ -like '*category*' }).Count | Should -Be 1
        ($bad.Markdown -join "`n") | Should -Not -BeLike '*## Category Check*'
        $bad.Hash | Should -Match '^[0-9a-f]{64}$'
        $bad.Hash | Should -Be $good.Hash
        @($good.Warnings | Where-Object { $_ -like '*category*' }).Count | Should -Be 0
    }
}
