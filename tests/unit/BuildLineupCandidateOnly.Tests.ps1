BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    $script:PlaylistFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\playlist.m3u'
    $script:GuideFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\guide.xml'
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-BuildLineupCandidateRoot {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive $Name
        $data = Join-Path $root 'data'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $data 'providers'), (Join-Path $data 'epg'),
            (Join-Path $data 'lineup'), (Join-Path $data 'rules'),
            (Join-Path $data 'playlists') | Out-Null
        Copy-Item -LiteralPath $script:PlaylistFixture -Destination (Join-Path $data 'playlists\playlist.m3u')
        Copy-Item -LiteralPath $script:GuideFixture -Destination (Join-Path $data 'epg\guide.xml')
        @{ provider = 'candidate-only-fixture'; sources = @(@{ name = 'Playlist'; group = 'General'; url = 'https://example.invalid/fixture'; enabled = $true; local_playlist = 'data/playlists/playlist.m3u' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'providers\mybunny.json') -Encoding UTF8
        @{ epg_sources = @(@{ name = 'Guide'; priority = 10; path = 'guide.xml'; enabled = $true; role = 'primary' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @(@{ start = 1; end = 9999; category = 'General'; notes = 'candidate-only fixture' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'rules\aliases.json') -Encoding UTF8
        return $root
    }

    function Get-CandidateFile {
        param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name)
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        return Join-Path $Root ((Join-Path ($summary.CandidateNamespacePath -replace '/', '\') $Name))
    }
}

Describe 'Build-Lineup candidate-only publication' {
    It 'does not touch legacy public outputs or rollback directories' {
        $root = New-BuildLineupCandidateRoot -Name 'candidate-only-boundary'
        $output = Join-Path $root 'output'
        New-Item -ItemType Directory -Force -Path (Join-Path $output 'm3u-rollback'), (Join-Path $output 'xmltv-rollback') | Out-Null
        [IO.File]::WriteAllText((Join-Path $output 'merged.m3u'), 'old m3u')
        [IO.File]::WriteAllText((Join-Path $output 'merged.xml'), 'old xml')
        [IO.File]::WriteAllText((Join-Path $output 'm3u-rollback\merged.m3u.previous'), 'old m3u rollback')
        [IO.File]::WriteAllText((Join-Path $output 'xmltv-rollback\merged.xml.previous'), 'old xml rollback')

        & $script:BuildPath -Root $root

        (Get-Content -LiteralPath (Join-Path $output 'merged.m3u') -Raw) | Should -Be 'old m3u'
        (Get-Content -LiteralPath (Join-Path $output 'merged.xml') -Raw) | Should -Be 'old xml'
        (Get-Content -LiteralPath (Join-Path $output 'm3u-rollback\merged.m3u.previous') -Raw) | Should -Be 'old m3u rollback'
        (Get-Content -LiteralPath (Join-Path $output 'xmltv-rollback\merged.xml.previous') -Raw) | Should -Be 'old xml rollback'
        Test-Path -LiteralPath (Get-CandidateFile -Root $root -Name 'manifest.json') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Get-CandidateFile -Root $root -Name 'merged.m3u') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Get-CandidateFile -Root $root -Name 'merged.xml') -PathType Leaf | Should -BeTrue
    }

    It 'reuses one deterministic candidate namespace for equivalent repeated builds' {
        $root = New-BuildLineupCandidateRoot -Name 'candidate-repeat'
        & $script:BuildPath -Root $root
        $first = Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        & $script:BuildPath -Root $root
        $second = Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $second.CandidateManifestHash | Should -Be $first.CandidateManifestHash
        $second.CandidateBuildIdentity | Should -Be $first.CandidateBuildIdentity
        $second.CandidateNamespacePath | Should -Be $first.CandidateNamespacePath
        @($second.CandidateNamespacePath -split '/')[-1] | Should -Match '^[0-9a-f]{64}$'
    }

    It 'keeps candidate manifest and review artifacts free of stream URLs and local paths' {
        $root = New-BuildLineupCandidateRoot -Name 'candidate-privacy'
        & $script:BuildPath -Root $root
        foreach ($name in @('manifest.json', 'lineup-change-review.json', 'lineup-change-review.md')) {
            $content = Get-Content -LiteralPath (Get-CandidateFile -Root $root -Name $name) -Raw
            $content | Should -Not -Match 'https?://|[A-Z]:\\|^\\\\'
        }
    }
}
