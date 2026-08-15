BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'New-ChannelForgeProgramme' {
    It 'creates a target-neutral programme with guide metadata' {
        $start = [datetimeoffset]::new(2026, 8, 15, 9, 0, 0, [timespan]::Zero)
        $end = $start.AddHours(1)
        $evidence = [pscustomobject]@{ SourceId = 'fixture' }

        $programme = New-ChannelForgeProgramme `
            -ChannelId 'news.us' `
            -Start $start `
            -End $end `
            -Title 'Morning News' `
            -Subtitle 'First Edition' `
            -Description 'Headlines and weather.' `
            -Categories @('News', 'Local') `
            -EpisodeNumber 'S01E01' `
            -IsNew $true `
            -SourceId 'fixture' `
            -Evidence $evidence

        $programme.GetType().Name | Should -Be 'Programme'
        $programme.ChannelId | Should -Be 'news.us'
        $programme.Start | Should -Be $start
        $programme.End | Should -Be $end
        $programme.Title | Should -Be 'Morning News'
        $programme.Subtitle | Should -Be 'First Edition'
        $programme.Description | Should -Be 'Headlines and weather.'
        $programme.Categories | Should -Be @('News', 'Local')
        $programme.EpisodeNumber | Should -Be 'S01E01'
        $programme.IsNew | Should -BeTrue
        $programme.IsLive | Should -BeFalse
        $programme.SourceId | Should -Be 'fixture'
        $programme.Evidence | Should -Be $evidence
    }

    It 'trims textual fields and initializes optional values safely' {
        $start = [datetimeoffset]::new(2026, 8, 15, 9, 0, 0, [timespan]::Zero)
        $programme = New-ChannelForgeProgramme `
            -ChannelId ' news.us ' `
            -Start $start `
            -End $start.AddHours(1) `
            -Title ' Morning News ' `
            -Categories @(' News ', '', '   ')

        $programme.ChannelId | Should -Be 'news.us'
        $programme.Title | Should -Be 'Morning News'
        $programme.Subtitle | Should -Be ''
        $programme.Description | Should -Be ''
        $programme.Categories | Should -Be @('News')
        $programme.IsNew | Should -BeFalse
        $programme.IsLive | Should -BeFalse
        $programme.IsPremiere | Should -BeFalse
        $programme.Evidence | Should -BeNullOrEmpty
    }

    It 'rejects missing identity, title, and non-positive duration' {
        $start = [datetimeoffset]::new(2026, 8, 15, 9, 0, 0, [timespan]::Zero)

        { New-ChannelForgeProgramme -ChannelId '' -Start $start -End $start.AddHours(1) -Title 'Test' } | Should -Throw
        { New-ChannelForgeProgramme -ChannelId 'news.us' -Start $start -End $start.AddHours(1) -Title '' } | Should -Throw
        { New-ChannelForgeProgramme -ChannelId 'news.us' -Start $start -End $start -Title 'Test' } | Should -Throw
    }
}
