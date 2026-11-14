BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    $script:Playlist = @(
        '#EXTM3U'
        '#EXTINF:-1 tvg-id="max.us" tvg-name="Max" group-title="Movies",Movie Max'
        'https://example.invalid/live/max'
        '#EXTINF:-1 tvg-id="two.us" tvg-name="Two" group-title="Movies",Cinema Two'
        'https://example.invalid/live/two'
        '#EXTINF:-1 tvg-id="few.us" tvg-name="Few" group-title="Movies",Cinema Few'
        'https://example.invalid/live/few'
    )

    function New-GuideXml {
        param([Parameter(Mandatory)][hashtable]$Titles)
        $lines = @('<?xml version="1.0" encoding="UTF-8"?>', '<tv>')
        foreach ($id in $Titles.Keys) { $lines += "  <channel id=`"$id`"><display-name>$id</display-name></channel>" }
        foreach ($id in $Titles.Keys) {
            $hour = 8
            foreach ($title in $Titles[$id]) {
                $lines += "  <programme start=`"20260824$('{0:00}' -f $hour)0000 +0000`" stop=`"20260824$('{0:00}' -f ($hour + 1))0000 +0000`" channel=`"$id`"><title>$title</title></programme>"
                $hour++
            }
        }
        return (($lines + '</tv>') -join "`n") + "`n"
    }

    function New-CategoryBuildRoot {
        param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Guide)
        $root = Join-Path $TestDrive $Name
        $data = Join-Path $root 'data'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $data 'providers'), (Join-Path $data 'epg'),
            (Join-Path $data 'lineup'), (Join-Path $data 'rules'),
            (Join-Path $data 'playlists') | Out-Null
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText((Join-Path $data 'playlists\playlist.m3u'), (($script:Playlist -join "`n") + "`n"), $utf8)
        [IO.File]::WriteAllText((Join-Path $data 'epg\guide.xml'), $Guide, $utf8)
        @{ provider = 'category-programme-fixture'; sources = @(@{ name = 'Playlist'; group = 'General'; url = 'https://example.invalid/fixture'; enabled = $true; local_playlist = 'data/playlists/playlist.m3u' }) } |
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
        param([Parameter(Mandatory)][string]$Root, [string]$Script = $script:BuildPath)
        if ($Script -ne $script:BuildPath) {
            # A second copy of the module cannot share this session (class types clash), so run it in its own process.
            $text = @(& pwsh -NoProfile -File $Script -Root $Root *>&1 | ForEach-Object { [string]$_ })
            # The child may color its output, so match the word anywhere in the line.
            $captured = @($text | Where-Object { $_ -like '*WARNING:*' } | ForEach-Object { [pscustomobject]@{ Message = $_ } })
        }
        else {
            $captured = @(& $Script -Root $Root 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        }
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        [pscustomobject]@{
            Hash     = [string]$summary.CandidateManifestHash
            Markdown = @(Get-Content -LiteralPath (Join-Path $Root 'output\reports\lineup-plan.md'))
            Warnings = @($captured | ForEach-Object { [string]$_.Message })
        }
    }

    $script:Football = @('NFL Sunday Night', 'NFL Primetime', 'NFL Gameday Live', 'NFL Replay')
    $script:Movies = @('The Late Movie', 'Movie Matinee', 'Classic Movie Hour', 'Movie Premiere')
}

Describe 'Category check: programme titles against the channel category' {
    It 'names a movie channel that airs football and leaves the other channels out' {
        $guide = New-GuideXml -Titles @{ 'max.us' = $script:Football; 'two.us' = $script:Movies; 'few.us' = $script:Football[0..1] }
        $result = Invoke-CategoryBuild -Root (New-CategoryBuildRoot -Name 'mismatch' -Guide $guide)
        $line = @($result.Markdown | Where-Object { $_ -like 'Programme titles disagree*' })
        $line.Count | Should -Be 1
        $line[0] | Should -BeLike '*: 1 (Movie Max)*'
        $line[0] | Should -Not -BeLike '*Cinema*'
        ($result.Markdown -join "`n") | Should -BeLike '*## Category Check*'
    }

    It 'adds nothing when the programmes fit the channels or too few titles can be classified' {
        $guide = New-GuideXml -Titles @{ 'max.us' = $script:Movies; 'two.us' = $script:Movies; 'few.us' = ($script:Football[0..1] + 'Evening Show') }
        $result = Invoke-CategoryBuild -Root (New-CategoryBuildRoot -Name 'clean' -Guide $guide)
        ($result.Markdown -join "`n") | Should -Not -BeLike '*Programme titles disagree*'
    }

    It 'turns a failure into one warning, keeps the build and leaves the candidate hash alone' {
        $guide = New-GuideXml -Titles @{ 'max.us' = $script:Football; 'two.us' = $script:Movies; 'few.us' = $script:Football[0..1] }
        $good = Invoke-CategoryBuild -Root (New-CategoryBuildRoot -Name 'hash-ok' -Guide $guide)

        $clone = Join-Path $TestDrive 'clone'
        New-Item -ItemType Directory -Force -Path $clone | Out-Null
        foreach ($folder in 'scripts', 'src', 'schemas') { Copy-Item -LiteralPath (Join-Path $script:RepoRoot $folder) -Destination $clone -Recurse }
        Set-Content -LiteralPath (Join-Path $clone 'src\ChannelForge\Private\Get-ChannelForgeCategoryProgrammeCheck.ps1') -Value 'function Get-ChannelForgeCategoryProgrammeCheck { param($CandidateDirectory, $Report) throw "broken" }'
        $broken = Invoke-CategoryBuild -Root (New-CategoryBuildRoot -Name 'hash-broken' -Guide $guide) -Script (Join-Path $clone 'scripts\Build-Lineup.ps1')

        @($broken.Warnings | Where-Object { $_ -like '*category programme check*' }).Count | Should -Be 1
        ($broken.Markdown -join "`n") | Should -Not -BeLike '*Programme titles disagree*'
        $broken.Hash | Should -Match '^[0-9a-f]{64}$'
        $broken.Hash | Should -Be $good.Hash
        ($good.Markdown -join "`n") | Should -BeLike '*Programme titles disagree*'
    }
}
