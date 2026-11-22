BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $fix = Join-Path $script:RepoRoot 'tests\fixtures\event-sources'
    $script:Dir = Join-Path ([IO.Path]::GetTempPath()) ('cf-refresh-' + [guid]::NewGuid().ToString('N'))
    $script:Profiles = Join-Path $script:Dir 'profiles'
    [void](New-Item -ItemType Directory -Path (Join-Path $script:Profiles 'tvmaze') -Force)
    Copy-Item -LiteralPath (Join-Path $fix 'legacy-layout-profile.json') -Destination (Join-Path $script:Profiles 'fixture-wiki.json')
    '[{"showId":5001,"name":"Fixture Show","kind":"episode","trustTimes":true}]' | Set-Content -LiteralPath (Join-Path $script:Profiles 'tvmaze\shows.json')
    $html = Get-Content -LiteralPath (Join-Path $fix 'wikipedia-sample.html') -Raw
    $script:WikiReply = @{ parse = @{ title = 'x'; revid = 987654; text = $html } } | ConvertTo-Json -Depth 4
    $script:TvReply = Get-Content -LiteralPath (Join-Path $fix 'tvmaze-schedule.json') -Raw
    function New-Cache { Join-Path $script:Dir ('cache-' + [guid]::NewGuid().ToString('N')) }
    function New-Fetch([string]$Wiki, [string]$Tv, $Calls) {
        { param($Url) $Calls.Add($Url); if ($Url -like '*wikipedia*') { $Wiki } else { $Tv } }.GetNewClosure()
    }
    function Invoke-Refresh([string]$Cache, [scriptblock]$Fetch, [hashtable]$Extra = @{}) {
        Update-ChannelForgeEventEvidence -ProfileDirectory $script:Profiles -CacheDirectory $Cache -Fetch $Fetch @Extra
    }
}
AfterAll { Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Update-ChannelForgeEventEvidence' {
    It 'fetches every source and writes one cache file each' {
        $cache = New-Cache; $calls = [System.Collections.Generic.List[string]]::new()
        $r = @(Invoke-Refresh $cache (New-Fetch $script:WikiReply $script:TvReply $calls))
        $r.Name | Should -Be @('fixture-wiki', 'Fixture Show')
        $r.Status | Should -Be @('Refreshed', 'Refreshed')
        $r.Kind | Should -Be @('Wikipedia', 'TVmaze')
        $r[0].RecordCount | Should -Be 2
        $r[1].RecordCount | Should -Be 3
        Test-Path -LiteralPath $r[0].CachePath | Should -BeTrue
        $r[1].CachePath | Should -BeLike '*tvmaze-5001.json'
        (Get-Content -LiteralPath $r[1].CachePath -Raw | ConvertFrom-Json).records.Count | Should -Be 3
    }

    It 'skips a fresh cache and refetches with -Force' {
        $cache = New-Cache; $calls = [System.Collections.Generic.List[string]]::new()
        $fetch = New-Fetch $script:WikiReply $script:TvReply $calls
        [void](Invoke-Refresh $cache $fetch)
        $calls.Clear()
        $second = @(Invoke-Refresh $cache $fetch)
        $second.Status | Should -Be @('SkippedFresh', 'SkippedFresh')
        $calls.Count | Should -Be 0
        $forced = @(Invoke-Refresh $cache $fetch @{ Force = $true })
        $forced.Status | Should -Be @('Refreshed', 'Refreshed')
        $calls.Count | Should -Be 2
    }

    It 'reports a changed page plainly and leaves the cache untouched' {
        $cache = New-Cache; $calls = [System.Collections.Generic.List[string]]::new()
        [void](Invoke-Refresh $cache (New-Fetch $script:WikiReply $script:TvReply $calls) @{ Source = 'fixture-wiki' })
        $path = Join-Path $cache 'wikipedia-fixture-wiki.json'
        $before = (Get-FileHash -LiteralPath $path).Hash
        $bad = @{ parse = @{ title = 'x'; revid = 1; text = '<p>nothing here</p>' } } | ConvertTo-Json
        $r = @(Invoke-Refresh $cache (New-Fetch $bad '' $calls) @{ Source = 'fixture-wiki'; Force = $true })
        $r.Status | Should -Be 'PageChanged'
        $r.Reason | Should -Not -BeNullOrEmpty
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
        Test-Path -LiteralPath "$path.lkg" | Should -BeFalse
    }

    It 'reports a failed fetch and writes nothing' {
        $cache = New-Cache
        $r = @(Invoke-Refresh $cache { param($Url) throw 'offline' } @{ Source = 'Fixture Show' })
        $r.Status | Should -Be 'FetchFailed'
        Test-Path -LiteralPath $cache | Should -BeFalse
    }

    It 'with -WhatIf fetches nothing and writes nothing' {
        $cache = New-Cache; $calls = [System.Collections.Generic.List[string]]::new()
        $r = @(Invoke-Refresh $cache (New-Fetch $script:WikiReply $script:TvReply $calls) @{ WhatIf = $true })
        $r.Status | Should -Be @('WouldFetch', 'WouldFetch')
        $calls.Count | Should -Be 0
        Test-Path -LiteralPath $cache | Should -BeFalse
    }

    It 'gives a clear error for an unknown -Source' {
        $calls = [System.Collections.Generic.List[string]]::new()
        { Invoke-Refresh (New-Cache) (New-Fetch '' '' $calls) @{ Source = 'Nope' } } | Should -Throw '*Unknown source: Nope*Fixture Show*'
        $calls.Count | Should -Be 0
    }
}
