BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    $script:FixtureDir = Join-Path $RepoRoot 'tests\fixtures\lineup'
    $script:AliasPath = Join-Path $script:FixtureDir 'aliases.json'
    $script:NumberingBlocksPath = Join-Path $script:FixtureDir 'numbering_blocks.json'

    $script:TwoFileSource = @(
        [pscustomobject]@{ Path = Join-Path $script:FixtureDir 'sources-a.m3u'; Provider = 'fixture'; Playlist = 'a' }
        [pscustomobject]@{ Path = Join-Path $script:FixtureDir 'sources-b.m3u'; Provider = 'fixture'; Playlist = 'b' }
    )

    $script:GoldenM3U = "#EXTM3U`n" +
        "#EXTINF:-1 tvg-id=`"wcbs.us`" tvg-name=`"WCBS`" tvg-chno=`"2`" group-title=`"Locals`",WCBS CBS New York`n" +
        "https://example.invalid/live/wcbs`n" +
        "#EXTINF:-1 tvg-id=`"espn.us`" tvg-name=`"ESPN`" tvg-logo=`"https://example.invalid/logos/espn.png`" tvg-chno=`"400`" group-title=`"Sports`",ESPN`n" +
        "https://example.invalid/live/espn`n" +
        "#EXTINF:-1 tvg-id=`"fs1.us`" tvg-name=`"FS1`" tvg-logo=`"https://example.invalid/logos/fs1.png`" tvg-chno=`"401`" group-title=`"Sports`",FS1`n" +
        "https://example.invalid/live/fs1`n" +
        "#EXTINF:-1 tvg-id=`"cnn.us`" tvg-name=`"CNN`" tvg-chno=`"700`" group-title=`"News`",CNN`n" +
        "https://example.invalid/live/cnn`n" +
        "#EXTINF:-1 tvg-id=`"msnbc.us`" tvg-name=`"MSNBC`" tvg-chno=`"701`" group-title=`"News`",MSNBC`n" +
        "https://example.invalid/live/msnbc`n" +
        "#EXTINF:-1 tvg-id=`"overflow.us`" tvg-name=`"Overflow`" group-title=`"Unmatched Group`",Unmatched Channel`n" +
        "https://example.invalid/live/overflow`n"
}

Describe 'Merge-ChannelForgeLineup' {
    It 'normalizes, resolves aliases, deduplicates, and numbers channels deterministically' {
        $result = Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath

        $result.Channels.Count | Should -Be 6
        $result.DuplicateCount | Should -Be 0

        ($result.Channels | Where-Object TvgId -eq 'fs1.us').DisplayName | Should -Be 'FS1'
        ($result.Channels | Where-Object TvgId -eq 'espn.us').AssignedNumber | Should -Be 400
        ($result.Channels | Where-Object TvgId -eq 'wcbs.us').AssignedNumber | Should -Be 2
    }

    It 'leaves a channel with no matching numbering block unassigned and warns instead of guessing' {
        $result = Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath
        $unmatched = $result.Channels | Where-Object TvgId -eq 'overflow.us'

        $unmatched.AssignedNumber | Should -BeNullOrEmpty
        $unmatched.Warnings | Should -Contain "No numbering block matched group 'Unmatched Group'."
        $result.WarningCount | Should -BeGreaterOrEqual 1
    }

    It 'sorts numbered channels by channel number, then unassigned channels by name' {
        $result = Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath
        $orderedNumbers = @($result.Channels | Where-Object { $null -ne $_.AssignedNumber } | Select-Object -ExpandProperty AssignedNumber)

        $orderedNumbers | Should -Be ($orderedNumbers | Sort-Object)
        $result.Channels[-1].TvgId | Should -Be 'overflow.us'
    }

    It 'sorts source files by path before parsing, so caller-supplied order does not matter' {
        $reversed = @($script:TwoFileSource[1], $script:TwoFileSource[0])

        $forward = Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath
        $backward = Merge-ChannelForgeLineup -Source $reversed -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath

        @($forward.Channels.DisplayName) | Should -Be @($backward.Channels.DisplayName)
    }

    It 'deduplicates a channel that appears under the same tvg-id from a second playlist' {
        $sourceWithDuplicate = $script:TwoFileSource + [pscustomobject]@{
            Path     = Join-Path $script:FixtureDir 'sources-dup.m3u'
            Provider = 'fixture'
            Playlist = 'dup'
        }

        $result = Merge-ChannelForgeLineup -Source $sourceWithDuplicate -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath

        $result.Channels.Count | Should -Be 6
        $result.DuplicateCount | Should -Be 1
        $result.Duplicates[0].TvgId | Should -Be 'espn.us'
        $result.Duplicates[0].IsDuplicate | Should -BeTrue

        # The first occurrence (from sources-a.m3u, sorted before sources-dup.m3u
        # by path) survives with its own stream URL, not the duplicate's.
        $survivor = $result.Channels | Where-Object TvgId -eq 'espn.us'
        $survivor.Url | Should -Be 'https://example.invalid/live/espn'
    }

    It 'produces byte-identical results across repeated runs with the same inputs' {
        $first = Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath
        $second = Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath

        $firstPath = Join-Path $TestDrive 'first.m3u'
        $secondPath = Join-Path $TestDrive 'second.m3u'
        $first.Channels | Export-ChannelForgeM3UPlaylist -Path $firstPath
        $second.Channels | Export-ChannelForgeM3UPlaylist -Path $secondPath

        (Get-FileHash -LiteralPath $firstPath -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $secondPath -Algorithm SHA256).Hash
    }

    It 'throws when a playlist file is missing' {
        $badSource = @([pscustomobject]@{ Path = Join-Path $script:FixtureDir 'does-not-exist.m3u'; Provider = 'fixture'; Playlist = 'missing' })

        { Merge-ChannelForgeLineup -Source $badSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath } | Should -Throw
    }

    It 'throws when the numbering blocks file is missing' {
        { Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath (Join-Path $script:FixtureDir 'does-not-exist.json') } | Should -Throw
    }
}

Describe 'Export-ChannelForgeM3UPlaylist' {
    It 'renders an exact, golden merged M3U from the fixture lineup' {
        $result = Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath
        $outPath = Join-Path $TestDrive 'merged.m3u'

        $result.Channels | Export-ChannelForgeM3UPlaylist -Path $outPath

        (Get-Content -LiteralPath $outPath -Raw) | Should -Be $script:GoldenM3U
    }

    It 'writes plain UTF-8 with no BOM' {
        $result = Merge-ChannelForgeLineup -Source $script:TwoFileSource -AliasPath $script:AliasPath -NumberingBlocksPath $script:NumberingBlocksPath
        $outPath = Join-Path $TestDrive 'merged-encoding.m3u'

        $result.Channels | Export-ChannelForgeM3UPlaylist -Path $outPath

        $bytes = [System.IO.File]::ReadAllBytes($outPath)
        $bytes[0] | Should -Be ([byte][char]'#')
    }

    It 'sanitizes an embedded double quote in attribute text so the line stays parseable' {
        $channel = New-ChannelForgeChannel -OriginalName 'Test' -DisplayName 'Test' -TvgName 'Channel "Quoted" Name' -Url 'https://example.invalid/live/test'
        $outPath = Join-Path $TestDrive 'quote.m3u'

        @($channel) | Export-ChannelForgeM3UPlaylist -Path $outPath
        $lines = Get-Content -LiteralPath $outPath

        $lines.Count | Should -Be 3
        $lines[1] | Should -Match "tvg-name=`"Channel 'Quoted' Name`""
        $lines[1] | Should -Not -Match '\\"'
    }

    It 'sanitizes an embedded newline in the display name so it cannot inject a fake extra line' {
        $maliciousName = "Innocent Channel`n#EXTINF:-1,Injected Channel`nhttps://example.invalid/live/injected"
        $channel = New-ChannelForgeChannel -OriginalName 'Test' -DisplayName $maliciousName -Url 'https://example.invalid/live/test'
        $outPath = Join-Path $TestDrive 'newline.m3u'

        @($channel) | Export-ChannelForgeM3UPlaylist -Path $outPath
        $lines = Get-Content -LiteralPath $outPath

        # Exactly 3 lines: header, one #EXTINF, one stream URL. A successful
        # injection would add extra lines that look like another channel.
        $lines.Count | Should -Be 3
        $lines[1] | Should -Match 'Injected Channel'
        ($lines | Where-Object { $_ -like '#EXTINF*' }).Count | Should -Be 1
    }

    It 'sanitizes an embedded CRLF in a quoted attribute the same way' {
        $channel = New-ChannelForgeChannel -OriginalName 'Test' -DisplayName 'Test' -TvgId "abc`r`ndef" -Url 'https://example.invalid/live/test'
        $outPath = Join-Path $TestDrive 'crlf.m3u'

        @($channel) | Export-ChannelForgeM3UPlaylist -Path $outPath
        $lines = Get-Content -LiteralPath $outPath

        $lines.Count | Should -Be 3
        $lines[1] | Should -Match 'tvg-id="abc def"'
    }

    It 'leaves ordinary commas in a display name untouched (M3U does not require escaping them)' {
        $channel = New-ChannelForgeChannel -OriginalName 'Test' -DisplayName 'Channel, The Sequel' -Url 'https://example.invalid/live/test'
        $outPath = Join-Path $TestDrive 'comma.m3u'

        @($channel) | Export-ChannelForgeM3UPlaylist -Path $outPath
        $lines = Get-Content -LiteralPath $outPath

        $lines[1] | Should -Match ',Channel, The Sequel$'
    }
}

Describe 'Set-ChannelForgeChannelNumber' {
    It 'leaves overflow channels in a full block unassigned with a warning instead of spilling into the next block' {
        $channelA = New-ChannelForgeChannel -OriginalName 'Channel A' -Group 'Sports'
        $channelB = New-ChannelForgeChannel -OriginalName 'Channel B' -Group 'Sports'
        $blocks = @([pscustomobject]@{ start = 400; end = 400; category = 'Sports' })

        Set-ChannelForgeChannelNumber -Channel @($channelA, $channelB) -NumberingBlock $blocks | Out-Null

        $assigned = @($channelA, $channelB) | Where-Object { $null -ne $_.AssignedNumber }
        $unassigned = @($channelA, $channelB) | Where-Object { $null -eq $_.AssignedNumber }

        $assigned.Count | Should -Be 1
        $unassigned.Count | Should -Be 1
        $unassigned[0].Warnings | Should -Contain "Numbering block 'Sports' (400-400) is full; channel left unassigned."
    }
}
