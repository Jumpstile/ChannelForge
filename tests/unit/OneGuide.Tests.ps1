BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    $script:SchemaPath = Join-Path $script:RepoRoot 'schemas\one-guide-projection.schema.json'
    Import-Module $script:ModulePath -Force


    $script:FixturePath = Join-Path $script:RepoRoot 'tests\fixtures\one-guide\programmes.json'

    function Get-OneGuideFixtureProgrammes {
        $rows = Get-Content -LiteralPath $script:FixturePath -Raw | ConvertFrom-Json -DateKind String
        return @(
            foreach ($row in $rows) {
                $start = [datetimeoffset]::Parse([string]$row.Start, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
                $end = [datetimeoffset]::Parse([string]$row.End, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
                $programme = New-OneGuideTestProgramme -ChannelId $row.ChannelId -Start $start -End $end -Title $row.Title -Categories $row.Categories -SourceId $row.SourceId
                foreach ($name in @('SourceLabel', 'Sport', 'League', 'HomeParticipant', 'AwayParticipant', 'Promotion')) {
                    $property = $row.PSObject.Properties[$name]
                    if ($null -ne $property) { $programme | Add-Member -NotePropertyName $name -NotePropertyValue $property.Value }
                }
                $programme
            }
        )
    }
    function New-OneGuideTestProgramme {
        param(
            [Parameter(Mandatory)][string]$ChannelId,
            [Parameter(Mandatory)][datetimeoffset]$Start,
            [Parameter(Mandatory)][datetimeoffset]$End,
            [Parameter(Mandatory)][string]$Title,
            [string[]]$Categories = @(),
            [string]$SourceId = 'provider-a',
            [string]$Subtitle = '',
            [string]$Description = '',
            [string]$EpisodeNumber = ''
        )
        return New-ChannelForgeProgramme -ChannelId $ChannelId -Start $Start -End $End -Title $Title -Categories $Categories -SourceId $SourceId -Subtitle $Subtitle -Description $Description -EpisodeNumber $EpisodeNumber
    }
}

Describe 'One Guide read projection' {
    BeforeEach {
        $script:Evaluation = [datetimeoffset]::Parse('2026-10-01T12:00:00Z')
    }

    It 'uses half-open live intervals and an inclusive two-hour Starting Soon boundary' {
        $programmes = @(
            (New-OneGuideTestProgramme 'starts-now' $Evaluation ($Evaluation.AddHours(1)) 'Starts Now'),
            (New-OneGuideTestProgramme 'ends-now' ($Evaluation.AddHours(-1)) $Evaluation 'Ends Now'),
            (New-OneGuideTestProgramme 'starts-in-two-hours' ($Evaluation.AddHours(2)) ($Evaluation.AddHours(3)) 'Two Hours'),
            (New-OneGuideTestProgramme 'just-late' ($Evaluation.AddHours(2).AddSeconds(1)) ($Evaluation.AddHours(3)) 'Just Late')
        )

        $live = Get-ChannelForgeOneGuide -Query LiveNow -Programmes $programmes -EvaluationTimeUtc $Evaluation
        $soon = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes $programmes -EvaluationTimeUtc $Evaluation

        @($live.Items.Title) | Should -Be @('Starts Now')
        @($soon.Items.Title) | Should -Be @('Two Hours')
        $live.EvaluationTimeUtc | Should -Be $Evaluation.ToString('o')
    }

    It 'emits only the fixed taxonomy and keeps wrestling promotion structured' {
        $programmes = Get-OneGuideFixtureProgrammes
        $expectedTaxonomy = @('live-now', 'starting-soon', 'wrestling', 'football', 'baseball', 'soccer', 'movies', 'news')

        foreach ($key in $expectedTaxonomy) {
            $result = Get-ChannelForgeOneGuide -Query Category -CategoryKey $key -Programmes $programmes -EvaluationTimeUtc $Evaluation
            $result.Query | Should -Be 'Category'
            $result.CategoryKey | Should -Be $key
            $result.TotalCount | Should -BeGreaterThan 0
        }
        $items = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes $programmes -EvaluationTimeUtc $Evaluation
        $wrestling = Get-ChannelForgeOneGuide -Query Category -CategoryKey wrestling -Programmes $programmes -EvaluationTimeUtc $Evaluation
        $items.Items[0].Promotion | Should -BeNullOrEmpty
        $wrestling.Items[0].Promotion.Id | Should -Be 'wwe'
        $wrestling.Items[0].Promotion.Name | Should -Be 'WWE'
        @($wrestling.Items[0].CategoryKeys | Where-Object { $_ -notin $expectedTaxonomy }) | Should -BeNullOrEmpty
    }

    It 'groups one event across offerings despite classification disagreement with order-independent output' {
        $programmes = Get-OneGuideFixtureProgrammes
        $reversed = @($programmes)
        [array]::Reverse($reversed)
        $forward = Get-ChannelForgeOneGuide -Query Category -CategoryKey wrestling -Programmes $programmes -EvaluationTimeUtc $Evaluation
        $reverse = Get-ChannelForgeOneGuide -Query Category -CategoryKey wrestling -Programmes $reversed -EvaluationTimeUtc $Evaluation
        $item = $forward.Items[0]

        $item.ItemId | Should -Be $reverse.Items[0].ItemId
        ($forward | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($reverse | ConvertTo-Json -Depth 10 -Compress)
        $item.Offerings.Count | Should -Be 2
        $item.OfferingCount | Should -Be 2
        $item.OfferingsTruncated | Should -BeFalse
        $item.Kind | Should -Be 'Event'
        $item.CategoryKeys | Should -Contain 'wrestling'
        $item.Sport | Should -Be 'Wrestling'
        $item.League | Should -Be 'WWE'
        $item.Promotion.Id | Should -Be 'wwe'
        @($item.Offerings.Launch.ChannelReference | Sort-Object) | Should -Be @('channel-wwe-a', 'channel-wwe-b')
        @($item.Offerings.SourceId | Sort-Object) | Should -Be @('provider-a', 'provider-b')
        $item.ItemId | Should -Not -Be $item.Offerings[0].Launch.ChannelReference
    }

    It 'selects repeated-offering metadata deterministically when source rows disagree' {
        $first = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Football') 'provider-a' -EpisodeNumber 's01e01' -Description 'Zulu description'
        $second = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Football') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Alpha description'
        $first | Add-Member -NotePropertyName SourceLabel -NotePropertyValue 'Zulu Source'
        $second | Add-Member -NotePropertyName SourceLabel -NotePropertyValue 'Alpha Source'
        $forward = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($first, $second) -EvaluationTimeUtc $Evaluation
        $reverse = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($second, $first) -EvaluationTimeUtc $Evaluation

        ($forward | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($reverse | ConvertTo-Json -Depth 10 -Compress)
        $forward.Items[0].Description | Should -Be 'Alpha description'
        $forward.Items[0].EpisodeNumber | Should -Be 'S01E01'
        $forward.Items[0].Offerings.Count | Should -Be 1
        $forward.Items[0].Offerings[0].SourceLabel | Should -Be 'Alpha Source'
    }

    It 'bounds large offering sets while reporting their full count' {
        $programmes = @(
            for ($index = 0; $index -lt 17; $index++) {
                New-OneGuideTestProgramme "channel-$index" ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Multi-channel Event' @('Football') 'provider-a'
            }
        )
        $result = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes $programmes -EvaluationTimeUtc $Evaluation

        $result.Items[0].OfferingCount | Should -Be 17
        $result.Items[0].Offerings.Count | Should -Be 16
        $result.Items[0].OfferingsTruncated | Should -BeTrue
    }

    It 'pages stable query results without hiding additional rows' {
        $programmes = Get-OneGuideFixtureProgrammes
        $first = Get-ChannelForgeOneGuide -Query Category -CategoryKey news -Programmes $programmes -EvaluationTimeUtc $Evaluation -MaximumItems 1
        $second = Get-ChannelForgeOneGuide -Query Category -CategoryKey news -Programmes $programmes -EvaluationTimeUtc $Evaluation -MaximumItems 1 -Offset 1

        $first.TotalCount | Should -Be 2
        $first.ItemsTruncated | Should -BeTrue
        $first.Items.Count | Should -Be 1
        $second.ItemsTruncated | Should -BeFalse
        $second.Items.Count | Should -Be 1
        $second.Items[0].ItemId | Should -Not -Be $first.Items[0].ItemId
    }

    It 'returns optional metadata as null and identifies a details item without changing source records' {
        $programme = New-OneGuideTestProgramme 'details-channel' ($Evaluation.AddHours(3)) ($Evaluation.AddHours(4)) 'No Metadata'
        $before = $programme | ConvertTo-Json -Depth 5 -Compress
        $list = Get-ChannelForgeOneGuide -Query Category -CategoryKey football -Programmes @($programme) -EvaluationTimeUtc $Evaluation
        $all = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($programme) -EvaluationTimeUtc $Evaluation
        $futureProgramme = New-OneGuideTestProgramme 'details-channel' ($Evaluation.AddMinutes(5)) ($Evaluation.AddHours(1)) 'Details Event'
        $future = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($futureProgramme) -EvaluationTimeUtc $Evaluation
        $details = Get-ChannelForgeOneGuide -Query Details -ItemId $future.Items[0].ItemId -Programmes @($futureProgramme) -EvaluationTimeUtc $Evaluation

        $list.TotalCount | Should -Be 0
        $future.Items[0].Subtitle | Should -BeNullOrEmpty
        $future.Items[0].Description | Should -BeNullOrEmpty
        $future.Items[0].EpisodeNumber | Should -BeNullOrEmpty
        $future.Items[0].Sport | Should -BeNullOrEmpty
        $future.Items[0].ConfidenceScore | Should -BeNullOrEmpty
        $details.Items.Count | Should -Be 1
        $details.Items[0].ItemId | Should -Be $future.Items[0].ItemId
        ($programme | ConvertTo-Json -Depth 5 -Compress) | Should -Be $before
    }

    It 'redacts URLs, secrets, private paths, and unsafe identifiers from emitted data' {
        $programme = New-OneGuideTestProgramme 'C:\private\guide.xml' ($Evaluation.AddMinutes(5)) ($Evaluation.AddHours(1)) 'Watch https://user:pass@example.invalid/live secret=abc' @('News') 'https://example.invalid/ACCOUNT_ID/API_TOKEN' -Description 'password=very-secret D:\private\source.xml'
        $programme | Add-Member -NotePropertyName SourceLabel -NotePropertyValue 'D:\private\Provider TOKEN=hidden'
        $result = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($programme) -EvaluationTimeUtc $Evaluation
        $json = $result | ConvertTo-Json -Depth 10 -Compress

        $json | Should -Match '\[redacted-url\]'
        $json | Should -Match '\[redacted-path\]'
        $json | Should -Not -Match 'https?://|ACCOUNT_ID|API_TOKEN|very-secret|hidden|C:\\private|D:\\private'
        $result.Items[0].Offerings[0].Launch.PSObject.Properties.Name | Should -Contain 'ChannelReference'
        $result.Items[0].Offerings[0].Launch.PSObject.Properties.Name | Should -Not -Contain 'Url'
    }

    It 'matches the versioned JSON schema and rejects malformed intervals' {
        $programme = New-OneGuideTestProgramme 'schema-channel' ($Evaluation.AddMinutes(5)) ($Evaluation.AddHours(1)) 'Schema Event' @('Movies') -EpisodeNumber 'S01E01'
        $result = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($programme) -EvaluationTimeUtc $Evaluation
        $json = $result | ConvertTo-Json -Depth 10 -Compress

        Test-Json -Json $json -SchemaFile $SchemaPath | Should -BeTrue
        $invalid = [pscustomobject]@{ ChannelId = 'bad'; Start = $Evaluation; End = $Evaluation; Title = 'Broken'; Categories = @(); SourceId = 'source' }
        { Get-ChannelForgeOneGuide -Query LiveNow -Programmes @($invalid) -EvaluationTimeUtc $Evaluation } | Should -Throw '*invalid time interval*'
    }
}
