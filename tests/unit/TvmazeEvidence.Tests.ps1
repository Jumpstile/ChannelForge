BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Json = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests\fixtures\event-sources\tvmaze-schedule.json') -Raw
    $script:Records = @(InModuleScope ChannelForge -Parameters @{ J = $script:Json } { ConvertFrom-ChannelForgeTvmazeEvidence -Json $J -FetchedAt '2026-11-21T10:00:00Z' })
}

Describe 'TVmaze evidence adapter' {
    It 'gives the local air time in winter (EST)' {
        $script:Records[0].Date | Should -Be '2026-01-14'
        $script:Records[0].Time | Should -Be '20:00'
    }
    It 'gives the same local air time in summer (EDT)' {
        $script:Records[1].Date | Should -Be '2026-07-15'
        $script:Records[1].Time | Should -Be '20:00'
    }
    It 'leaves Time empty when TVmaze has no air time, and marks specials' {
        $script:Records[2].Time | Should -BeNullOrEmpty
        $script:Records[2].Kind | Should -Be 'special'
        $script:Records[0].Kind | Should -Be 'episode'
    }
    It 'carries the credit, license and fetch time' {
        $r = $script:Records[0]
        $r.Name | Should -Be 'Fixture Show: Fixture Winter Night'
        $r.Attribution | Should -Be 'TVmaze'
        $r.License | Should -Be 'CC BY-SA 4.0'
        $r.FetchedAt | Should -Be '2026-11-21T10:00:00Z'
        $r.Id | Should -Be 'tvmaze:900001'
    }
}
