BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Profile = Join-Path $script:RepoRoot 'tests\fixtures\event-sources\legacy-layout-profile.json'
    function Convert-Text {
        param([string]$Text)
        InModuleScope ChannelForge -Parameters @{ T = $Text; P = $script:Profile } { ConvertFrom-ChannelForgeWikipediaEvidence -Text $T -ProfilePath $P -Revision '1' -FetchedAt 'x' }
    }
}

Describe 'Wikipedia page no longer fits its profile' {
    It 'says the page changed when a column is renamed, and returns no records' {
        $r = Convert-Text '<table class="wikitable"><tr><th>When</th><th>Event</th><th>Venue</th><th>City</th></tr><tr><td>May 1, 2026</td><td>X</td><td>V</td><td>C</td></tr></table>'
        $r.Status | Should -Be 'PageChanged'
        $r.Reason | Should -BeLike "*column 'Date'*"
        @($r.Records).Count | Should -Be 0
    }
    It 'says the page changed when the table is missing' {
        (Convert-Text '<p>No tables here.</p>').Status | Should -Be 'PageChanged'
    }
    It 'says the page changed when rows span rows, rather than misreading columns' {
        $r = Convert-Text '<table class="wikitable"><tr><th>Date</th><th>Event</th><th>Venue</th><th>City</th></tr><tr><td>May 1, 2026</td><td>X</td><td rowspan="2">V</td><td>C</td></tr></table>'
        $r.Status | Should -Be 'PageChanged'
    }
    It 'says the page changed when no row has a readable date' {
        (Convert-Text '<table class="wikitable"><tr><th>Date</th><th>Event</th><th>Venue</th><th>City</th></tr><tr><td>TBA</td><td>X</td><td>V</td><td>C</td></tr></table>').Status | Should -Be 'PageChanged'
    }
    It 'says the page changed when merged cells leave rows of different width' {
        $r = Convert-Text '<table class="wikitable"><tr><th>Date</th><th>Event</th><th>Venue</th><th>City</th></tr><tr><td>May 1, 2026</td><td colspan="3">X</td><td>C</td></tr></table>'
        $r.Status | Should -Be 'PageChanged'
        $r.Reason | Should -Not -BeNullOrEmpty
    }
}
