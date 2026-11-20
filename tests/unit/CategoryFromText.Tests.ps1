BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $DataPath = Join-Path $RepoRoot 'data\rules\categories.json'
}

Describe 'Get-ChannelForgeCategoryFromText' {
    It 'resolves <Name> from "<Text>"' -ForEach @(
        @{ Name = 'Hockey'; Text = 'NHL Tonight: Bruins at Rangers' }
        @{ Name = 'Basketball'; Text = 'Live NBA basketball' }
        @{ Name = 'Auto Racing'; Text = 'Formula 1 qualifying' }
        @{ Name = 'NASCAR'; Text = 'NASCAR Cup Series' }
        @{ Name = 'Music'; Text = 'Example Music Hits' }
        @{ Name = 'Music'; Text = 'Example Radio One' }
        @{ Name = 'Pay-per-view'; Text = 'PPV Event 12' }
        @{ Name = 'Pay-per-view'; Text = 'Example Pay Per View 3' }
        @{ Name = 'Adult'; Text = 'Example Adult Channel' }
        @{ Name = 'Adult'; Text = 'Example XXX 4' }
    ) {
        InModuleScope ChannelForge -Parameters @{ Name = $Name; Text = $Text } {
            (Get-ChannelForgeCategoryFromText -Text $Text).Category | Should -BeExactly $Name
        }
    }

    It 'resolves every category in the data file on its own first match word' {
        $document = Get-Content -LiteralPath $DataPath -Raw | ConvertFrom-Json
        foreach ($entry in $document.categories) {
            $text = "Tonight: $($entry.match[0]) special"
            $result = InModuleScope ChannelForge -Parameters @{ Text = $text } { Get-ChannelForgeCategoryFromText -Text $Text }
            $result.Category | Should -BeExactly $entry.name
        }
    }

    It 'gives a review flag and no category when two categories match' {
        InModuleScope ChannelForge {
            $result = Get-ChannelForgeCategoryFromText -Text 'Hockey and basketball highlights'
            $result.Category | Should -BeNullOrEmpty
            $result.Review | Should -BeTrue
            $result.Candidates | Should -Be @('Basketball', 'Hockey')
        }
    }

    It 'does not pull an ordinary sports name into Music, Pay-per-view or Adult' {
        InModuleScope ChannelForge {
            foreach ($text in 'Example Sports Network', 'Pay Day Movie', 'Grown-up Soccer Night') {
                (Get-ChannelForgeCategoryFromText -Text $text).Category | Should -Not -BeIn @('Music', 'Pay-per-view', 'Adult')
            }
        }
    }

    It 'gives nothing when no category matches' {
        InModuleScope ChannelForge {
            $result = Get-ChannelForgeCategoryFromText -Text 'The Giants play tonight'
            $result.Category | Should -BeNullOrEmpty
            $result.Review | Should -BeFalse
        }
    }

    It 'does not overwrite a configured name' {
        InModuleScope ChannelForge {
            (Get-ChannelForgeCategoryFromText -Text 'NHL hockey' -Existing 'My Sports').Category | Should -BeExactly 'My Sports'
        }
    }

    It 'lists categories A to Z with no duplicates' {
        $document = Get-Content -LiteralPath $DataPath -Raw | ConvertFrom-Json
        $names = @($document.categories.name)
        $sorted = [string[]]$names.Clone()
        [Array]::Sort($sorted, [System.StringComparer]::OrdinalIgnoreCase)
        $names | Should -Be $sorted
        @($names | Select-Object -Unique).Count | Should -Be $names.Count
        @($document.categories.id | Select-Object -Unique).Count | Should -Be $names.Count
    }
}
