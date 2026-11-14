BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    # Programmes as the build holds them: (source, channel, "HH:mm" start on 2030-01-01 UTC, minutes, title).
    function New-XgProgramme {
        param([string]$Source, [string]$Channel, [string]$At, [int]$Minutes, [string]$Title, [int]$Day = 1)
        $start = [datetimeoffset]::Parse("2030-01-{0:00}T${At}:00Z" -f $Day, [Globalization.CultureInfo]::InvariantCulture)
        $p = & (Get-Module ChannelForge) { [Programme]::new() }
        $p.SourceId = $Source; $p.ChannelId = $Channel; $p.Start = $start; $p.End = $start.AddMinutes($Minutes); $p.Title = $Title
        return $p
    }

    # Returns the summary lines for a programme list, the way the build asks for them.
    function Get-XgLines {
        param([object[]]$Programme, [string[]]$Guide = @())
        $now = [datetime]::Parse('2029-12-31T00:00:00Z').ToUniversalTime()
        $result = & (Get-Module ChannelForge) {
            param($prog, $now, $guide)
            $r = Get-ChannelForgeXguideReport -Programme $prog -BuildTimeUtc $now -GuideSourceId $guide
            , @(Get-ChannelForgeXguideSummaryLines -Report $r)
        } $Programme $now $Guide
        return ,@($result)
    }

    function New-XgBuildRoot {
        param([Parameter(Mandatory)][string]$Name, [string]$TitleB = 'Film Night')
        $root = Join-Path $TestDrive $Name
        $data = Join-Path $root 'data'
        New-Item -ItemType Directory -Force -Path (Join-Path $data 'providers'), (Join-Path $data 'epg'), (Join-Path $data 'lineup'), (Join-Path $data 'rules'), (Join-Path $data 'playlists') | Out-Null
        [IO.File]::WriteAllText((Join-Path $data 'playlists\playlist.m3u'), "#EXTM3U`n#EXTINF:-1 tvg-id=`"wwe.us`" tvg-name=`"WWE`" group-title=`"Sports`",WWE Network`nhttps://example.invalid/live/wwe`n", [System.Text.UTF8Encoding]::new($false))
        $guideA = '<tv><channel id="wwe.us"><display-name>WWE</display-name></channel><programme start="20300101200000 +0000" stop="20300101210000 +0000" channel="wwe.us"><title>Evening News</title></programme><programme start="20300101210000 +0000" stop="20300101220000 +0000" channel="wwe.us"><title>Movie Night</title></programme></tv>'
        $guideB = "<tv><channel id=`"wwe.us`"><display-name>WWE</display-name></channel><programme start=`"20300101201000 +0000`" stop=`"20300101210000 +0000`" channel=`"wwe.us`"><title>Evening News</title></programme><programme start=`"20300101210000 +0000`" stop=`"20300101220000 +0000`" channel=`"wwe.us`"><title>$TitleB</title></programme></tv>"
        [IO.File]::WriteAllText((Join-Path $data 'epg\a.xml'), $guideA)
        [IO.File]::WriteAllText((Join-Path $data 'epg\b.xml'), $guideB)
        @{ provider = 'xguide-fixture'; sources = @(@{ name = 'Playlist'; group = 'General'; url = 'https://example.invalid/fixture'; enabled = $true; local_playlist = 'data/playlists/playlist.m3u' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'providers\mybunny.json') -Encoding UTF8
        @{ epg_sources = @(
                @{ name = 'Guide A'; priority = 10; path = 'a.xml'; enabled = $true; role = 'primary' },
                @{ name = 'Guide B'; priority = 20; path = 'b.xml'; enabled = $true; role = 'secondary' }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @(@{ start = 1; end = 9999; category = 'General'; notes = 'fixture' }) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'rules\aliases.json') -Encoding UTF8
        return $root
    }

    function Invoke-XgBuild {
        param([Parameter(Mandatory)][string]$Root, [string]$Script = $script:BuildPath)
        # A separate process keeps two copies of the module's classes from clashing.
        $out = @(& pwsh -NoProfile -File $Script -Root $Root 3>&1 *>&1 | ForEach-Object { [string]$_ })
        $warnings = @($out | Where-Object { $_ -like '*WARNING:*' } | ForEach-Object { $_ })
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        [pscustomobject]@{
            Hash     = [string]$summary.CandidateManifestHash
            Markdown = @(Get-Content -LiteralPath (Join-Path $Root 'output\reports\lineup-plan.md'))
            Warnings = @($warnings)
        }
    }
}

Describe 'Guide comparison lines' {
    It 'gives one agreement line when two guides agree' {
        $lines = Get-XgLines -Programme @(
            (New-XgProgramme 'A' 'ch1' '20:00' 60 'News'), (New-XgProgramme 'B' 'ch1' '20:00' 60 ' news '))
        $lines.Count | Should -Be 1
        $lines[0] | Should -Be 'Guide comparison: 2 guides, 1 shared channels, all programmes agree.'
    }

    It 'names a channel that one guide lacks' {
        $lines = Get-XgLines -Programme @(
            (New-XgProgramme 'A' 'ch1' '20:00' 60 'News'), (New-XgProgramme 'B' 'ch1' '20:00' 60 'News'),
            (New-XgProgramme 'A' 'ch2' '20:00' 60 'Sports'))
        $lines | Should -Contain '- channel ch2: in A, not in B'
    }

    It 'shows both start times when the same title starts at another time' {
        $lines = Get-XgLines -Programme @(
            (New-XgProgramme 'A' 'ch1' '20:00' 60 'Evening News'), (New-XgProgramme 'B' 'ch1' '20:10' 50 'Evening News'))
        $lines | Should -Contain '- channel ch1: "Evening News" starts 2030-01-01 20:00 in A, 2030-01-01 20:10 in B'
        ($lines -join "`n") | Should -BeLike '*Nothing was changed.*'
    }

    It 'shows both titles when the same slot has different titles' {
        $lines = Get-XgLines -Programme @(
            (New-XgProgramme 'A' 'ch1' '20:00' 60 'Evening News'), (New-XgProgramme 'B' 'ch1' '20:05' 55 'News Hour'))
        $lines | Should -Contain '- channel ch1: 2030-01-01 20:00 is "Evening News" in A, "News Hour" in B'
    }

    It 'shows a programme with no match in the other guide, with both titles and times' {
        $lines = Get-XgLines -Programme @(
            (New-XgProgramme 'A' 'ch1' '20:00' 60 'News'), (New-XgProgramme 'A' 'ch1' '21:00' 60 'Cooking'),
            (New-XgProgramme 'B' 'ch1' '20:00' 60 'News'), (New-XgProgramme 'B' 'ch1' '21:45' 15 'Weather'))
        $lines | Should -Contain '- channel ch1: "Cooking" at 2030-01-01 21:00 in A; nearest in B is "Weather" at 2030-01-01 21:45'
    }

    It 'names a guide that ends earlier than the other' {
        $lines = Get-XgLines -Programme @(
            (New-XgProgramme 'A' 'ch1' '20:00' 60 'News'), (New-XgProgramme 'B' 'ch1' '20:00' 60 'News'),
            (New-XgProgramme 'B' 'ch1' '20:00' 60 'Later' -Day 4))
        ($lines -join "`n") | Should -BeLike '*guide A ends 2030-01-01 21:00, the newest guide ends 2030-01-04 21:00 (72 h behind)*'
    }

    It 'adds nothing for one guide, or for guides that share no channel' {
        (Get-XgLines -Programme @((New-XgProgramme 'A' 'ch1' '20:00' 60 'News'))).Count | Should -Be 0
        (Get-XgLines -Programme @((New-XgProgramme 'A' 'ch1' '20:00' 60 'News'), (New-XgProgramme 'B' 'ch2' '20:00' 60 'News'))).Count | Should -Be 0
    }

    It 'gives identical lines when the guide order is swapped' {
        $programmes = @(
            (New-XgProgramme 'A' 'ch1' '20:00' 60 'Evening News'), (New-XgProgramme 'B' 'ch1' '20:10' 50 'Evening News'),
            (New-XgProgramme 'A' 'ch2' '20:00' 60 'Sports'), (New-XgProgramme 'B' 'ch2' '20:05' 55 'Golf'),
            (New-XgProgramme 'A' 'ch3' '20:00' 60 'Only A'))
        $forward = Get-XgLines -Programme $programmes -Guide @('A', 'B')
        $reversed = Get-XgLines -Programme @($programmes[($programmes.Count - 1)..0]) -Guide @('B', 'A')
        ($reversed -join "`n") | Should -Be ($forward -join "`n")
        $forward.Count | Should -BeGreaterThan 3
    }
}

Describe 'Build summary guide comparison section' {
    It 'shows the disagreement, keeps the candidate hash, and shows nothing sensitive' {
        $shown = Invoke-XgBuild -Root (New-XgBuildRoot -Name 'shown')
        $text = $shown.Markdown -join "`n"
        $text | Should -BeLike '*## Guide Comparison*'
        $text | Should -BeLike '*"Evening News" starts 2030-01-01 20:00 in Guide A, 2030-01-01 20:10 in Guide B*'
        $text | Should -BeLike '*"Movie Night" in Guide A, "Film Night" in Guide B*'
        $text.IndexOf('## Guide Comparison') | Should -BeLessThan $text.IndexOf('## M3U/XMLTV Identity Binding')
        $section = $shown.Markdown[($shown.Markdown.IndexOf('## Guide Comparison'))..($shown.Markdown.IndexOf('## M3U/XMLTV Identity Binding') - 1)] -join "`n"
        $section | Should -Not -Match '(?i)https?://|[a-z]:[\\/]'
        $section | Should -Not -BeLike "*$TestDrive*"

        $url = Invoke-XgBuild -Root (New-XgBuildRoot -Name 'url' -TitleB 'https://example.invalid/x?token=1')
        ($url.Markdown -join "`n") | Should -Not -BeLike '*example.invalid/x*'

        # A copy of the tool whose comparison always fails.
        $copy = Join-Path $TestDrive 'tool-copy'
        New-Item -ItemType Directory -Force -Path $copy | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'src'), (Join-Path $script:RepoRoot 'scripts'), (Join-Path $script:RepoRoot 'schemas'), (Join-Path $script:RepoRoot 'config') -Destination $copy -Recurse
        Set-Content -LiteralPath (Join-Path $copy 'src\ChannelForge\Private\Get-ChannelForgeXguideReport.ps1') -Value 'function Get-ChannelForgeXguideReport { throw ''boom'' }'
        $broken = Invoke-XgBuild -Root (New-XgBuildRoot -Name 'broken') -Script (Join-Path $copy 'scripts\Build-Lineup.ps1')
        @($broken.Warnings | Where-Object { $_ -like '*guide comparison*' }).Count | Should -Be 1
        ($broken.Markdown -join "`n") | Should -Not -BeLike '*## Guide Comparison*'
        $broken.Hash | Should -Match '^[0-9a-f]{64}$'
        $broken.Hash | Should -Be $shown.Hash
    }
}
