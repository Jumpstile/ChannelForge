BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    $script:FixtureDir = Join-Path $RepoRoot 'tests\fixtures\lineup'
    $script:AliasPath = Join-Path $script:FixtureDir 'aliases.json'
    $script:NumberingBlocksPath = Join-Path $script:FixtureDir 'numbering_blocks.json'
    $script:Source = @(
        [pscustomobject]@{ Path = Join-Path $script:FixtureDir 'sources-a.m3u'; Provider = 'fixture'; Playlist = 'a' }
        [pscustomobject]@{ Path = Join-Path $script:FixtureDir 'sources-b.m3u'; Provider = 'fixture'; Playlist = 'b' }
    )

    function Get-TestMerge {
        param([object[]]$UserNumber = @())
        Merge-ChannelForgeLineup -Source $script:Source -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath -UserNumber $UserNumber
    }

    function New-TestNumber {
        param([string]$Key, $Number)
        [pscustomobject]@{ channelKey = $Key; number = $Number }
    }

    function Write-TestDecisionsFile {
        param([string]$Name, [string]$Json)
        $path = Join-Path $TestDrive "$Name.json"
        Set-Content -LiteralPath $path -Value $Json -Encoding utf8
        return $path
    }

    $script:KeyA = ('a' * 64)
}

Describe 'Saved channel numbers in the lineup' {
    It 'writes the saved number to tvg-chno, beats the block number, and moves the displaced channel' {
        $baseline = Get-TestMerge
        $holder = @($baseline.Channels | Where-Object AssignedNumber -eq 700)[0]
        $result = Get-TestMerge -UserNumber @(New-TestNumber 'id:espn.us' 700)

        $out = Join-Path $TestDrive 'merged.m3u'
        $result.Channels | Export-ChannelForgeM3UPlaylist -Path $out -AllowedRoot $TestDrive
        $espnLine = @(Get-Content -LiteralPath $out | Where-Object { $_ -like '*tvg-id="espn.us"*' })[0]
        $espnLine | Should -Match 'tvg-chno="700"'

        $moved = @($result.Channels | Where-Object TvgId -eq $holder.TvgId)[0]
        $moved.AssignedNumber | Should -BeGreaterThan 700
        $moved.AssignedNumber | Should -BeLessOrEqual 705
        $numbers = @($result.Channels | Where-Object { $null -ne $_.AssignedNumber } | ForEach-Object AssignedNumber)
        @($numbers | Select-Object -Unique).Count | Should -Be $numbers.Count
    }

    It 'leaves the displaced channel unnumbered, with the block-full warning, when its block has no free number' {
        $result = Get-TestMerge -UserNumber @(New-TestNumber 'id:wcbs.us' 400)
        $espn = @($result.Channels | Where-Object TvgId -eq 'espn.us')[0]

        ($result.Channels | Where-Object TvgId -eq 'wcbs.us').AssignedNumber | Should -Be 400
        $espn.AssignedNumber | Should -BeNullOrEmpty
        $espn.Warnings | Should -Contain "Numbering block 'Sports' (400-401) is full; channel left unassigned."
    }

    It 'marks both channels review-needed and picks neither when two saved numbers are equal' {
        $baseline = Get-TestMerge
        $result = Get-TestMerge -UserNumber @((New-TestNumber 'id:espn.us' 700), (New-TestNumber 'id:fs1.us' 700))

        @($result.NumberReview.Collisions).Count | Should -Be 1
        $result.NumberReview.Collisions[0] | Should -Match 'channel number 700 is saved for'
        foreach ($id in 'espn.us', 'fs1.us') {
            $after = @($result.Channels | Where-Object TvgId -eq $id)[0]
            $before = @($baseline.Channels | Where-Object TvgId -eq $id)[0]
            $after.AssignedNumber | Should -Be $before.AssignedNumber
            @($after.Warnings | Where-Object { $_ -like 'Review needed:*' }).Count | Should -Be 1
        }
    }
}

Describe 'channel-decisions.json versions' {
    It 'still reads a v1 file, and its guide choices are unchanged' {
        $path = Write-TestDecisionsFile -Name 'v1' -Json ('[{"key":"' + $script:KeyA + '","name":"One","choice":"KeepWithoutGuide","decidedAt":"2026-11-12T20:00:00Z"}]')
        $choices = @(& (Get-Module ChannelForge) { param($p) Read-ChannelForgeChannelDecisions -Path $p } $path)
        $numbers = @(& (Get-Module ChannelForge) { param($p) Read-ChannelForgeChannelDecisions -Path $p -Section ChannelNumbers } $path)

        $choices.Count | Should -Be 1
        $choices[0].choice | Should -Be 'KeepWithoutGuide'
        $numbers.Count | Should -Be 0
    }

    It 'reads guide choices and numbers from a v2 file' {
        $path = Write-TestDecisionsFile -Name 'v2' -Json ('{"schemaVersion":"channel-decisions/v2","guideChoices":[{"key":"' + $script:KeyA + '","name":"One","choice":"OwnPlaceholder","decidedAt":""}],"channelNumbers":[{"channelKey":"id:espn.us","number":206,"decidedAt":""}]}')
        $choices = @(& (Get-Module ChannelForge) { param($p) Read-ChannelForgeChannelDecisions -Path $p } $path)
        $numbers = @(& (Get-Module ChannelForge) { param($p) Read-ChannelForgeChannelDecisions -Path $p -Section ChannelNumbers } $path)

        $choices[0].choice | Should -Be 'OwnPlaceholder'
        $numbers[0].number | Should -Be 206
    }

    It 'stops on an unknown version' {
        $path = Write-TestDecisionsFile -Name 'v9' -Json '{"schemaVersion":"channel-decisions/v9","guideChoices":[],"channelNumbers":[]}'
        { & (Get-Module ChannelForge) { param($p) Read-ChannelForgeChannelDecisions -Path $p } $path } | Should -Throw '*unknown version*Nothing was published*'
    }

    It 'rejects a saved number that is not a whole number from 1 to 9999' {
        foreach ($bad in '0', '10000', '2.5', '"7"', 'true') {
            $path = Write-TestDecisionsFile -Name 'bad' -Json ('{"schemaVersion":"channel-decisions/v2","guideChoices":[],"channelNumbers":[{"channelKey":"id:x","number":' + $bad + '}]}')
            { & (Get-Module ChannelForge) { param($p) Read-ChannelForgeChannelDecisions -Path $p -Section ChannelNumbers } $path } | Should -Throw '*not a whole number from 1 to 9999*'
        }
    }
}

Describe 'Set-ChannelForgeUserChannelNumber' {
    It 'rejects a number outside 1-9999 or not a whole number, with a plain message, and writes nothing' {
        foreach ($bad in 0, 10000, -3, 2.5, 'abc') {
            { Set-ChannelForgeUserChannelNumber -Root $TestDrive -TvgId 'espn.us' -Number $bad } | Should -Throw '*whole number from 1 to 9999*'
        }
        Test-Path -LiteralPath (Join-Path $TestDrive 'state\channel-decisions.json') | Should -BeFalse
    }

    It 'saves a number into a v1 file as v2, keeps the guide choices, and keeps the number when guide choices are saved again' {
        $root = Join-Path $TestDrive 'save-root'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'state') | Out-Null
        $file = Join-Path $root 'state\channel-decisions.json'
        Set-Content -LiteralPath $file -Encoding utf8 -Value ('[{"key":"' + $script:KeyA + '","name":"One","choice":"KeepWithoutGuide","decidedAt":"2026-11-12T20:00:00Z"}]')

        Set-ChannelForgeUserChannelNumber -Root $root -TvgId 'ESPN.us' -Number 206
        Set-ChannelForgeUserChannelNumber -Root $root -TvgId 'espn.us' -Number 207
        $saved = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        $saved.schemaVersion | Should -Be 'channel-decisions/v2'
        @($saved.guideChoices).Count | Should -Be 1
        @($saved.channelNumbers).Count | Should -Be 1
        $saved.channelNumbers[0].number | Should -Be 207

        # A later guide-choice save (what Build-My-Lineup does) must not drop the number.
        $records = @(& (Get-Module ChannelForge) { param($p) Read-ChannelForgeChannelDecisions -Path $p } $file)
        & (Get-Module ChannelForge) { param($p, $r) Write-ChannelForgeChannelDecisions -Path $p -Record $r } $file $records
        $again = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        $again.channelNumbers[0].number | Should -Be 207
    }
}

Describe 'Saved channel numbers on the source-set candidate path' {
    It 'writes the saved number to tvg-chno and, with none saved, builds the same playlist as with no decisions file' {
        $root = Join-Path $TestDrive 'ss'
        New-Item -ItemType Directory -Force "$root/data/rules", "$root/data/lineup", "$root/in", "$root/state" | Out-Null
        $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Copy-Item (Join-Path $repo 'data/rules/aliases.json') "$root/data/rules"
        Copy-Item (Join-Path $repo 'data/lineup/numbering_blocks.json') "$root/data/lineup"
        [IO.File]::WriteAllText("$root/in/alpha.m3u", "#EXTM3U`n#EXTINF:-1 tvg-id=`"alpha`",alpha`nhttps://example.invalid/alpha`n", [Text.UTF8Encoding]::new($false))
        $playlist = [pscustomobject]@{ SourceId = 'p-alpha'; SourceKey = 'p-alpha'; Label = 'alpha'; Priority = 1; Path = "$root/in/alpha.m3u" }
        $build = {
            $c = New-ChannelForgeSourceSetCandidateProposal -Root $root -PlaylistSources @($playlist) -OutputRoot (Join-Path $root ('out-' + [guid]::NewGuid().ToString('N'))) -WarningAction SilentlyContinue 3>$null
            [IO.File]::ReadAllText((Join-Path $c.CandidateDirectory 'merged.m3u'))
        }
        $plain = & $build
        '{"schemaVersion":"channel-decisions/v2","guideChoices":[],"channelNumbers":[]}' | Set-Content -LiteralPath "$root/state/channel-decisions.json" -Encoding utf8NoBOM
        (& $build) | Should -BeExactly $plain
        Set-ChannelForgeUserChannelNumber -Root $root -TvgId 'alpha' -Number 4242
        $withNumber = & $build
        $withNumber | Should -Match 'tvg-chno="4242"'
        $plain | Should -Not -Match 'tvg-chno="4242"'
        ($withNumber -replace ' tvg-chno="\d+"', '') | Should -BeExactly ($plain -replace ' tvg-chno="\d+"', '')
    }
}
