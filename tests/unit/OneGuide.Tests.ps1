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
                foreach ($name in @('SourceLabel', 'Sport', 'League', 'HomeParticipant', 'AwayParticipant', 'Promotion', 'CanonicalEventId', 'Kind')) {
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

    It 'exposes only the eight Slice 1 categories and keeps wrestling promotion structured' {
        $fixtureProgrammes = Get-OneGuideFixtureProgrammes
        $expectedTaxonomy = @('live-now', 'starting-soon', 'wrestling', 'football', 'baseball', 'soccer', 'movies', 'news')
        $registryTaxonomy = @(& (Get-Module ChannelForge) { Get-ChannelForgeOneGuideCategoryRegistry } | ForEach-Object { $_.Key })
        $registryTaxonomy | Should -Be $expectedTaxonomy
        $categoryAliases = [ordered]@{
            wrestling = 'Professional Wrestling'
            football = 'Football'
            baseball = 'Baseball'
            soccer = 'Association Football'
            movies = 'Film'
            news = 'Current Affairs'
        }
        $categoryProgrammes = @(
            foreach ($entry in $categoryAliases.GetEnumerator()) {
                New-OneGuideTestProgramme "category-$($entry.Key)" ($Evaluation.AddMinutes(30)) ($Evaluation.AddHours(1)) "Category $($entry.Key)" @([string]$entry.Value)
            }
        )
        $programmes = @($fixtureProgrammes) + @($categoryProgrammes)

        foreach ($key in $expectedTaxonomy) {
            $result = Get-ChannelForgeOneGuide -Query Category -CategoryKey $key -Programmes $programmes -EvaluationTimeUtc $Evaluation
            $result.Query | Should -Be 'Category'
            $result.CategoryKey | Should -Be $key
            $result.TotalCount | Should -BeGreaterThan 0
        }

        { Get-ChannelForgeOneGuide -Query Category -CategoryKey hockey -Programmes $programmes -EvaluationTimeUtc $Evaluation } | Should -Throw '*Unsupported One Guide category*'
        $items = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes $fixtureProgrammes -EvaluationTimeUtc $Evaluation
        $wrestling = Get-ChannelForgeOneGuide -Query Category -CategoryKey wrestling -Programmes $fixtureProgrammes -EvaluationTimeUtc $Evaluation
        $items.Items[0].Promotion | Should -BeNullOrEmpty
        $wrestling.Items[0].Promotion.Id | Should -Match '^cf-[a-f0-9]{64}$'
        $wrestling.Items[0].Promotion.Name | Should -Be 'WWE'
        @($wrestling.Items[0].CategoryKeys | Where-Object { $_ -notin $expectedTaxonomy }) | Should -BeNullOrEmpty
    }

    It 'groups offerings only when an explicit canonical event identity is present' {
        $programmes = Get-OneGuideFixtureProgrammes
        $reversed = @($programmes)
        [array]::Reverse($reversed)
        $forward = Get-ChannelForgeOneGuide -Query Category -CategoryKey wrestling -Programmes $programmes -EvaluationTimeUtc $Evaluation
        $reverse = Get-ChannelForgeOneGuide -Query Category -CategoryKey wrestling -Programmes $reversed -EvaluationTimeUtc $Evaluation
        $item = $forward.Items[0]

        $forward.TotalCount | Should -Be 1
        $item.ItemId | Should -Be $reverse.Items[0].ItemId
        ($forward | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($reverse | ConvertTo-Json -Depth 10 -Compress)
        $item.Offerings.Count | Should -Be 2
        $item.OfferingCount | Should -Be 2
        $item.OfferingsTruncated | Should -BeFalse
        $item.Kind | Should -Be 'Event'
        $item.CategoryKeys | Should -Contain 'wrestling'
        $item.Sport | Should -Be 'Wrestling'
        $item.League | Should -Be 'WWE'
        $item.Promotion.Id | Should -Match '^cf-[a-f0-9]{64}$'
        $item.Promotion.Id | Should -Not -Be 'wwe'
        @($item.Offerings.Launch.ChannelReference | Where-Object { $_ -notmatch '^cf-[a-f0-9]{64}$' }) | Should -BeNullOrEmpty
        @($item.Offerings.SourceId | Where-Object { $_ -notmatch '^cf-[a-f0-9]{64}$' }) | Should -BeNullOrEmpty
        $item.ItemId | Should -Not -Be $item.Offerings[0].Launch.ChannelReference
    }

    It 'keeps matching title and time on separate channels as separate items without explicit identity' {
        $first = New-OneGuideTestProgramme 'channel-a' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Same Scheduled Title' @('Wrestling') 'provider-a'
        $second = New-OneGuideTestProgramme 'channel-b' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Same Scheduled Title' @('Wrestling') 'provider-b'
        $result = Get-ChannelForgeOneGuide -Query Category -CategoryKey wrestling -Programmes @($first, $second) -EvaluationTimeUtc $Evaluation

        $result.TotalCount | Should -Be 2
        @($result.Items.ItemId | Select-Object -Unique).Count | Should -Be 2
        @($result.Items | Where-Object { $_.OfferingCount -ne 1 }) | Should -BeNullOrEmpty
    }

    It 'uses only an exactly recognized explicit Kind value instead of inferring from category or episode metadata' {
        $categoryOnly = New-OneGuideTestProgramme 'category-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Wrestling Movie' @('Wrestling', 'Movies') 'provider-a' -EpisodeNumber 'S01E01'
        $explicit = New-OneGuideTestProgramme 'explicit-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Explicit Event' @('Wrestling') 'provider-a'
        $lowercase = New-OneGuideTestProgramme 'lowercase-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Unrecognized Kind' @('Wrestling') 'provider-a'
        $explicit | Add-Member -NotePropertyName Kind -NotePropertyValue Event
        $lowercase | Add-Member -NotePropertyName Kind -NotePropertyValue event
        $categoryResult = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($categoryOnly) -EvaluationTimeUtc $Evaluation
        $explicitResult = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($explicit) -EvaluationTimeUtc $Evaluation
        $lowercaseResult = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($lowercase) -EvaluationTimeUtc $Evaluation

        $categoryResult.Items[0].Kind | Should -Be 'Programme'
        $explicitResult.Items[0].Kind | Should -Be 'Event'
        $lowercaseResult.Items[0].Kind | Should -Be 'Programme'
    }

    It 'keeps conflicting same-source programme rows separate and stable under permutation' {
        $first = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Football') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Football description'
        $second = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Wrestling') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Wrestling description'
        $third = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Football') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Football description'
        $third | Add-Member -NotePropertyName League -NotePropertyValue 'League B'
        $duplicate = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Football') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Football description'
        $newFlag = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Football') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Football description'
        $newFlag.IsNew = $true
        $liveFlag = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Football') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Football description'
        $liveFlag.IsLive = $true
        $premiereFlag = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Football') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Football description'
        $premiereFlag.IsPremiere = $true
        $unknownDrama = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Drama') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Football description'
        $unknownDocumentary = New-OneGuideTestProgramme 'shared-channel' ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Episode Event' @('Documentary') 'provider-a' -EpisodeNumber 'S01E01' -Description 'Football description'
        $allRows = @($first, $second, $third, $duplicate, $newFlag, $liveFlag, $premiereFlag, $unknownDrama, $unknownDocumentary)
        $reverseRows = @($unknownDocumentary, $unknownDrama, $premiereFlag, $liveFlag, $newFlag, $duplicate, $third, $second, $first)
        $forward = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes $allRows -EvaluationTimeUtc $Evaluation
        $reverse = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes $reverseRows -EvaluationTimeUtc $Evaluation
        $forward.TotalCount | Should -Be 8
        ($forward | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($reverse | ConvertTo-Json -Depth 10 -Compress)
        @($forward.Items.ItemId | Select-Object -Unique).Count | Should -Be 8
        @($forward.Items | Where-Object { $_.CategoryKeys -contains 'football' -and $_.Description -eq 'Wrestling description' }).Count | Should -Be 0
        @($forward.Items | Where-Object { $_.CategoryKeys -contains 'wrestling' -and $_.Description -eq 'Football description' }).Count | Should -Be 0
        @($forward.Items | Where-Object { $_.Description -eq 'Football description' -and $_.League -eq 'League B' }).Count | Should -Be 1
        @($forward.Items | Where-Object { $_.Description -eq 'Football description' -and $null -eq $_.League }).Count | Should -Be 6
        @($forward.Items | Where-Object { $_.OfferingCount -ne 1 }).Count | Should -Be 0
    }

    It 'bounds large offering sets while reporting their full count' {
        $programmes = @(
            for ($index = 0; $index -lt 17; $index++) {
                $programme = New-OneGuideTestProgramme "channel-$index" ($Evaluation.AddMinutes(20)) ($Evaluation.AddHours(1)) 'Multi-channel Event' @('Football') 'provider-a'
                $programme | Add-Member -NotePropertyName CanonicalEventId -NotePropertyValue 'sample-event:multi-channel-2026'
                $programme
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
    It 'hashes source, channel, and promotion identifiers even when they resemble ordinary labels' {
        $programme = New-OneGuideTestProgramme 'ChannelPlan42' ($Evaluation.AddMinutes(5)) ($Evaluation.AddHours(1)) 'Visible Programme' @('Wrestling') 'ProviderAccount19'
        $programme | Add-Member -NotePropertyName Promotion -NotePropertyValue @{ Id = 'PromoAccess29'; Name = 'WWE' }
        $result = Get-ChannelForgeOneGuide -Query StartingSoon -Programmes @($programme) -EvaluationTimeUtc $Evaluation
        $json = $result | ConvertTo-Json -Depth 10 -Compress

        $json | Should -Not -Match 'ChannelPlan42|ProviderAccount19|PromoAccess29'
        $result.Items[0].Offerings[0].SourceId | Should -Match '^cf-[a-f0-9]{64}$'
        $result.Items[0].Offerings[0].Launch.ChannelReference | Should -Match '^cf-[a-f0-9]{64}$'
        $result.Items[0].Promotion.Id | Should -Match '^cf-[a-f0-9]{64}$'
        $result.Items[0].Offerings[0].SourceLabel | Should -Be 'Source'
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
