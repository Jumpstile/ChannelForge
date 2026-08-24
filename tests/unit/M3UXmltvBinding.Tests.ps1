BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    $script:PlaylistPath = Join-Path $RepoRoot 'tests\fixtures\identity-binding\playlist.m3u'
    $script:GuidePath = Join-Path $RepoRoot 'tests\fixtures\identity-binding\guide.xml'
    $script:Channels = @(Import-ChannelForgeM3UPlaylist `
        -Path $script:PlaylistPath `
        -Provider 'fixture-provider' `
        -Playlist 'identity-fixture')
    $script:Programmes = @(Import-ChannelForgeXmltvSource `
        -Path $script:GuidePath `
        -SourceId 'fixture-guide')

    function Get-BindingOrderSummary {
        param(
            [Parameter(Mandatory)]
            [object]$Result
        )

        return [ordered]@{
            Exact   = @($Result.ExactBindings | ForEach-Object { "$($_.TvgId)->$($_.XmltvSourceId):$($_.XmltvChannelId)" })
            Unbound = @($Result.UnboundChannels | ForEach-Object { "$($_.TvgId):$($_.Reason)" })
            Review  = @($Result.ReviewNeeded | ForEach-Object { "$($_.TvgId):$($_.Reason)" })
            Orphan  = @($Result.OrphanedXmltvChannels | ForEach-Object { "$($_.XmltvChannelId):$($_.Reason)" })
        } | ConvertTo-Json -Depth 8 -Compress
    }
}

Describe 'Resolve-ChannelForgeM3UXmltvBinding' {
    It 'publishes only exact one-to-one tvg-id/XMLTV channel-id matches' {
        $result = Resolve-ChannelForgeM3UXmltvBinding `
            -Channel $script:Channels `
            -Programme $script:Programmes

        $result.ExactBindingCount | Should -Be 2
        @($result.ExactBindings.TvgId) | Should -Be @('alpha.us', 'zeta.us')
        $result.ExactBindings | ForEach-Object {
            $_.Status | Should -Be 'Exact'
            $_.Publishable | Should -BeTrue
            $_.TvgId | Should -Be $_.XmltvChannelId
        }
    }

    It 'uses raw ordinal identity and rejects whitespace, case, and confusable variants' {
        $start = [datetimeoffset]::new(2026, 8, 15, 9, 0, 0, [timespan]::Zero)
        $unicodeConfusable = 'guid' + [char]0x0435 + '.us'
        $cases = @(
            [pscustomobject]@{ Name = 'XMLTV trailing whitespace'; M3U = 'guide.us'; XMLTV = 'guide.us ' }
            [pscustomobject]@{ Name = 'XMLTV leading whitespace'; M3U = 'guide.us'; XMLTV = ' guide.us' }
            [pscustomobject]@{ Name = 'M3U trailing whitespace'; M3U = 'guide.us '; XMLTV = 'guide.us' }
            [pscustomobject]@{ Name = 'M3U leading whitespace'; M3U = ' guide.us'; XMLTV = 'guide.us' }
            [pscustomobject]@{ Name = 'case mismatch'; M3U = 'GUIDE.US'; XMLTV = 'guide.us' }
            [pscustomobject]@{ Name = 'Unicode confusable'; M3U = $unicodeConfusable; XMLTV = 'guide.us' }
        )

        foreach ($case in $cases) {
            $channel = New-ChannelForgeChannel `
                -Provider 'fixture-provider' `
                -Playlist 'ordinal-fixture' `
                -OriginalName 'Guide' `
                -DisplayName 'Guide' `
                -TvgId $case.M3U `
                -Url 'https://example.invalid/live/guide'
            $programme = New-ChannelForgeProgramme `
                -ChannelId $case.XMLTV `
                -Start $start `
                -End $start.AddHours(1) `
                -Title 'Guide' `
                -SourceId 'fixture-guide'

            $result = Resolve-ChannelForgeM3UXmltvBinding -Channel @($channel) -Programme @($programme)

            $result.ExactBindingCount | Should -Be 0 -Because $case.Name
            @($result.UnboundChannels | Where-Object {
                    [string]::Equals([string]$_.TvgId, [string]$case.M3U, [System.StringComparison]::Ordinal)
                }).Count | Should -Be 1 -Because $case.Name
        }

        $exactChannel = New-ChannelForgeChannel -OriginalName 'Guide' -DisplayName 'Guide' -TvgId 'guide.us ' -Url 'https://example.invalid/live/guide'
        $exactProgramme = New-ChannelForgeProgramme `
            -ChannelId 'guide.us ' `
            -Start $start `
            -End $start.AddHours(1) `
            -Title 'Guide' `
            -SourceId 'fixture-guide'
        $exactResult = Resolve-ChannelForgeM3UXmltvBinding -Channel @($exactChannel) -Programme @($exactProgramme)

        $exactResult.ExactBindingCount | Should -Be 1
        $exactResult.ExactBindings[0].TvgId | Should -Be 'guide.us '
        $exactResult.ExactBindings[0].XmltvChannelId | Should -Be 'guide.us '
    }

    It 'keeps a channel with no tvg-id explicitly unbound' {
        $result = Resolve-ChannelForgeM3UXmltvBinding -Channel $script:Channels -Programme $script:Programmes
        $unbound = @($result.UnboundChannels | Where-Object Reason -eq 'MissingTvgId')

        $unbound.Count | Should -Be 1
        $unbound[0].Status | Should -Be 'Unbound'
        $unbound[0].Publishable | Should -BeFalse
        $unbound[0].TvgId | Should -Be ''
    }

    It 'keeps a tvg-id with no XMLTV channel explicitly unbound' {
        $result = Resolve-ChannelForgeM3UXmltvBinding -Channel $script:Channels -Programme $script:Programmes
        $unbound = @($result.UnboundChannels | Where-Object TvgId -eq 'missing.us')

        $unbound.Count | Should -Be 1
        $unbound[0].Reason | Should -Be 'TvgIdNotFoundInXmltv'
        $result.ExactBindings.TvgId | Should -Not -Contain 'missing.us'
    }

    It 'keeps duplicate XMLTV channel declarations review-needed without selecting one' {
        $result = Resolve-ChannelForgeM3UXmltvBinding -Channel $script:Channels -Programme $script:Programmes
        $review = @($result.ReviewNeeded | Where-Object TvgId -eq 'ambiguous.us')

        $review.Count | Should -Be 1
        $review[0].Reason | Should -Be 'DuplicateXmltvChannelIdDeclaration'
        $review[0].Candidates.Count | Should -Be 1
        $review[0].Candidates[0].DeclarationCount | Should -Be 2
        $review[0].Publishable | Should -BeFalse
        $result.ExactBindings.TvgId | Should -Not -Contain 'ambiguous.us'
    }

    It 'reports XMLTV channel identities with no M3U channel' {
        $result = Resolve-ChannelForgeM3UXmltvBinding -Channel $script:Channels -Programme $script:Programmes
        $orphan = @($result.OrphanedXmltvChannels | Where-Object XmltvChannelId -eq 'orphan.us')

        $orphan.Count | Should -Be 1
        $orphan[0].Status | Should -Be 'OrphanedXmltv'
        $orphan[0].Reason | Should -Be 'NoM3UChannelWithTvgId'
        $orphan[0].Candidates[0].Evidence[0].ChannelCount | Should -Be 4
    }

    It 'preserves XMLTV provenance and duplicate declaration evidence' {
        $result = Resolve-ChannelForgeM3UXmltvBinding -Channel $script:Channels -Programme $script:Programmes
        $evidence = $result.ExactBindings[0].Evidence[0]

        $evidence.EvidenceType | Should -Be 'xmltv-source'
        $evidence.SourceId | Should -Be 'fixture-guide'
        @($evidence.ChannelIdOccurrences | Where-Object Id -eq 'ambiguous.us')[0].OccurrenceCount | Should -Be 2
        $result.ExactBindings[0].Evidence | Should -Be $script:Programmes[0].Evidence
    }

    It 'produces the same report ordering for reversed input arrays' {
        $reverseChannels = [System.Collections.Generic.List[object]]::new()
        for ($index = $script:Channels.Count - 1; $index -ge 0; $index--) {
            [void]$reverseChannels.Add($script:Channels[$index])
        }
        $reverseProgrammes = [System.Collections.Generic.List[object]]::new()
        for ($index = $script:Programmes.Count - 1; $index -ge 0; $index--) {
            [void]$reverseProgrammes.Add($script:Programmes[$index])
        }

        $forward = Resolve-ChannelForgeM3UXmltvBinding `
            -Channel $script:Channels `
            -Programme $script:Programmes
        $reverse = Resolve-ChannelForgeM3UXmltvBinding `
            -Channel @($reverseChannels.ToArray()) `
            -Programme @($reverseProgrammes.ToArray())

        Get-BindingOrderSummary -Result $reverse | Should -Be (Get-BindingOrderSummary -Result $forward)
    }

    It 'does not mutate canonical M3U channels or XMLTV programmes' {
        $beforeChannels = @($script:Channels | ForEach-Object {
                "{0}|{1}|{2}|{3}" -f $_.DisplayName, $_.TvgId, $_.Url, $_.AssignedNumber
            }) -join "`n"
        $beforeProgrammes = @($script:Programmes | ForEach-Object {
                "{0}|{1}|{2}|{3}" -f $_.SourceId, $_.ChannelId, $_.Title, $_.Evidence.SourceId
            }) -join "`n"

        Resolve-ChannelForgeM3UXmltvBinding -Channel $script:Channels -Programme $script:Programmes | Out-Null

        $afterChannels = @($script:Channels | ForEach-Object {
                "{0}|{1}|{2}|{3}" -f $_.DisplayName, $_.TvgId, $_.Url, $_.AssignedNumber
            }) -join "`n"
        $afterProgrammes = @($script:Programmes | ForEach-Object {
                "{0}|{1}|{2}|{3}" -f $_.SourceId, $_.ChannelId, $_.Title, $_.Evidence.SourceId
            }) -join "`n"

        $afterChannels | Should -Be $beforeChannels
        $afterProgrammes | Should -Be $beforeProgrammes
    }
}
