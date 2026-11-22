BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Guide pattern analysis: weekday and time provenance' {
    BeforeAll {
        function Invoke-Titles {
            param([string[]]$Text, [string]$Evidence = '')
            InModuleScope ChannelForge -Parameters @{ Text = $Text; Evidence = $Evidence } {
                $examples = @(for ($i = 0; $i -lt $Text.Count; $i++) {
                        New-ChannelForgeGuidePatternExample -Ordinal ($i + 1) -Text $Text[$i] -InputField DisplayName -EventType Fight
                    })
                if ($Evidence) { $examples[0].EvidenceStartUtc = $Evidence }
                Invoke-ChannelForgeGuidePatternAnalysis -Examples $examples `
                    -TimezoneMap ([ordered]@{ UTC = '+00:00' }) -DefaultTimezone '' `
                    -ReferenceInstantUtc ([datetimeoffset]'2024-04-15T00:00:00Z')
            }
        }
    }

    It 'infers the weekday from the date and marks it inferred' {
        $r = Invoke-Titles @('UFC 01: Fight Night // UTC 13 Apr 5:00pm', 'UFC 02: Fight Night // UTC 20 Apr 5:00pm', 'UFC 03: Fight Night // UTC 27 Apr 5:00pm')
        $r.ExtractionPreview[0].EventDayOfWeekSource | Should -Be 'Inferred'
        $r.ExtractionPreview[0].EventDayOfWeekInferred | Should -Be 'Sat'
        $r.ExtractionPreview[0].StartUtc | Should -Be '2024-04-13T17:00:00Z'
    }

    It 'keeps a one-day weekday typo only when evidence agrees, and flags it' {
        $r = Invoke-Titles -Evidence '2024-04-13T17:00:00Z' -Text @('UFC 01: Fight Night // UTC Fri 13 Apr 5:00pm', 'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm', 'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm')
        $s = $r.ExtractionPreview | Where-Object { $_.ReasonCodes -contains 'WeekdayMismatchTolerated' }
        $s.StartUtc | Should -Be '2024-04-13T17:00:00Z'
        $r.ReasonCodes | Should -Contain 'WeekdayMismatchTolerated'
        $r.SelectedCandidate | Should -BeNullOrEmpty
    }

    It 'reports a conflict when a one-day typo has no agreeing evidence' {
        $r = Invoke-Titles @('UFC 01: Fight Night // UTC Fri 13 Apr 5:00pm', 'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm', 'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm')
        $r.ReasonCodes | Should -Contain 'WeekdayConflict'
        $r.SelectedCandidate | Should -BeNullOrEmpty
    }

    It 'reports a conflict and picks no date when the weekday is far off' {
        $r = Invoke-Titles @('UFC 01: Fight Night // UTC Wed 13 Apr 5:00pm', 'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm', 'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm')
        $s = $r.ExtractionPreview | Where-Object { $_.ReasonCodes -contains 'WeekdayConflict' }
        $s.StartUtc | Should -BeNullOrEmpty
        $r.ReasonCodes | Should -Contain 'WeekdayConflict'
        $r.SelectedCandidate | Should -BeNullOrEmpty
    }

    It 'never invents a missing time' {
        $r = Invoke-Titles @('UFC 01: Fight Night // UTC Sat 13 Apr', 'UFC 02: Fight Night // UTC Sat 20 Apr', 'UFC 03: Fight Night // UTC Sat 27 Apr')
        $r.ExtractionPreview[0].EventTimeSource | Should -Be 'Absent'
        $r.ExtractionPreview[0].EventTimeText | Should -BeNullOrEmpty
        $r.ExtractionPreview[0].StartUtc | Should -BeNullOrEmpty
        $ok = Invoke-Titles @('UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm', 'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm', 'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm')
        $ok.ExtractionPreview[0].EventTimeSource | Should -Be 'Present'
    }
}
