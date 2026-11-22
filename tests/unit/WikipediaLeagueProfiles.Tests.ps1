BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Fix = Join-Path $script:RepoRoot 'tests\fixtures\event-sources'
    function Read-Page {
        param([string]$Html, [string]$Profile)
        $p = Join-Path $script:RepoRoot "data\event-profiles\$Profile.json"
        InModuleScope ChannelForge -Parameters @{ T = $Html; P = $p } { ConvertFrom-ChannelForgeWikipediaEvidence -Text $T -ProfilePath $P -Revision '1' -FetchedAt 'x' }
    }
    function Read-Fixture {
        param([string]$File, [string]$Profile)
        Read-Page -Html (Get-Content -LiteralPath (Join-Path $script:Fix $File) -Raw) -Profile $Profile
    }
}

Describe 'League profiles read year-less dates from their year heading' {
    It 'WWE: reads 2024 rows, repeats the spanned venue, drops the aired note, ignores the 2019 table and the label table' {
        $r = Read-Fixture 'wwe-league-sample.html' 'wwe-pay-per-view'
        $r.Status | Should -Be 'Ok'
        @($r.Records).Count | Should -Be 3
        ($r.Records.Date -join ',') | Should -Be '2024-01-06,2024-01-07,2024-05-04'
        $r.Records[1].Name | Should -Be 'Fixture Rumble Night Two'
        $r.Records[1].Venue | Should -Be 'Fixture Arena'
        $r.Records[1].City | Should -Be 'Testville, ST'
        $r.Records[2].Venue | Should -Be 'Sample Center'
    }
    It 'AEW: reads the live layout (Event first, Location is the city), skips TBA and the Event/Feature table' {
        $r = Read-Fixture 'aew-league-sample.html' 'aew-pay-per-view'
        $r.Status | Should -Be 'Ok'
        ($r.Records.Date -join ',') | Should -Be '2024-05-25,2024-08-31,2027-03-07'
        $r.Records[0].Name | Should -Be 'Fixture Showdown'
        $r.Records[0].Venue | Should -Be 'Fixture Arena'
        $r.Records[0].City | Should -Be 'Testville, ST'
        $r.Skipped | Should -Be 1
    }
    It 'TNA: reads rows when a header cell carries leaked template text and rows lack their last cell' {
        $r = Read-Fixture 'tna-league-sample.html' 'tna-pay-per-view'
        $r.Status | Should -Be 'Ok'
        ($r.Records.Date -join ',') | Should -Be '2023-02-03,2023-02-10,2023-04-08'
        $r.Records[1].City | Should -Be 'Testville, ST'
    }
    It 'NJPW: reads rows, and counts the full-width legend row as skipped' {
        $r = Read-Fixture 'njpw-league-sample.html' 'njpw-major-events'
        $r.Status | Should -Be 'Ok'
        ($r.Records.Date -join ',') | Should -Be '2022-01-04,2022-01-05,2022-05-01'
        $r.Records[1].Venue | Should -Be 'Fixture Dome'
        $r.Skipped | Should -Be 1
    }
    It 'ROH: reads rows and drops the aired note' {
        $r = Read-Fixture 'roh-league-sample.html' 'roh-pay-per-view'
        $r.Status | Should -Be 'Ok'
        ($r.Records.Date -join ',') | Should -Be '2021-03-05,2021-03-20,2021-07-09'
        $r.Records[2].City | Should -Be 'Mockton, ST'
    }
}

Describe 'League profiles never guess' {
    It 'says the page changed, with a reason, when a column is renamed' {
        $html = (Get-Content -LiteralPath (Join-Path $script:Fix 'wwe-league-sample.html') -Raw) -replace '<th>Venue</th>', '<th>Place</th>'
        $r = Read-Page -Html $html -Profile 'wwe-pay-per-view'
        $r.Status | Should -Be 'PageChanged'
        $r.Reason | Should -BeLike "*column 'Venue'*"
        @($r.Records).Count | Should -Be 0
    }
    It 'says the page changed when no table sits under a year in range' {
        $html = (Get-Content -LiteralPath (Join-Path $script:Fix 'roh-league-sample.html') -Raw) -replace '<h3>2021</h3>', '<h3>1999</h3>'
        $r = Read-Page -Html $html -Profile 'roh-pay-per-view'
        $r.Status | Should -Be 'PageChanged'
        $r.Reason | Should -Not -BeNullOrEmpty
    }
    It 'says the page changed when a table in range cannot be read' {
        $html = '<h4>2024</h4><table class="wikitable"><tr><th>Date</th><th>Event</th><th>Venue</th><th>Location</th></tr><tr><td>May 1</td><td>X</td><td rowspan="3">V</td><td>C</td></tr></table>'
        (Read-Page -Html $html -Profile 'wwe-pay-per-view').Status | Should -Be 'PageChanged'
    }
    It 'an older profile without the new fields still skips year-less dates' {
        $html = '<h4>2024</h4><table class="wikitable"><tr><th>Date</th><th>Event</th><th>Venue</th><th>City</th></tr><tr><td>May 1</td><td>X</td><td>V</td><td>C</td></tr></table>'
        $r = InModuleScope ChannelForge -Parameters @{ T = $html; P = (Join-Path $script:Fix 'legacy-layout-profile.json') } { ConvertFrom-ChannelForgeWikipediaEvidence -Text $T -ProfilePath $P -Revision '1' -FetchedAt 'x' }
        $r.Status | Should -Be 'PageChanged'
        $r.Reason | Should -BeLike '*no row had a readable date*'
    }
}

Describe 'Table choice by id or heading' {
    It 'reads the table with the named id, and the table under the named heading' {
        $html = Get-Content -LiteralPath (Join-Path $script:Fix 'wwe-league-sample.html') -Raw
        foreach ($pick in @{ tableId = 'Past_events_2024' }, @{ tableHeading = '2024' }) {
            $profile = Join-Path $TestDrive 'pick.json'
            $body = [ordered]@{ pageTitle = 'Fixture'; yearFrom = 'heading'; kind = 'special'; columns = [ordered]@{ date = 'Date'; name = 'Event'; venue = 'Venue'; city = 'Location' } } + $pick
            $body | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $profile
            $r = InModuleScope ChannelForge -Parameters @{ T = $html; P = $profile } { ConvertFrom-ChannelForgeWikipediaEvidence -Text $T -ProfilePath $P -Revision '1' -FetchedAt 'x' }
            $r.Status | Should -Be 'Ok' -Because ($pick.Keys -join '')
            ($r.Records.Date -join ',') | Should -Be '2024-01-06,2024-01-07,2024-05-04'
        }
    }
}
