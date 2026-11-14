BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    $script:GuideFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\guide.xml'
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function New-EventChannel {
        param([string]$Name, [string[]]$Titles = @(), [int]$Hours = 4, [string]$Category = $null)
        $start = [datetimeoffset]'2026-11-14T00:00:00Z'
        $programmes = for ($i = 0; $i -lt $Titles.Count; $i++) {
            [pscustomobject]@{ Title = $Titles[$i]; Start = $start.AddHours($i * $Hours); Stop = $start.AddHours(($i + 1) * $Hours) }
        }
        [pscustomobject]@{ Key = ('{0:x64}' -f $Name.Length); DisplayName = $Name; GroupTitle = 'Test'; Category = $Category; Programmes = @($programmes) }
    }
    function Get-Rated {
        param([object[]]$Channel)
        InModuleScope ChannelForge -Parameters @{ Channel = $Channel } { @(Get-ChannelForgeEventChannelCandidate -Channel $Channel) }
    }
}

Describe 'Event channel candidates' {
    It 'rates every PPV name high, and medium only with several different real programmes' {
        $rated = Get-Rated -Channel @(
            (New-EventChannel -Name 'PPV 1' -Titles @('No Event', 'No Event'))
            (New-EventChannel -Name 'Pay-Per-View 2')
            (New-EventChannel -Name 'Sport PPV 3' -Titles @('News', 'Match A', 'Match B', 'Match C'))
        )
        ($rated | Where-Object DisplayName -ceq 'PPV 1').Confidence | Should -Be 'high'
        ($rated | Where-Object DisplayName -ceq 'Pay-Per-View 2').Confidence | Should -Be 'high'
        ($rated | Where-Object DisplayName -ceq 'Sport PPV 3').Confidence | Should -Be 'medium'
    }

    It 'rates an event-word channel high when over half its guide time is placeholder, medium when it has real programmes' {
        $rated = Get-Rated -Channel @(
            (New-EventChannel -Name 'Fight Night 4' -Titles @('Fight Night 4', 'Fight Night 4', 'Weigh-in'))
            (New-EventChannel -Name 'Fight Network' -Titles @('Bout A', 'Bout B', 'Bout C'))
            (New-EventChannel -Name 'UFC Extra')
        )
        ($rated | Where-Object DisplayName -ceq 'Fight Night 4').Confidence | Should -Be 'high'
        ($rated | Where-Object DisplayName -ceq 'Fight Network').Confidence | Should -Be 'medium'
        $none = $rated | Where-Object DisplayName -ceq 'UFC Extra'
        $none.Confidence | Should -Be 'medium'
        $none.Reasons | Should -Contain 'no guide data'
    }

    It 'rates PPV1 style names high' {
        $rated = Get-Rated -Channel @((New-EventChannel -Name 'Prima Sport PPV1' -Titles @('Prima Sport PPV1')))
        $rated[0].Confidence | Should -Be 'high'
    }

    It 'counts a title that echoes the channel name with a suffix as placeholder' {
        $rated = Get-Rated -Channel @(
            (New-EventChannel -Name 'blue Event D 1' -Titles @('blue Event D 1 Live', 'blue Event D 1 Live'))
            (New-EventChannel -Name 'Fight Network' -Titles @('Bout A', 'Bout B', 'Bout C'))
        )
        ($rated | Where-Object DisplayName -ceq 'blue Event D 1').Confidence | Should -Be 'high'
        ($rated | Where-Object DisplayName -ceq 'Fight Network').Confidence | Should -Be 'medium'
    }

    It 'does not flag a normal channel full of filler, and reports nothing for a normal channel' {
        $rated = Get-Rated -Channel @(
            (New-EventChannel -Name 'City News' -Titles @('Off Air', 'SIGN OFF', 'To Be Announced'))
            (New-EventChannel -Name 'Movie Max' -Titles @('Film A', 'Film B'))
        )
        $rated.Count | Should -Be 0
    }
}

Describe 'Event channel summary lines' {
    It 'counts each level and caps the high list' {
        $rows = @(1..8 | ForEach-Object { [pscustomobject]@{ DisplayName = "PPV $_"; GroupTitle = 'G'; Confidence = 'high'; Reasons = @('r') } }) +
            [pscustomobject]@{ DisplayName = 'M'; GroupTitle = 'G'; Confidence = 'medium'; Reasons = @('r') }
        $lines = InModuleScope ChannelForge -Parameters @{ Rows = $rows } { @(Get-ChannelForgeEventChannelSummaryLines -Candidate $Rows) }
        $lines | Should -Contain '9 channels look like event channels: 8 high, 1 medium, 0 low. Nothing was changed.'
        @($lines | Where-Object { $_ -like '- PPV*' }).Count | Should -Be 5
        $lines | Should -Contain '- and 3 more'
    }
}

Describe 'Build summary event channel section' {
    It 'turns a failure inside the block into one warning and leaves the build and candidate hash alone' {
        function New-Root([string]$Name) {
            $root = Join-Path $TestDrive $Name
            $data = Join-Path $root 'data'
            New-Item -ItemType Directory -Force -Path (Join-Path $data 'providers'), (Join-Path $data 'epg'), (Join-Path $data 'lineup'), (Join-Path $data 'rules'), (Join-Path $data 'playlists') | Out-Null
            $playlist = @('#EXTM3U', '#EXTINF:-1 tvg-id="zeta.us" group-title="PPV",PPV 1', 'https://example.invalid/live/ppv1', '#EXTINF:-1 tvg-id="misc.us" group-title="Misc",Mystery Channel', 'https://example.invalid/live/misc')
            [IO.File]::WriteAllText((Join-Path $data 'playlists\playlist.m3u'), (($playlist -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
            Copy-Item -LiteralPath $script:GuideFixture -Destination (Join-Path $data 'epg\guide.xml')
            @{ provider = 'event-fixture'; sources = @(@{ name = 'Playlist'; group = 'General'; url = 'https://example.invalid/fixture'; enabled = $true; local_playlist = 'data/playlists/playlist.m3u' }) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'providers\mybunny.json') -Encoding UTF8
            @{ epg_sources = @(@{ name = 'Guide'; priority = 10; path = 'guide.xml'; enabled = $true; role = 'primary' }) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'epg\epg_sources.json') -Encoding UTF8
            @{ locals = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'lineup\locals.json') -Encoding UTF8
            @{ blocks = @(@{ start = 1; end = 9999; category = 'General'; notes = 'fixture' }) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'lineup\numbering_blocks.json') -Encoding UTF8
            @{ aliases = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'rules\aliases.json') -Encoding UTF8
            return $root
        }
        function Invoke-Build([string]$Root) {
            $warnings = @(& $script:BuildPath -Root $Root 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
            [pscustomobject]@{ Hash = [string]$summary.CandidateManifestHash; Markdown = (Get-Content -LiteralPath (Join-Path $Root 'output\reports\lineup-plan.md')) -join "`n"; Warnings = @($warnings | ForEach-Object { [string]$_.Message }) }
        }
        $good = Invoke-Build (New-Root 'good')
        $brokenRoot = New-Root 'broken'
        New-Item -ItemType Directory -Force -Path (Join-Path $brokenRoot 'state') | Out-Null
        [IO.File]::WriteAllText((Join-Path $brokenRoot 'state\category-overrides.json'), '{ not json')
        $bad = Invoke-Build $brokenRoot

        $good.Markdown | Should -BeLike '*## Event Channels*PPV 1 (group ''PPV'', high): name has "ppv"; 0% of guide time is placeholder titles*'
        @($good.Warnings | Where-Object { $_ -like '*event channel*' }).Count | Should -Be 0
        @($bad.Warnings | Where-Object { $_ -like '*event channel*' }).Count | Should -Be 1
        $bad.Markdown | Should -Not -BeLike '*## Event Channels*'
        $bad.Hash | Should -Be $good.Hash
    }
}
