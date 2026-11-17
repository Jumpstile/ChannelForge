BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function New-Xguide([int]$Missing = 0, [string]$State = 'ok', [int]$Behind = 0) {
        [pscustomobject]@{
            Contract = 'xguide-compare/v1'; SharedChannelCount = 4
            Guides = @([pscustomobject]@{ SourceId = 'a'; State = 'ok' }, [pscustomobject]@{ SourceId = 'b'; State = $State })
            Counts = [pscustomobject]@{ MissingChannel = $Missing; StartShift = 0; TitleDiffers = 0; Unmatched = 0; GuideBehind = $Behind }
        }
    }
    function New-Categories([string]$Decision = 'name-and-group') {
        $conf = if ($Decision -ceq 'conflict') { 'none' } else { 'high' }
        [pscustomobject]@{
            ChannelCount = 3
            Rows = @(
                [pscustomobject]@{ ChannelKey = 'k1'; Decision = 'name-and-group'; Confidence = 'high' }
                [pscustomobject]@{ ChannelKey = 'k2'; Decision = 'name-and-group'; Confidence = 'high' }
                [pscustomobject]@{ ChannelKey = 'k3'; Decision = $Decision; Confidence = $conf }
            )
        }
    }
    function New-Readiness {
        [pscustomobject]@{
            Records = @([pscustomobject]@{ ChannelReference = 'c1' }, [pscustomobject]@{ ChannelReference = 'c2' })
            StateCounts = [pscustomobject]@{ Confirmed = 2; Contradiction = 0; StaleSource = 0; SourceUnavailable = 0; Unresolved = 0 }
        }
    }
    function New-Programmes {
        $start = [datetimeoffset]::Parse('2026-10-01T12:00:00Z')
        @(
            New-ChannelForgeProgramme -ChannelId 'one' -Start $start -End $start.AddHours(1) -Title 'Show A' -SourceId 'p'
            New-ChannelForgeProgramme -ChannelId 'two' -Start $start -End $start.AddHours(1) -Title 'Show B' -SourceId 'p'
            [pscustomobject]@{ ChannelId = 'three'; RawChannelId = 'three'; Start = $start; End = $start.AddHours(1); Title = 'Show C'; CanonicalEventId = 'evt-1' }
        )
    }
    function Get-Card($Params) { InModuleScope ChannelForge -Parameters @{ P = $Params } { Get-ChannelForgeGuideQualityScorecard @P } }
    function Get-Gate($Card, [string]$Name) { @($Card.Gates | Where-Object { $_.Name -ceq $Name })[0] }
    function New-CleanInput { @{ XguideReport = (New-Xguide); CategoryReport = (New-Categories); ReadinessResult = (New-Readiness); Programme = (New-Programmes) } }
}

Describe 'Guide quality scorecard: what the owner sees' {
    It 'gives six Pass gates and Overall Pass for clean input' {
        $card = Get-Card (New-CleanInput)
        $card.SchemaVersion | Should -Be 'guide-quality-scorecard/v1'
        @($card.Gates).Count | Should -Be 6
        @($card.Gates | Where-Object { $_.Verdict -ne 'Pass' }) | Should -BeNullOrEmpty
        $card.Overall | Should -Be 'Pass'
    }

    It 'makes completeness Review for a missing channel and Overall follows' {
        $in = New-CleanInput; $in.XguideReport = New-Xguide -Missing 2
        $card = Get-Card $in
        (Get-Gate $card 'Completeness').Verdict | Should -Be 'Review'
        (Get-Gate $card 'Completeness').Counts.MissingChannel | Should -Be 2
        $card.Overall | Should -Be 'Review'
    }

    It 'does not pass freshness for a guide that ended before the build' {
        $in = New-CleanInput; $in.XguideReport = New-Xguide -State 'ended' -Behind 1
        $card = Get-Card $in
        (Get-Gate $card 'Freshness').Verdict | Should -Be 'Fail'
        $card.Overall | Should -Be 'Fail'
    }

    It 'makes an ambiguous category Review, never Pass' {
        $in = New-CleanInput; $in.CategoryReport = New-Categories -Decision 'conflict'
        $gate = Get-Gate (Get-Card $in) 'Classification'
        $gate.Verdict | Should -Be 'Review'
        $gate.Counts.Ambiguous | Should -Be 1
    }

    It 'counts same title and time on different channels with no identity (Deduplication Review)' {
        $start = [datetimeoffset]::Parse('2026-10-01T12:00:00Z')
        $in = New-CleanInput
        $in.Programme = @(
            $in.Programme[2]
            New-ChannelForgeProgramme -ChannelId 'one' -Start $start -End $start.AddHours(1) -Title 'Same Show' -SourceId 'p'
            New-ChannelForgeProgramme -ChannelId 'two' -Start $start -End $start.AddHours(1) -Title 'same  show' -SourceId 'p'
            New-ChannelForgeProgramme -ChannelId 'one' -Start $start -End $start.AddHours(1) -Title 'Sign Off' -SourceId 'p'
            New-ChannelForgeProgramme -ChannelId 'two' -Start $start -End $start.AddHours(1) -Title 'Sign Off' -SourceId 'p'
        )
        $gate = Get-Gate (Get-Card $in) 'Deduplication'
        $gate.Verdict | Should -Be 'Review'
        $gate.Counts.DuplicateGroups | Should -Be 1
    }

    It 'does not call syndicated repeats duplicates when no programme has an event identity (Deduplication NotMeasured)' {
        $in = New-CleanInput; $in.Programme = @(New-Programmes)[0..1]
        $gate = Get-Gate (Get-Card $in) 'Deduplication'
        $gate.Verdict | Should -Be 'NotMeasured'
        $gate.Reason | Should -BeLike '*syndicated*'
    }

    It 'does not pass Accuracy or Completeness when one guide compared nothing' {
        $in = New-CleanInput
        $in.XguideReport = [pscustomobject]@{ Contract = 'xguide-compare/v1'; SharedChannelCount = 0; Guides = @([pscustomobject]@{ SourceId = 'a'; State = 'ok' })
            Counts = [pscustomobject]@{ MissingChannel = 0; StartShift = 0; TitleDiffers = 0; Unmatched = 0; GuideBehind = 0 } }
        $card = Get-Card $in
        (Get-Gate $card 'Accuracy').Verdict | Should -Be 'NotMeasured'
        (Get-Gate $card 'Completeness').Verdict | Should -Be 'NotMeasured'
    }

    It 'makes Completeness Review when playlist channels have no programmes' {
        $in = New-CleanInput; $in.PlaylistGuideId = @('one', 'two', 'ghost', '')
        $gate = Get-Gate (Get-Card $in) 'Completeness'
        $gate.Verdict | Should -Be 'Review'
        $gate.Counts.PlaylistChannelsWithoutProgrammes | Should -Be 2
    }

    It 'reports NotMeasured, never Pass, for a missing input report' {
        $card = Get-Card @{ CategoryReport = (New-Categories) }
        foreach ($name in 'Accuracy', 'Completeness', 'Freshness', 'Deduplication', 'Availability') {
            (Get-Gate $card $name).Verdict | Should -Be 'NotMeasured'
        }
        (Get-Gate $card 'Classification').Verdict | Should -Be 'Pass'
        $card.Overall | Should -Be 'Review'
    }

    It 'keeps the input channel totals and does not change its inputs' {
        $in = New-CleanInput
        $before = $in | ConvertTo-Json -Depth 8
        $card = Get-Card $in
        $again = Get-Card $in
        $card.Totals.CategoryChannelCount | Should -Be 3
        $card.Totals.XguideSharedChannels | Should -Be 4
        $card.Totals.ReadinessRecordCount | Should -Be 2
        $card.Totals.ProgrammeCount | Should -Be 3
        ($in | ConvertTo-Json -Depth 8) | Should -Be $before
        ($card | ConvertTo-Json -Depth 8) | Should -Be ($again | ConvertTo-Json -Depth 8)
    }

    It 'is returned by the public command' {
        $card = Get-ChannelForgeGuideQualityReport -CategoryReport (New-Categories)
        $card.SchemaVersion | Should -Be 'guide-quality-scorecard/v1'
    }
}
