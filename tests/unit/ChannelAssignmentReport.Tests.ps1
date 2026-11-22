BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Get-ChannelForgeChannelAssignmentReport' {
    BeforeAll {
        $script:Result = & (Get-Module ChannelForge) {
            function New-Ch($name, $tvg, $url, $number) {
                $c = [Channel]::new()
                $c.DisplayName = $name; $c.TvgId = $tvg; $c.Url = $url; $c.Provider = 'ProviderOne'
                $c.Group = 'News'; $c.AssignedNumber = $number
                $c
            }
            $alpha = New-Ch 'Alpha News' 'alpha.test' 'http://h.invalid/a' 101
            $bravo = New-Ch 'Bravo' '' 'http://h.invalid/b' $null
            $twin1 = New-Ch 'Twin' 'twin.one' 'http://h.invalid/t1' 5
            $twin2 = New-Ch 'twin' 'twin.two' 'http://h.invalid/t2' 6
            $all = @($alpha, $bravo, $twin1, $twin2)
            $binding = [pscustomobject]@{
                ExactBindings   = @([pscustomobject]@{ M3UChannel = $alpha; Status = 'Exact'; XmltvChannelId = 'alpha.test' })
                ReviewNeeded    = @()
                UnboundChannels = @([pscustomobject]@{ M3UChannel = $bravo; Status = 'Unbound'; Reason = 'MissingTvgId' })
            }
            $numbers = @([pscustomobject]@{ channelKey = 'id:alpha.test'; number = 101 })
            $choices = @([pscustomobject]@{ key = (Get-ChannelForgeChannelKey -Url 'http://h.invalid/b'); choice = 'KeepWithoutGuide'; guideId = $null })
            [pscustomobject]@{
                Found     = Get-ChannelForgeChannelAssignmentReport -Channel $all -Query 'alpha.test' -BindingResult $binding -ChannelNumber $numbers
                Missing   = Get-ChannelForgeChannelAssignmentReport -Channel $all -Query 'nope'
                Ambiguous = Get-ChannelForgeChannelAssignmentReport -Channel $all -Query 'TWIN'
                NoGuide   = Get-ChannelForgeChannelAssignmentReport -Channel $all -Query 'Bravo' -BindingResult $binding -GuideChoice $choices
                Text      = Format-ChannelForgeChannelAssignmentReport -Report (Get-ChannelForgeChannelAssignmentReport -Channel $all -Query 'alpha.test' -BindingResult $binding -ChannelNumber $numbers)
            }
        }
    }

    It 'reports source, group, guide and a saved number for a found channel' {
        $r = $script:Result.Found
        $r.Found | Should -BeTrue
        $r.Source | Should -Be 'ProviderOne'
        $r.Group | Should -Be 'News'
        $r.Guide.GuideId | Should -Be 'alpha.test'
        $r.Guide.Origin | Should -Be 'PlaylistTvgId'
        $r.Number.Value | Should -Be 101
        $r.Number.IsSavedUser | Should -BeTrue
    }

    It 'says not found instead of guessing' {
        $script:Result.Missing.Found | Should -BeFalse
        $script:Result.Missing.Reason | Should -Be 'NotFound'
    }

    It 'lists the matches when a name is ambiguous' {
        $script:Result.Ambiguous.Found | Should -BeFalse
        $script:Result.Ambiguous.Reason | Should -Be 'Ambiguous'
        @($script:Result.Ambiguous.Matches).Count | Should -Be 2
    }

    It 'reports no guide, an unnumbered channel and the saved decision' {
        $r = $script:Result.NoGuide
        $r.Guide.GuideId | Should -BeNullOrEmpty
        $r.Guide.Origin | Should -Be 'None'
        $r.Number.Value | Should -BeNullOrEmpty
        $r.Number.IsSavedUser | Should -BeFalse
        $r.Decision.choice | Should -Be 'KeepWithoutGuide'
    }

    It 'formats plain text that never shows the stream address' {
        ($script:Result.Text -join "`n") | Should -Match 'Number:\s+101 \(saved by you\)'
        ($script:Result.Text -join "`n") | Should -Not -Match 'invalid'
    }
}
