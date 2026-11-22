BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Fix = Join-Path $script:RepoRoot 'tests\fixtures\event-sources'
    $script:Profile = Join-Path $script:RepoRoot 'tests\fixtures\event-sources\legacy-layout-profile.json'
    function Convert-Page {
        param([string]$File, [string]$Profile = $script:Profile)
        $text = Get-Content -LiteralPath (Join-Path $script:Fix $File) -Raw
        InModuleScope ChannelForge -Parameters @{ T = $text; P = $Profile } { ConvertFrom-ChannelForgeWikipediaEvidence -Text $T -ProfilePath $P -Revision '1234567' -FetchedAt '2026-11-21T10:00:00Z' }
    }
}

Describe 'Wikipedia evidence adapter' {
    It 'reads an HTML table with the profile, skips a TBA row and leaves Time empty' {
        $r = Convert-Page 'wikipedia-sample.html'
        $r.Status | Should -Be 'Ok'
        $r.Skipped | Should -Be 1
        @($r.Records).Count | Should -Be 2
        $r.Records[0].Name | Should -Be 'Fixture Showdown'
        $r.Records[0].Date | Should -Be '2026-08-27'
        $r.Records[0].Venue | Should -Be 'Fixture Arena'
        $r.Records[0].City | Should -Be 'Testville, ST'
        $r.Records[0].Time | Should -BeNullOrEmpty
        $r.Records[1].Name | Should -Be 'Fixture Finale & More'
        $r.Records[1].Date | Should -Be '2026-10-03'
    }
    It 'reads the same facts from wikitext' {
        $r = Convert-Page 'wikipedia-sample.wikitext'
        $r.Status | Should -Be 'Ok'
        @($r.Records).Count | Should -Be 2
        $r.Records[0].Name | Should -Be 'Fixture Showdown'
        $r.Records[1].Name | Should -Be 'Fixture Finale'
        $r.Records[1].City | Should -Be 'Mockton, ST'
    }
    It 'records page title, revision, fetch time, license and credit' {
        $r = (Convert-Page 'wikipedia-sample.html').Records[0]
        $r.Revision | Should -Be '1234567'
        $r.FetchedAt | Should -Be '2026-11-21T10:00:00Z'
        $r.Attribution | Should -Be 'Wikipedia'
        $r.License | Should -Be 'CC BY-SA 4.0'
        $r.Source | Should -Be 'en.wikipedia.org/wiki/List_of_All_Elite_Wrestling_pay-per-view_events'
        $r.Kind | Should -Be 'special'
    }
    It 'reads a table built from every shipped profile' {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'data\event-profiles') -Filter *.json) {
            $p = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $c = $p.columns
            $html = "<table class=`"wikitable`"><tr><th>$($c.date)</th><th>$($c.name)</th><th>$($c.venue)</th><th>$($c.city)</th></tr><tr><td>May 1, 2026</td><td>Fixture One</td><td>Fixture Hall</td><td>Testville</td></tr></table>"
            $r = InModuleScope ChannelForge -Parameters @{ T = $html; P = $file.FullName } { ConvertFrom-ChannelForgeWikipediaEvidence -Text $T -ProfilePath $P -Revision '1' -FetchedAt 'x' }
            $r.Status | Should -Be 'Ok' -Because $file.Name
            $r.Records[0].Kind | Should -Be $p.kind
        }
    }
    It 'reads merged cells: a spanned cell repeats in each row it covers (HTML)' {
        $html = '<table class="wikitable"><tr><th>Date</th><th>Event</th><th>Venue</th><th>City</th></tr>' +
        '<tr><td>May 1, 2026</td><td>Fixture One</td><td rowspan="2">Fixture Arena</td><td>Testville</td></tr>' +
        '<tr><td>May 2, 2026</td><td>Fixture Two</td><td>Testburg</td></tr>' +
        '<tr><td colspan="2">TBA</td><td>Fixture Hall</td><td>Testton</td></tr></table>'
        $r = InModuleScope ChannelForge -Parameters @{ T = $html; P = $script:Profile } { ConvertFrom-ChannelForgeWikipediaEvidence -Text $T -ProfilePath $P -Revision '1' -FetchedAt 'x' }
        $r.Status | Should -Be 'Ok'
        @($r.Records).Count | Should -Be 2
        $r.Records[0].Venue | Should -Be 'Fixture Arena'
        $r.Records[1].Venue | Should -Be 'Fixture Arena'
        $r.Records[1].City | Should -Be 'Testburg'
        $r.Skipped | Should -Be 1
    }

    It 'reads merged cells from wikitext' {
        $wiki = "{| class=`"wikitable`"`n! Date !! Event !! Venue !! City`n|-`n| May 1, 2026 || Fixture One || rowspan=`"2`" | Fixture Arena || Testville`n|-`n| May 2, 2026 || Fixture Two || Testburg`n|}"
        $r = InModuleScope ChannelForge -Parameters @{ T = $wiki; P = $script:Profile } { ConvertFrom-ChannelForgeWikipediaEvidence -Text $T -ProfilePath $P -Revision '1' -FetchedAt 'x' }
        $r.Status | Should -Be 'Ok'
        $r.Records[1].Venue | Should -Be 'Fixture Arena'
        $r.Records[1].City | Should -Be 'Testburg'
    }
}
