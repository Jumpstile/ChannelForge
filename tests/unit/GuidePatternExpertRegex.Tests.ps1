BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Guide pattern analysis: expert regex and input domain' {
    BeforeAll {
        $script:Lines = @(
            'ZZQ 01 :: Alpha Cup // UTC Sat 13 Apr 5:00pm',
            'ZZQ 02 :: Beta Cup // UTC Sat 20 Apr 5:00pm',
            'ZZQ 03 :: Gamma Cup // UTC Sat 27 Apr 5:00pm'
        )
        $script:Good = '^(?<identifier>ZZQ)\s+(?<ordinal>\d+)\s*::\s*(?<title>.+?)\s*//\s*(?<tz>\w+)\s+(?<date>\w+ \d+ \w+)\s+(?<time>[\d:]+[ap]m)$'
        function Invoke-Case {
            param([string]$Expert = '', [string]$InputField = 'DisplayName', [object]$Existing = $null, [string[]]$Text = $script:Lines)
            InModuleScope ChannelForge -Parameters @{ Expert = $Expert; Field = $InputField; Existing = $Existing; Text = $Text } {
                $examples = @(for ($i = 0; $i -lt $Text.Count; $i++) {
                        New-ChannelForgeGuidePatternExample -Ordinal ($i + 1) -Text $Text[$i] -InputField $Field -EventType Fight
                    })
                Invoke-ChannelForgeGuidePatternAnalysis -Examples $examples `
                    -TimezoneMap ([ordered]@{ UTC = '+00:00' }) -DefaultTimezone '' `
                    -ReferenceInstantUtc ([datetimeoffset]'2024-04-15T00:00:00Z') `
                    -ExpertPattern $Expert -ExistingRule $Existing
            }
        }
    }

    It 'reads title and start time through an expert pattern' {
        $result = Invoke-Case -Expert $script:Good
        $result.ExtractionPreview[0].EventTitle | Should -Be 'Alpha Cup'
        $result.ExtractionPreview[0].StartUtc | Should -Be '2024-04-13T17:00:00Z'
        $result.CanPublish | Should -BeFalse
    }

    It 'fails closed on an invalid or unsafe expert pattern and does not fall back' {
        foreach ($bad in @('([unclosed', '^(?<title>.+)(?<bogus>x)?$', '^(?<date>.+)$')) {
            $result = Invoke-Case -Expert $bad
            $result.ReasonCodes | Should -Contain 'ExpertPatternInvalid'
            $result.OverallState | Should -Be 'NeedsReview'
            $result.SelectedCandidate | Should -BeNullOrEmpty
            $result.ExtractionPreview[0].EventTitle | Should -BeNullOrEmpty
        }
    }

    It 'sends the whole result to review when one example does not match' {
        $text = @($script:Lines + 'something else entirely')
        $result = Invoke-Case -Expert $script:Good -Text $text
        $result.ReasonCodes | Should -Contain 'ExpertPatternNoMatch'
        $result.SelectedCandidate | Should -BeNullOrEmpty
    }

    It 'does not leak the pattern text into the result' {
        $json = (Invoke-Case -Expert $script:Good) | ConvertTo-Json -Depth 20
        $json | Should -Not -BeLike '*(?<identifier>*'
    }

    It 'adds nothing to native rule ids when no expert pattern is given' {
        $native = Invoke-Case
        $expert = Invoke-Case -Expert $script:Good
        $native.Candidates[0].Grammar.Contains('ExpertPatternHash') | Should -BeFalse
        $expert.Candidates[0].Grammar.Contains('ExpertPatternHash') | Should -BeTrue
        $expert.Candidates[0].RuleId | Should -Not -Be $native.Candidates[0].RuleId
    }

    It 'flags a rule learned from channel names when applied to stream names' {
        $native = Invoke-Case
        $result = Invoke-Case -InputField OriginalName -Existing $native.Candidates[0]
        $result.ReasonCodes | Should -Contain 'InputDomainMismatch'
        $result.DriftStatus | Should -Be 'Detected'
        $result.SelectedCandidate | Should -BeNullOrEmpty
    }

    It 'treats display name and tvg name as the same domain' {
        $native = Invoke-Case
        $result = Invoke-Case -InputField TvgName -Existing $native.Candidates[0]
        $result.ReasonCodes | Should -Not -Contain 'InputDomainMismatch'
    }

    It 'sends mixed channel-name and stream-name examples to review' {
        $result = InModuleScope ChannelForge {
            $examples = @(
                New-ChannelForgeGuidePatternExample -Ordinal 1 -Text 'ZZQ 01: Alpha Cup // UTC Sat 13 Apr 5:00pm' -InputField DisplayName -EventType Fight
                New-ChannelForgeGuidePatternExample -Ordinal 2 -Text 'ZZQ 02: Beta Cup // UTC Sat 20 Apr 5:00pm' -InputField OriginalName -EventType Fight
                New-ChannelForgeGuidePatternExample -Ordinal 3 -Text 'ZZQ 03: Gamma Cup // UTC Sat 27 Apr 5:00pm' -InputField DisplayName -EventType Fight
            )
            Invoke-ChannelForgeGuidePatternAnalysis -Examples $examples -TimezoneMap ([ordered]@{ UTC = '+00:00' }) -DefaultTimezone '' -ReferenceInstantUtc ([datetimeoffset]'2024-04-15T00:00:00Z')
        }
        $result.ReasonCodes | Should -Contain 'InputDomainMixed'
        $result.SelectedCandidate | Should -BeNullOrEmpty
    }
}
