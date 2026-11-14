BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-XgProgramme {
        param([string]$Source, [string]$Channel, [string]$At, [int]$Minutes, [string]$Title)
        $start = [datetimeoffset]::Parse("2030-01-01T${At}:00Z", [Globalization.CultureInfo]::InvariantCulture)
        $p = & (Get-Module ChannelForge) { [Programme]::new() }
        $p.SourceId = $Source; $p.ChannelId = $Channel; $p.Start = $start; $p.End = $start.AddMinutes($Minutes); $p.Title = $Title
        return $p
    }

    # Saved source set: playlists alpha and beta, guides named as given, each bound as "guide=playlist".
    function New-XgProject {
        param([string[]]$Playlist, [hashtable]$Bind)
        $project = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $project | Out-Null
        $add = {
            param($name, $kind)
            $path = Join-Path $project "$name.$(if ($kind -eq 'M3U') { 'm3u' } else { 'xml' })"
            $text = if ($kind -eq 'M3U') { "#EXTM3U`n#EXTINF:-1 tvg-id=`"$name`",$name`nhttps://example.invalid/$name`n" }
            else { "<?xml version=`"1.0`"?><tv><channel id=`"$name`"><display-name>$name</display-name></channel><programme start=`"20300101000000 +0000`" stop=`"20300101010000 +0000`" channel=`"$name`"><title>$name</title></programme></tv>" }
            [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
            Add-ChannelForgeSourceSetSource -Kind $kind -Path $path -Label $name -RepositoryRoot $project | Out-Null
        }
        foreach ($p in $Playlist) { & $add $p 'M3U' }
        foreach ($g in $Bind.Keys) { & $add $g 'XMLTV'; Set-ChannelForgeSourceSetBinding -Label $g -Kind XMLTV -Playlist $Bind[$g] -RepositoryRoot $project | Out-Null }
        return $project
    }

    # Summary lines the way the build asks for them: scope from the project, then the scoped report.
    function Get-XgLines {
        param([object[]]$Programme, [string[]]$Guide, [string]$Project, [switch]$Plain)
        $now = [datetime]::Parse('2029-12-31T00:00:00Z').ToUniversalTime()
        $result = & (Get-Module ChannelForge) {
            param($prog, $now, $guide, $project, $plain)
            if ($plain) { $r = Get-ChannelForgeXguideReport -Programme $prog -BuildTimeUtc $now -GuideSourceId $guide }
            else {
                $scope = Get-ChannelForgeXguideScope -RepositoryRoot $project -GuideName $guide
                $args2 = @{ Programme = $prog; BuildTimeUtc = $now; GuideSourceId = $guide }
                if ($null -ne $scope) { $args2.GuideScope = $scope }
                $r = Get-ChannelForgeXguideScopedReport @args2
            }
            , @(Get-ChannelForgeXguideSummaryLines -Report $r)
        } $Programme $now $Guide $Project $Plain
        return ,@($result)
    }

    function New-XgDifferingGuides {
        @((New-XgProgramme 'guide-a' 'ch1' '20:00' 60 'Evening News'), (New-XgProgramme 'guide-b' 'ch1' '20:05' 55 'News Hour'))
    }

    function New-XgBuildRoot {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive $Name
        $data = Join-Path $root 'data'
        New-Item -ItemType Directory -Force -Path (Join-Path $data 'providers'), (Join-Path $data 'epg'), (Join-Path $data 'lineup'), (Join-Path $data 'rules'), (Join-Path $data 'playlists') | Out-Null
        [IO.File]::WriteAllText((Join-Path $data 'playlists\playlist.m3u'), "#EXTM3U`n#EXTINF:-1 tvg-id=`"wwe.us`" tvg-name=`"WWE`" group-title=`"Sports`",WWE Network`nhttps://example.invalid/live/wwe`n", [System.Text.UTF8Encoding]::new($false))
        foreach ($g in @(@('a.xml', '20300101200000', 'Evening News'), @('b.xml', '20300101200500', 'News Hour'))) {
            [IO.File]::WriteAllText((Join-Path $data "epg\$($g[0])"), "<tv><channel id=`"wwe.us`"><display-name>WWE</display-name></channel><programme start=`"$($g[1]) +0000`" stop=`"20300101210000 +0000`" channel=`"wwe.us`"><title>$($g[2])</title></programme></tv>")
        }
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
        param([Parameter(Mandatory)][string]$Root)
        $out = @(& pwsh -NoProfile -File $script:BuildPath -Root $Root 3>&1 *>&1 | ForEach-Object { [string]$_ })
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        [pscustomobject]@{
            Hash     = [string]$summary.CandidateManifestHash
            Markdown = @(Get-Content -LiteralPath (Join-Path $Root 'output\reports\lineup-plan.md'))
            Warnings = @($out | Where-Object { $_ -like '*WARNING:*' })
        }
    }
}

Describe 'Guide comparison scoped to playlists' {
    It 'does not compare two guides bound to different playlists' {
        $project = New-XgProject -Playlist 'alpha', 'beta' -Bind @{ 'guide-a' = 'alpha'; 'guide-b' = 'beta' }
        (Get-XgLines -Programme (New-XgDifferingGuides) -Guide 'guide-a', 'guide-b' -Project $project).Count | Should -Be 0
    }

    It 'still compares two guides bound to the same playlist, and names it' {
        $project = New-XgProject -Playlist 'alpha', 'beta' -Bind @{ 'guide-a' = 'alpha'; 'guide-b' = 'alpha'; 'guide-c' = 'beta' }
        $programmes = @(New-XgDifferingGuides) + @(New-XgProgramme 'guide-c' 'ch1' '20:00' 60 'Cooking')
        $lines = Get-XgLines -Programme $programmes -Guide 'guide-a', 'guide-b', 'guide-c' -Project $project
        $lines | Should -Contain '- channel ch1: 2030-01-01 20:00 is "Evening News" in guide-a, "News Hour" in guide-b (playlist alpha)'
        ($lines -join "`n") | Should -Not -BeLike '*guide-c*'
    }

    It 'gives the same lines as before when no saved source set matches the guide names' {
        $plain = Get-XgLines -Programme (New-XgDifferingGuides) -Guide 'guide-a', 'guide-b' -Project $TestDrive -Plain
        $plain.Count | Should -BeGreaterThan 2
        (Get-XgLines -Programme (New-XgDifferingGuides) -Guide 'guide-a', 'guide-b' -Project (Join-Path $TestDrive 'nothing-saved')) | Should -Be $plain
        $project = New-XgProject -Playlist 'alpha', 'beta' -Bind @{ 'guide-a' = 'alpha'; 'other' = 'beta' }
        (Get-XgLines -Programme (New-XgDifferingGuides) -Guide 'guide-a', 'guide-b' -Project $project) | Should -Be $plain
    }

    It 'gives the same lines as before when the saved set has one playlist' {
        $project = New-XgProject -Playlist 'alpha' -Bind @{ 'guide-a' = 'alpha'; 'guide-b' = 'alpha' }
        $plain = Get-XgLines -Programme (New-XgDifferingGuides) -Guide 'guide-a', 'guide-b' -Project $TestDrive -Plain
        (Get-XgLines -Programme (New-XgDifferingGuides) -Guide 'guide-a', 'guide-b' -Project $project) | Should -Be $plain
    }

    It 'leaves the candidate hash unchanged and drops the comparison when guides sit on different playlists' {
        $plainRoot = New-XgBuildRoot -Name 'plain'
        $scopedRoot = New-XgBuildRoot -Name 'scoped'
        $plain = Invoke-XgBuild -Root $plainRoot
        $files = Join-Path $TestDrive 'scoped-files'
        New-Item -ItemType Directory -Force -Path $files | Out-Null
        foreach ($name in 'alpha', 'beta') { [IO.File]::WriteAllText((Join-Path $files "$name.m3u"), "#EXTM3U`n#EXTINF:-1 tvg-id=`"$name`",$name`nhttps://example.invalid/$name`n"); Add-ChannelForgeSourceSetSource -Kind M3U -Path (Join-Path $files "$name.m3u") -Label $name -RepositoryRoot $scopedRoot | Out-Null }
        foreach ($pair in @(@('Guide A', 'alpha', 'a.xml'), @('Guide B', 'beta', 'b.xml'))) {
            Add-ChannelForgeSourceSetSource -Kind XMLTV -Path (Join-Path $scopedRoot "data\epg\$($pair[2])") -Label $pair[0] -RepositoryRoot $scopedRoot | Out-Null
            Set-ChannelForgeSourceSetBinding -Label $pair[0] -Kind XMLTV -Playlist $pair[1] -RepositoryRoot $scopedRoot | Out-Null
        }
        $scoped = Invoke-XgBuild -Root $scopedRoot
        ($plain.Markdown -join "`n") | Should -BeLike '*## Guide Comparison*'
        ($scoped.Markdown -join "`n") | Should -Not -BeLike '*## Guide Comparison*'
        $scoped.Hash | Should -Be $plain.Hash
        $scoped.Warnings.Count | Should -Be $plain.Warnings.Count
    }
}
