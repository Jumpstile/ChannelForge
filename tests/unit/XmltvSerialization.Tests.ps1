BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'
    $script:ExpectedPath = Join-Path $RepoRoot 'tests\fixtures\xmltv\expected-merged.xml'
    $script:sourceA = [pscustomobject]@{
        Name      = 'fixture'
        Path      = $script:FixturePath
        Url       = ''
        Format    = 'xmltv'
        Supported = $true
    }
    $script:programmesA = @(Import-ChannelForgeConfiguredXmltvSource -Source $script:sourceA)
    $script:singleSourceResult = Merge-ChannelForgeXmltvProgrammes -Programme $script:programmesA

    function Get-NormalizedXmlText {
        param([string]$Path)

        $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
        return [regex]::Replace($text, "\r\n?", [string][char]10)
    }

    function Export-TestXmltv {
        param(
            [object]$Result,
            [string]$Root,
            [string]$Name
        )

        $path = Join-Path $Root $Name
        Export-ChannelForgeXmltv -MergeResult $Result -Path $path -AllowedRoot $Root
        return $path
    }
}

Describe 'Export-ChannelForgeXmltv' {
    It 'matches the checked-in deterministic golden XMLTV output' {
        $outputPath = Export-TestXmltv -Result $script:singleSourceResult -Root $TestDrive -Name 'golden.xml'

        Get-NormalizedXmlText -Path $outputPath | Should -Be (Get-NormalizedXmlText -Path $script:ExpectedPath)
        $bytes = [System.IO.File]::ReadAllBytes($outputPath)
        $bytes[0] | Should -Be ([byte][char]'<')
        $bytes[0] | Should -Not -Be 0xEF
    }

    It 'produces identical bytes for repeated exports and input permutations' {
        $sourceB = [pscustomobject]@{
            Name      = 'second-source'
            Path      = $script:FixturePath
            Url       = ''
            Format    = 'xmltv'
            Supported = $true
        }
        $programmesB = @(Import-ChannelForgeConfiguredXmltvSource -Source $sourceB)
        $forward = Merge-ChannelForgeXmltvProgrammes -Programme @($script:programmesA + $programmesB)
        $reverse = Merge-ChannelForgeXmltvProgrammes -Programme @($programmesB + $script:programmesA)

        $firstPath = Export-TestXmltv -Result $forward -Root $TestDrive -Name 'first.xml'
        $secondPath = Export-TestXmltv -Result $reverse -Root $TestDrive -Name 'second.xml'

        (Get-FileHash -LiteralPath $firstPath -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $secondPath -Algorithm SHA256).Hash
    }

    It 'emits valid XML with stable source-scoped ordering and UTC timestamps' {
        $sourceB = [pscustomobject]@{
            Name      = 'second-source'
            Path      = $script:FixturePath
            Url       = ''
            Format    = 'xmltv'
            Supported = $true
        }
        $programmesB = @(Import-ChannelForgeConfiguredXmltvSource -Source $sourceB)
        $result = Merge-ChannelForgeXmltvProgrammes -Programme @($programmesB + $script:programmesA)
        $outputPath = Export-TestXmltv -Result $result -Root $TestDrive -Name 'ordered.xml'

        $xml = [System.Xml.XmlDocument]::new()
        $xml.XmlResolver = $null
        $xml.Load($outputPath)

        $channelIds = @($xml.SelectNodes('/tv/channel') | ForEach-Object { $_.GetAttribute('id') })
        $channelIds | Should -Be @(
            '13:second-source|7:news.us'
            '13:second-source|9:sports.us'
            '7:fixture|7:news.us'
            '7:fixture|9:sports.us'
        )
        @($xml.SelectNodes('/tv/programme') | ForEach-Object { $_.GetAttribute('channel') }) | Should -Be @(
            '13:second-source|7:news.us'
            '13:second-source|9:sports.us'
            '7:fixture|7:news.us'
            '7:fixture|9:sports.us'
        )
        @($xml.SelectNodes('/tv/programme') | ForEach-Object { $_.GetAttribute('start') }) | Should -Be @(
            '20260815090000 +0000'
            '20260815120000 +0000'
            '20260815090000 +0000'
            '20260815120000 +0000'
        )
    }

    It 'escapes XML text and preserves only safe provenance fields' {
        $evidence = [pscustomobject]@{
            SourceId   = 'safe-source'
            SourcePath = 'C:\private\secret\guide.xml'
            Url        = 'https://example.invalid/REDACTED'
            Password   = 'secret'
        }
        $programme = New-ChannelForgeProgramme -ChannelId 'channel<&' -Start ([datetimeoffset]::new(2026, 8, 15, 9, 0, 0, [timespan]::Zero)) -End ([datetimeoffset]::new(2026, 8, 15, 10, 0, 0, [timespan]::Zero)) -Title 'A & <B> "C"' -Subtitle 'Sub > title' -Description 'Description & details' -Categories @('Z &', 'A <') -EpisodeNumber 'S01&E01' -SourceId 'safe-source' -Evidence $evidence

        $result = Merge-ChannelForgeXmltvProgrammes -Programme $programme
        $outputPath = Export-TestXmltv -Result $result -Root $TestDrive -Name 'escaped.xml'
        $text = Get-NormalizedXmlText -Path $outputPath

        $text | Should -Match '&amp;'
        $text | Should -Match '&lt;'
        $text | Should -Not -Match 'private'
        $text | Should -Not -Match 'password'
        $text | Should -Not -Match 'https://'
        $xml = [System.Xml.XmlDocument]::new()
        $xml.XmlResolver = $null
        $xml.Load($outputPath)
        $xml.SelectSingleNode('/tv/programme/title').InnerText | Should -Be 'A & <B> "C"'
    }

    It 'rejects path and URL source IDs before writing output' {
        $unsafeSourceIds = @(
            'C:\private\secret\guide.xml'
            'https://example.invalid/REDACTED'
        )

        for ($i = 0; $i -lt $unsafeSourceIds.Count; $i++) {
            $programme = New-ChannelForgeProgramme -ChannelId 'news.us' -Start ([datetimeoffset]::new(2026, 8, 15, 9, 0, 0, [timespan]::Zero)) -End ([datetimeoffset]::new(2026, 8, 15, 10, 0, 0, [timespan]::Zero)) -Title 'Unsafe source' -SourceId $unsafeSourceIds[$i]
            $result = Merge-ChannelForgeXmltvProgrammes -Programme $programme
            $outputPath = Join-Path $TestDrive ("unsafe-$i.xml")

            { Export-ChannelForgeXmltv -MergeResult $result -Path $outputPath -AllowedRoot $TestDrive } | Should -Throw '*cannot contain*'
            Test-Path -LiteralPath $outputPath | Should -BeFalse
        }
    }

    It 'rejects conflicts and NeedsReview records before creating output' {
        $original = $script:programmesA[0]
        $conflicting = New-ChannelForgeProgramme -ChannelId $original.ChannelId -Start $original.Start -End $original.End -Title 'Different title' -SourceId $original.SourceId -Evidence $original.Evidence
        $conflictResult = Merge-ChannelForgeXmltvProgrammes -Programme @($original, $conflicting)
        $conflictPath = Join-Path $TestDrive 'conflict.xml'

        { Export-ChannelForgeXmltv -MergeResult $conflictResult -Path $conflictPath -AllowedRoot $TestDrive } | Should -Throw '*conflict*'
        Test-Path -LiteralPath $conflictPath | Should -BeFalse

        $needsReviewResult = Merge-ChannelForgeXmltvProgrammes -Programme $script:programmesA
        $needsReviewResult.BoundProgrammes[0].Status = 'NeedsReview'
        $needsReviewPath = Join-Path $TestDrive 'needs-review.xml'
        { Export-ChannelForgeXmltv -MergeResult $needsReviewResult -Path $needsReviewPath -AllowedRoot $TestDrive } | Should -Throw '*NeedsReview*'
        Test-Path -LiteralPath $needsReviewPath | Should -BeFalse
    }

    It 'rejects missing required fields and inconsistent binding identity' {
        $invalidProgramme = New-ChannelForgeProgramme -ChannelId $script:programmesA[0].ChannelId -Start $script:programmesA[0].Start -End $script:programmesA[0].End -Title $script:programmesA[0].Title -SourceId $script:programmesA[0].SourceId -Evidence $script:programmesA[0].Evidence
        $invalidProgramme.Title = ''
        $invalidResult = Merge-ChannelForgeXmltvProgrammes -Programme $invalidProgramme
        $invalidPath = Join-Path $TestDrive 'invalid.xml'

        { Export-ChannelForgeXmltv -MergeResult $invalidResult -Path $invalidPath -AllowedRoot $TestDrive } | Should -Throw '*title*'
        Test-Path -LiteralPath $invalidPath | Should -BeFalse

        $invalidInterval = New-ChannelForgeProgramme -ChannelId 'news.us' -Start ([datetimeoffset]::new(2026, 8, 15, 9, 0, 0, [timespan]::Zero)) -End ([datetimeoffset]::new(2026, 8, 15, 10, 0, 0, [timespan]::Zero)) -Title 'Invalid interval' -SourceId 'fixture'
        $invalidIntervalResult = Merge-ChannelForgeXmltvProgrammes -Programme $invalidInterval
        $invalidIntervalResult.BoundProgrammes[0].Programme.End = [datetimeoffset]::new(2026, 8, 15, 8, 0, 0, [timespan]::Zero)
        $invalidIntervalPath = Join-Path $TestDrive 'invalid-interval.xml'
        { Export-ChannelForgeXmltv -MergeResult $invalidIntervalResult -Path $invalidIntervalPath -AllowedRoot $TestDrive } | Should -Throw '*interval*'
        Test-Path -LiteralPath $invalidIntervalPath | Should -BeFalse

        $missingStart = New-ChannelForgeProgramme -ChannelId 'news.us' -Start ([datetimeoffset]::MinValue) -End ([datetimeoffset]::new(2026, 8, 15, 10, 0, 0, [timespan]::Zero)) -Title 'Missing start' -SourceId 'fixture'
        $missingStartResult = Merge-ChannelForgeXmltvProgrammes -Programme $missingStart
        $missingStartPath = Join-Path $TestDrive 'missing-start.xml'
        { Export-ChannelForgeXmltv -MergeResult $missingStartResult -Path $missingStartPath -AllowedRoot $TestDrive } | Should -Throw '*start and end*'
        Test-Path -LiteralPath $missingStartPath | Should -BeFalse

        $bindingResult = Merge-ChannelForgeXmltvProgrammes -Programme $script:programmesA
        $bindingResult.Bindings[0].BindingKey = 'tampered'
        $bindingPath = Join-Path $TestDrive 'binding.xml'
        { Export-ChannelForgeXmltv -MergeResult $bindingResult -Path $bindingPath -AllowedRoot $TestDrive } | Should -Throw '*BindingKey*'
        Test-Path -LiteralPath $bindingPath | Should -BeFalse
    }

    It 'rejects output outside the allowed root and does not create parent directories' {
        $allowedRoot = Join-Path $TestDrive 'allowed'
        New-Item -ItemType Directory -Path $allowedRoot -Force | Out-Null
        $outsidePath = Join-Path $TestDrive 'outside.xml'
        { Export-ChannelForgeXmltv -MergeResult $script:singleSourceResult -Path $outsidePath -AllowedRoot $allowedRoot } | Should -Throw '*approved*'
        Test-Path -LiteralPath $outsidePath | Should -BeFalse

        $missingParent = Join-Path $allowedRoot 'missing\output.xml'
        { Export-ChannelForgeXmltv -MergeResult $script:singleSourceResult -Path $missingParent -AllowedRoot $allowedRoot } | Should -Throw '*parent directory*'
        Test-Path -LiteralPath (Split-Path -Parent $missingParent) | Should -BeFalse
    }
}
