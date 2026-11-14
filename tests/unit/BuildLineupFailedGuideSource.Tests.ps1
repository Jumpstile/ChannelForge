BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildScriptPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    $script:GoodGuide = @'
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="alpha.us"><display-name>Alpha</display-name></channel>
  <programme start="20260824100000 +0000" stop="20260824110000 +0000" channel="alpha.us"><title>Alpha Morning</title></programme>
</tv>
'@

    function New-FailedSourceBuildRoot {
        param([hashtable[]]$Guides)

        $root = Join-Path $TestDrive ('failed-source-' + [guid]::NewGuid().ToString('N'))
        $dataDir = Join-Path $root 'data'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $dataDir 'providers'), (Join-Path $dataDir 'epg'), (Join-Path $dataDir 'lineup'),
            (Join-Path $dataDir 'rules'), (Join-Path $dataDir 'playlists') | Out-Null

        @('#EXTM3U', '#EXTINF:-1 tvg-id="alpha.us" group-title="News",Alpha', 'https://example.invalid/live/alpha') -join "`n" |
            Set-Content -LiteralPath (Join-Path $dataDir 'playlists\playlist.m3u') -Encoding utf8NoBOM
        @{ provider = 'fixture-provider'; sources = @(
                @{ name = 'Playlist'; group = 'News'; url = 'https://example.invalid/iptv/fixture'; enabled = $true; local_playlist = 'data/playlists/playlist.m3u' }
            ) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        $entries = @()
        $priority = 10
        foreach ($guide in $Guides) {
            $guide.Content | Set-Content -LiteralPath (Join-Path $dataDir ('epg\' + $guide.File)) -Encoding utf8NoBOM
            $entries += @{ name = $guide.Name; priority = $priority; path = $guide.File; enabled = $true; role = 'primary' }
            $priority += 10
        }
        @{ epg_sources = $entries } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @(@{ start = 1; end = 9999; category = 'News'; notes = 'fixture' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding UTF8
        return $root
    }

    function Invoke-FailedSourceBuild {
        param([string]$Root)
        $message = $null
        try { & $script:BuildScriptPath -Root $Root *> $null } catch { $message = $_.Exception.Message }
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        [pscustomobject]@{ Message = $message; Summary = $summary }
    }
}

Describe 'Build-Lineup.ps1 names the failing XMLTV guide source' {
    It 'names only the failing source in the error and records it as Failed' {
        $root = New-FailedSourceBuildRoot -Guides @(
            @{ Name = 'Good Guide'; File = 'good.xml'; Content = $script:GoodGuide },
            @{ Name = 'Broken Guide'; File = 'broken.xml'; Content = '<tv><channel id="x">' })
        $run = Invoke-FailedSourceBuild -Root $root

        $run.Message | Should -Match "Broken Guide"
        $run.Message | Should -Not -Match 'Good Guide'
        $run.Message | Should -Not -Match '[A-Za-z]:\\|https?://|\\\\'
        $run.Summary.XMLTVStatus | Should -Be 'FAILED'
        $run.Summary.XMLTVFailureReason | Should -Be $run.Message
        $failed = @($run.Summary.XMLTVAcquisitionStatus | Where-Object { $_.Outcome -eq 'Failed' })
        $failed.Count | Should -Be 1
        $failed[0].SourceId | Should -Be 'Broken Guide'
        $failed[0].Reason | Should -Not -BeNullOrEmpty
        ($run.Summary | ConvertTo-Json -Depth 20) | Should -Not -Match '[A-Za-z]:\\\\|https?://'
    }

    It 'names the source whose programmes conflict' {
        $conflicting = $script:GoodGuide.Replace('</tv>',
            '  <programme start="20260824100000 +0000" stop="20260824110000 +0000" channel="alpha.us"><title>Different Title</title></programme>' + "`n</tv>")
        $root = New-FailedSourceBuildRoot -Guides @(
            @{ Name = 'Clean Guide'; File = 'clean.xml'; Content = $script:GoodGuide.Replace('alpha.us', 'beta.us') },
            @{ Name = 'Conflict Guide'; File = 'conflict.xml'; Content = $conflicting })
        $run = Invoke-FailedSourceBuild -Root $root

        $run.Message | Should -Match 'Conflict Guide'
        $run.Message | Should -Not -Match 'Clean Guide'
    }

    It 'builds normally and records no Failed source when every guide is good' {
        $root = New-FailedSourceBuildRoot -Guides @(@{ Name = 'Good Guide'; File = 'good.xml'; Content = $script:GoodGuide })
        $run = Invoke-FailedSourceBuild -Root $root

        $run.Message | Should -BeNullOrEmpty
        $run.Summary.XMLTVStatus | Should -Be 'GENERATED'
        @($run.Summary.XMLTVAcquisitionStatus | Where-Object { $_.Outcome -eq 'Failed' }).Count | Should -Be 0
    }
}
