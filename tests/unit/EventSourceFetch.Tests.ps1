BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Fix = Join-Path $script:RepoRoot 'tests\fixtures\event-sources'
    $script:Profile = Join-Path $script:RepoRoot 'tests\fixtures\event-sources\legacy-layout-profile.json'
    $script:Dir = Join-Path ([IO.Path]::GetTempPath()) ('cf-fetch-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Dir)
    $html = Get-Content -LiteralPath (Join-Path $script:Fix 'wikipedia-sample.html') -Raw
    $script:WikiReply = @{ parse = @{ title = 'x'; revid = 987654; text = $html } } | ConvertTo-Json -Depth 4
    $script:TvReply = Get-Content -LiteralPath (Join-Path $script:Fix 'tvmaze-schedule.json') -Raw
    $script:Show = [pscustomobject]@{ showId = 5001; name = 'Fixture Show'; kind = 'episode'; trustTimes = $true }
    function Invoke-Source {
        param([hashtable]$Arguments, [scriptblock]$Fetch)
        InModuleScope ChannelForge -Parameters @{ A = $Arguments; F = $Fetch } { Get-ChannelForgeEventSourceEvidence @A -Fetch $F -FetchedAt '2026-11-21T10:00:00Z' }
    }
    function Read-Saved([string]$Path) { @((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String).records) }
}
AfterAll { Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Event source fetch' {
    It 'turns a Wikipedia page into saved evidence with revision, fetch time, license and credit' {
        $path = Join-Path $script:Dir 'wiki\schedule-evidence.json'
        $calls = [System.Collections.Generic.List[string]]::new()
        $reply = $script:WikiReply
        $r = Invoke-Source @{ ProfilePath = $script:Profile; EvidencePath = $path } { param($Url) $calls.Add($Url); $reply }.GetNewClosure()
        $r.Status | Should -Be 'Ok'
        $r.Written | Should -Be 2
        $calls.Count | Should -Be 1
        $calls[0] | Should -BeLike 'https://en.wikipedia.org/w/api.php?*page=List%20of%20All%20Elite%20Wrestling%20pay-per-view%20events'
        $saved = Read-Saved $path
        $saved.Count | Should -Be 2
        $saved[0].name | Should -Be 'Fixture Showdown'
        $saved[0].date | Should -Be '2026-08-27'
        $saved[0].revision | Should -Be '987654'
        $saved[0].fetchedAt | Should -Be '2026-11-21T10:00:00Z'
        $saved[0].license | Should -Be 'CC BY-SA 4.0'
        $saved[0].attribution | Should -Be 'Wikipedia'
        $saved[0].source | Should -Be 'en.wikipedia.org/wiki/List_of_All_Elite_Wrestling_pay-per-view_events'
        @(InModuleScope ChannelForge -Parameters @{ P = $path } { Read-ChannelForgeScheduleEvidence -Path $P }).Count | Should -Be 2
    }

    It 'turns a TVmaze episode list into saved evidence with the request identity' {
        $path = Join-Path $script:Dir 'tv\schedule-evidence.json'
        $calls = [System.Collections.Generic.List[string]]::new()
        $reply = $script:TvReply
        $r = Invoke-Source @{ Show = $script:Show; EvidencePath = $path } { param($Url) $calls.Add($Url); $reply }.GetNewClosure()
        $r.Status | Should -Be 'Ok'
        @($calls) | Should -Be @('https://api.tvmaze.com/shows/5001/episodes')
        $saved = Read-Saved $path
        $saved.Count | Should -Be 3
        $saved[0].name | Should -Be 'Fixture Show: Fixture Winter Night'
        $saved[0].time | Should -Be '20:00'
        $saved[0].attribution | Should -Be 'TVmaze'
        $saved[0].license | Should -Be 'CC BY-SA 4.0'
        $saved[0].fetchedAt | Should -Be '2026-11-21T10:00:00Z'
        $saved[0].revision | Should -Be 'api.tvmaze.com/shows/5001/episodes'
    }

    It 'keeps the previous file unchanged when the transport fails' {
        $path = Join-Path $script:Dir 'fail.json'
        Copy-Item -LiteralPath (Join-Path $script:Dir 'wiki\schedule-evidence.json') -Destination $path
        $before = (Get-FileHash -LiteralPath $path).Hash
        $r = Invoke-Source @{ ProfilePath = $script:Profile; EvidencePath = $path } { param($Url) throw 'network down' }
        $r.Status | Should -Be 'FetchFailed'
        $r.Records.Count | Should -Be 0
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
    }

    It 'keeps the previous file unchanged and says why when the page layout changed' {
        $path = Join-Path $script:Dir 'changed.json'
        Copy-Item -LiteralPath (Join-Path $script:Dir 'wiki\schedule-evidence.json') -Destination $path
        $before = (Get-FileHash -LiteralPath $path).Hash
        $changed = @{ parse = @{ revid = 5; text = '<table class="wikitable"><tr><th>When</th><th>What</th></tr><tr><td>x</td><td>y</td></tr></table>' } } | ConvertTo-Json -Depth 4
        $r = Invoke-Source @{ ProfilePath = $script:Profile; EvidencePath = $path } { param($Url) $changed }.GetNewClosure()
        $r.Status | Should -Be 'PageChanged'
        $r.Reason | Should -Not -BeNullOrEmpty
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
        $r = Invoke-Source @{ Show = $script:Show; EvidencePath = $path } { param($Url) 'not json' }
        $r.Status | Should -Be 'PageChanged'
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
    }
}
