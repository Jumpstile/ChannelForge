BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function script:New-Row([string]$Group, [string]$Name) {
        [pscustomobject]@{ Group = $Group; OriginalName = $Name; DisplayName = $Name; Url = "http://h.invalid/$Name/user/secret-token" }
    }
    function script:Get-Report($Previous, $Current) {
        & (Get-Module ChannelForge) {
            param($p, $c)
            Get-ChannelForgeSourceChangeReport -Previous $p -Current $c
        } $Previous $Current
    }
}

Describe 'Get-ChannelForgeSourceChangeReport' {
    BeforeAll {
        $script:Old = @((New-Row 'News' 'Alpha'), (New-Row 'News' 'Beta'), (New-Row 'Sports' 'Gamma'))
    }

    It 'reports a first refresh and nothing else when there is no previous list' {
        $r = Get-Report $null @((New-Row 'News' 'Alpha'))
        $r.IsFirstRefresh | Should -BeTrue
        $r.Summary | Should -BeLike 'First refresh*'
        @($r.NewChannels).Count | Should -Be 0
    }

    It 'reports a new group and its new channel' {
        $r = Get-Report $script:Old ($script:Old + (New-Row 'Movies' 'Delta'))
        @($r.NewGroups) | Should -Be @('Movies')
        @($r.NewChannels) | Should -Be @('Delta')
        @($r.MissingChannels).Count | Should -Be 0
        $r.Summary | Should -BeLike 'Groups added: 1. Groups missing: 0. Channels added: 1. Channels missing: 0.'
    }

    It 'reports a missing channel and a missing group' {
        $r = Get-Report $script:Old @((New-Row 'News' 'Alpha'), (New-Row 'News' 'Beta'))
        @($r.MissingChannels) | Should -Be @('Gamma')
        @($r.MissingGroups) | Should -Be @('Sports')
        $r.IsFirstRefresh | Should -BeFalse
    }

    It 'reports no change for identical lists' {
        $r = Get-Report $script:Old $script:Old
        $r.Summary | Should -Be 'Groups added: 0. Groups missing: 0. Channels added: 0. Channels missing: 0.'
    }

    It 'never puts a stream URL in the output' {
        $r = Get-Report $script:Old @((New-Row 'Movies' 'Delta'))
        ($r | ConvertTo-Json -Depth 5) | Should -Not -Match 'h\.invalid|secret-token|http'
    }
}
