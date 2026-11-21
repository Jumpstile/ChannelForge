BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Shows = @(Get-Content -LiteralPath (Join-Path $script:RepoRoot 'data\event-profiles\tvmaze\shows.json') -Raw | ConvertFrom-Json)
    $script:Json = '[{"id":910001,"name":"Fixture Night","type":"regular","airdate":"2026-01-14","airtime":"20:00","airstamp":"2026-01-15T01:00:00+00:00","show":{"name":"Fixture Show"}},{"id":910002,"name":"Fixture Summer","type":"regular","airdate":"2026-07-15","airtime":"20:00","airstamp":"2026-07-16T00:00:00+00:00","show":{"name":"Fixture Show"}}]'
}

Describe 'TVmaze show profiles' {
    It 'lists valid shows with unique ids' {
        $script:Shows.Count | Should -BeGreaterThan 0
        foreach ($s in $script:Shows) {
            $s.showId | Should -BeOfType [long]
            $s.showId | Should -BeGreaterThan 0
            $s.name | Should -Not -BeNullOrEmpty
            $s.trustTimes | Should -BeOfType [bool]
        }
        @($script:Shows.showId | Select-Object -Unique).Count | Should -Be $script:Shows.Count
    }
    It 'does not trust the times of RAW and NJPW Strong' {
        ($script:Shows | Where-Object showId -eq 802).trustTimes | Should -BeFalse
        ($script:Shows | Where-Object showId -eq 50263).trustTimes | Should -BeFalse
    }
    It 'keeps the time when times are trusted, and by default' {
        $r = @(InModuleScope ChannelForge -Parameters @{ J = $script:Json } { ConvertFrom-ChannelForgeTvmazeEvidence -Json $J -FetchedAt 'x' -TrustTimes $true })
        $r.Time | Should -Be @('20:00', '20:00')
        $d = @(InModuleScope ChannelForge -Parameters @{ J = $script:Json } { ConvertFrom-ChannelForgeTvmazeEvidence -Json $J -FetchedAt 'x' })
        $d.Time | Should -Be @('20:00', '20:00')
    }
    It 'keeps date and name but drops the time when times are not trusted' {
        $r = @(InModuleScope ChannelForge -Parameters @{ J = $script:Json } { ConvertFrom-ChannelForgeTvmazeEvidence -Json $J -FetchedAt 'x' -TrustTimes $false })
        $r.Count | Should -Be 2
        $r[0].Time | Should -BeNullOrEmpty
        $r[1].Time | Should -BeNullOrEmpty
        $r[0].Date | Should -Be '2026-01-14'
        $r[1].Name | Should -Be 'Fixture Show: Fixture Summer'
    }
}
