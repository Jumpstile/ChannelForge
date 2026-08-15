BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'

    function Get-BoundProgrammeSummary {
        param(
            [Parameter(Mandatory)]
            [object]$MergeResult
        )

        return @(
            $MergeResult.BoundProgrammes | ForEach-Object {
                [ordered]@{
                    BindingKey       = $_.Binding.BindingKey
                    ChannelId        = $_.Programme.ChannelId
                    SourceId         = $_.Programme.SourceId
                    StartUtc         = $_.Programme.Start.ToUniversalTime().ToString('o', [cultureinfo]::InvariantCulture)
                    EndUtc           = $_.Programme.End.ToUniversalTime().ToString('o', [cultureinfo]::InvariantCulture)
                    Title            = $_.Programme.Title
                    Status           = $_.Status
                    ContributorCount = @($_.Contributors).Count
                    EvidenceCount    = @($_.Evidence).Count
                } | ConvertTo-Json -Depth 5 -Compress
            }
        ) -join ([Environment]::NewLine)
    }

    $script:sourceA = [pscustomobject]@{
        Name      = 'source-a'
        Path      = $script:FixturePath
        Url       = ''
        Format    = 'xmltv'
        Supported = $true
    }
    $script:sourceB = [pscustomobject]@{
        Name      = 'source-b'
        Path      = $script:FixturePath
        Url       = ''
        Format    = 'xmltv'
        Supported = $true
    }
    $script:programmesA = @(Import-ChannelForgeConfiguredXmltvSource -Source $script:sourceA)
    $script:programmesB = @(Import-ChannelForgeConfiguredXmltvSource -Source $script:sourceB)
}

Describe 'Merge-ChannelForgeXmltvProgrammes' {
    It 'keeps bindings source-scoped when raw channel references match' {
        $result = Merge-ChannelForgeXmltvProgrammes -Programme @($script:programmesA + $script:programmesB)

        $result.Bindings.Count | Should -Be 4
        $result.BoundProgrammes.Count | Should -Be 4
        @($result.Bindings | Where-Object SourceId -eq 'source-a').Count | Should -Be 2
        @($result.Bindings | Where-Object SourceId -eq 'source-b').Count | Should -Be 2
        @($result.BoundProgrammes | Where-Object { $_.Programme.ChannelId -eq 'news.us' }).Count | Should -Be 2
        $result.HasConflicts | Should -BeFalse
    }

    It 'collapses exact duplicates while preserving every contributor and evidence record' {
        $result = Merge-ChannelForgeXmltvProgrammes -Programme @($script:programmesA + $script:programmesA)

        $result.BoundProgrammes.Count | Should -Be 2
        $result.Duplicates.Count | Should -Be 2
        $result.BoundProgrammes.Status | Should -Be @('DuplicateMerged', 'DuplicateMerged')
        @($result.BoundProgrammes[0].Contributors).Count | Should -Be 2
        @($result.BoundProgrammes[0].Evidence).Count | Should -Be 2
    }

    It 'produces the same ordered result for every input permutation' {
        $forward = Merge-ChannelForgeXmltvProgrammes -Programme @($script:programmesA + $script:programmesB)
        $reverse = Merge-ChannelForgeXmltvProgrammes -Programme @($script:programmesB + $script:programmesA)

        Get-BoundProgrammeSummary -MergeResult $forward | Should -Be (Get-BoundProgrammeSummary -MergeResult $reverse)
    }

    It 'preserves conflicting facts for review without choosing a winner' {
        $original = $script:programmesA[0]
        $conflicting = New-ChannelForgeProgramme -ChannelId $original.ChannelId -Start $original.Start -End $original.End -Title 'Different title from the same source' -SourceId $original.SourceId -Evidence $original.Evidence

        $result = Merge-ChannelForgeXmltvProgrammes -Programme @($original, $conflicting)

        $result.Conflicts.Count | Should -Be 1
        $result.HasConflicts | Should -BeTrue
        $result.Conflicts[0].Status | Should -Be 'NeedsReview'
        @($result.Conflicts[0].Alternatives).Count | Should -Be 2
        $result.BoundProgrammes.Status | Should -Be @('Conflict', 'Conflict')
        @($result.BoundProgrammes | ForEach-Object { $_.Programme.Title }) | Should -Contain 'Different title from the same source'
        @($result.BoundProgrammes | ForEach-Object { $_.Programme.Title }) | Should -Contain $original.Title
    }

    It 'retains adjacent and overlapping non-identical intervals' {
        $original = $script:programmesA[0]
        $adjacent = New-ChannelForgeProgramme -ChannelId $original.ChannelId -Start $original.End -End $original.End.AddHours(1) -Title 'Adjacent programme' -SourceId $original.SourceId -Evidence $original.Evidence
        $overlapping = New-ChannelForgeProgramme -ChannelId $original.ChannelId -Start $original.Start.AddMinutes(30) -End $original.End.AddMinutes(30) -Title 'Overlapping programme' -SourceId $original.SourceId -Evidence $original.Evidence

        $result = Merge-ChannelForgeXmltvProgrammes -Programme @($original, $adjacent, $overlapping)

        $result.BoundProgrammes.Count | Should -Be 3
        $result.Duplicates.Count | Should -Be 0
        $result.Conflicts.Count | Should -Be 0
    }

    It 'rejects missing or inconsistent source-scoped identity' {
        $original = $script:programmesA[0]
        $missingSource = New-ChannelForgeProgramme -ChannelId $original.ChannelId -Start $original.Start -End $original.End -Title $original.Title
        $mismatchedEvidence = New-ChannelForgeProgramme -ChannelId $original.ChannelId -Start $original.Start -End $original.End -Title $original.Title -SourceId $original.SourceId -Evidence ([pscustomobject]@{ SourceId = 'different-source' })

        { Merge-ChannelForgeXmltvProgrammes -Programme $missingSource } | Should -Throw '*SourceId*'
        { Merge-ChannelForgeXmltvProgrammes -Programme $mismatchedEvidence } | Should -Throw '*does not match evidence*'
    }

    It 'does not mutate the input Programme objects' {
        $original = $script:programmesA[0]
        $before = [ordered]@{
            ChannelId = $original.ChannelId
            Start     = $original.Start
            End       = $original.End
            Title     = $original.Title
            SourceId  = $original.SourceId
            Evidence  = $original.Evidence
        } | ConvertTo-Json -Depth 5 -Compress

        Merge-ChannelForgeXmltvProgrammes -Programme @($script:programmesA + $script:programmesA) | Out-Null

        $after = [ordered]@{
            ChannelId = $original.ChannelId
            Start     = $original.Start
            End       = $original.End
            Title     = $original.Title
            SourceId  = $original.SourceId
            Evidence  = $original.Evidence
        } | ConvertTo-Json -Depth 5 -Compress
        $after | Should -Be $before
    }
}
