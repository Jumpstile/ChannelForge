BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Event pattern date and time gaps' {
    It 'puts a January event after a December reference in the next year' {
        $result = Invoke-ChannelForgeGuidePatternInference -Examples @(
            'Events 01: New Year Live // UTC Wed 1 Jan 1:00am',
            'Events 02: New Year Replay // UTC Thu 2 Jan 1:00am'
        ) -EventType TemporaryEvent -MinimumExamples 2 -TimezoneMap ([ordered]@{ UTC = '+00:00' }) -ReferenceInstantUtc '2024-12-30T00:00:00Z'

        $result.OverallState | Should -Be 'Confirmed'
        $first = @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '01' })[0]
        $first.EventDate | Should -Be '2025-01-01'
        $first.StartUtc | Should -Be '2025-01-01T01:00:00Z'
    }

    It 'agrees when UK Sun 14 Apr 2:00am and ET Sat 13 Apr 9:00pm are the same instant' {
        $result = Invoke-ChannelForgeGuidePatternInference -Examples @(
            'UFC 01: Fight Night // UK Sun 14 Apr 2:00am // ET Sat 13 Apr 9:00pm',
            'UFC 02: Fight Night // UK Sun 21 Apr 2:00am // ET Sat 20 Apr 9:00pm'
        ) -EventType Fight -MinimumExamples 2 -TimezoneMap ([ordered]@{ UK = '+00:00'; ET = '-05:00' }) -ReferenceInstantUtc '2024-04-15T00:00:00Z'

        $result.OverallState | Should -Be 'Confirmed'
        $result.Candidates[0].TimezoneInterpretation.CrossCheck | Should -Be 'Agrees'
    }

    It 'flags a contradiction when the two zones differ by an hour' {
        $result = Invoke-ChannelForgeGuidePatternInference -Examples @(
            'UFC 01: Fight Night // UK Sun 14 Apr 2:00am // ET Sat 13 Apr 9:00pm',
            'UFC 02: Fight Night // UK Sun 21 Apr 2:00am // ET Sat 20 Apr 8:00pm'
        ) -EventType Fight -MinimumExamples 2 -TimezoneMap ([ordered]@{ UK = '+00:00'; ET = '-05:00' }) -ReferenceInstantUtc '2024-04-15T00:00:00Z'

        $result.OverallState | Should -Be 'Contradiction'
    }

    It 'keeps every colon in a title with extra colons' {
        $result = Invoke-ChannelForgeGuidePatternInference -Examples @(
            'UFC 01: Main: Pereira vs Hill: Title Bout // UTC Sat 13 Apr 5:00pm',
            'UFC 02: Main: Silva vs Cruz: Title Bout // UTC Sat 20 Apr 5:00pm'
        ) -EventType Fight -MinimumExamples 2 -TimezoneMap ([ordered]@{ UTC = '+00:00' }) -ReferenceInstantUtc '2024-04-15T00:00:00Z'

        @($result.ExtractionPreview | Where-Object { $_.ChannelOrdinalText -eq '01' })[0].EventTitle | Should -Be 'Main: Pereira vs Hill: Title Bout'
    }
}
