BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Dir = Join-Path ([IO.Path]::GetTempPath()) ('cf-sched-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Dir)
    $records = @(
        @{ id = 'r1'; sport = 'Football'; home = 'Dallas Cowboys'; away = 'New York Giants'; date = '2026-11-15'; startUtc = '2026-11-15T12:00:00Z'; source = 'removed.example.invalid'; seen = '2026-11-10T09:00:00Z' }
        @{ id = 'r2'; sport = 'Baseball'; home = 'Los Angeles Dodgers'; away = 'Detroit Tigers'; date = '2026-11-16'; startUtc = $null; source = 'schedule.example.invalid'; seen = '2026-11-10T09:00:00Z' }
    )
    @{ records = $records } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:Dir 'evidence.json')
    function Get-Answer {
        param([string]$Title, [string]$Day = '2026-11-15', [string]$Channel = 'NFL 1', [switch]$NoBlock, [switch]$NoEvidence)
        $blocks = @(if (-not $NoBlock) { @([pscustomobject]@{ Start = [datetime]::Parse("${Day}T12:00:00Z").ToUniversalTime(); Stop = [datetime]::Parse("${Day}T15:00:00Z").ToUniversalTime(); Title = $Title }) })
        $path = Join-Path $script:Dir $(if ($NoEvidence) { 'missing.json' } else { 'evidence.json' })
        InModuleScope ChannelForge -Parameters @{ C = $Channel; B = [object[]]$blocks; P = $path; D = $Day; N = [bool]$NoBlock } {
            $ev = @(Read-ChannelForgeScheduleEvidence -Path $P)
            $args2 = @{ Channel = [pscustomobject]@{ Name = $C; Blocks = $B }; Evidence = $ev }
            if ($N) { $args2.Date = [datetime]::Parse($D) }
            Compare-ChannelForgeScheduleEvidence @args2
        }
    }
}
AfterAll { Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Schedule evidence check' {
    It 'asks nothing when guide and schedule agree, even from a removed source' {
        $r = Get-Answer -Title 'Giants vs Cowboys'
        $r.Status | Should -Be 'Confirmed'
        $r.Question | Should -BeNullOrEmpty
    }
    It 'asks one plain question when the schedule has no game for these teams' {
        $r = Get-Answer -Title 'Dodgers vs Tigers' -Channel 'Baseball 1'
        $r.Status | Should -Be 'NoEvidence'
        $r.Question | Should -Be 'Schedule has no game for Los Angeles Dodgers and Detroit Tigers on 2026-11-15. Keep the guide as is, or mark it cancelled?'
    }
    It 'asks one question when the schedule has a game and the guide has none' {
        $r = Get-Answer -NoBlock
        $r.Status | Should -Be 'GuideMissing'
        @($r.Question).Count | Should -Be 1
        $r.Question | Should -BeLike '*the guide has none*'
    }
    It 'sends a team name with no sport context to review and names no team' {
        $r = Get-Answer -Title 'Giants vs Tigers' -Channel 'Sports 1'
        $r.Status | Should -Be 'Review'
        $r.Question | Should -BeLike "*Cannot tell which team 'Giants'*"
    }
    It 'asks nothing when there is no evidence file' {
        Get-Answer -Title 'Giants vs Cowboys' -NoEvidence | Should -BeNullOrEmpty
    }
}

Describe 'Schedule evidence kinds' {
    It 'defaults old records to a game and reads non-game kinds by name' {
        $path = Join-Path $script:Dir 'kinds.json'
        @{ records = @(
                @{ id = 'a'; sport = 'Football'; home = 'Dallas Cowboys'; away = 'New York Giants'; date = '2026-11-15' }
                @{ id = 'b'; kind = 'special'; name = 'Fixture Showdown'; date = '2026-08-27' }
                @{ id = 'c'; kind = 'special'; date = '2026-08-27' }
            ) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
        $rows = @(InModuleScope ChannelForge -Parameters @{ P = $path } { Read-ChannelForgeScheduleEvidence -Path $P })
        $rows.Count | Should -Be 2
        $rows[0].Kind | Should -Be 'game'
        $rows[0].Name | Should -Be 'New York Giants at Dallas Cowboys'
        $rows[1].Kind | Should -Be 'special'
        $rows[1].Name | Should -Be 'Fixture Showdown'
    }
    It 'keeps time, venue, city and source details, and leaves them empty on old records' {
        $path = Join-Path $script:Dir 'details.json'
        @{ records = @(
                @{ id = 'd'; kind = 'special'; name = 'Fixture Showdown'; date = '2026-08-27'; time = '20:00'; venue = 'Fixture Arena'; city = 'Testville, ST'; source = 'fixture'; license = 'CC BY-SA 4.0'; attribution = 'Fixture'; fetchedAt = '2026-11-21T10:00:00Z'; revision = '99' }
                @{ id = 'a'; sport = 'Football'; home = 'Dallas Cowboys'; away = 'New York Giants'; date = '2026-11-15' }
            ) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
        $rows = @(InModuleScope ChannelForge -Parameters @{ P = $path } { Read-ChannelForgeScheduleEvidence -Path $P })
        $rows[0].Time | Should -Be '20:00'
        $rows[0].Venue | Should -Be 'Fixture Arena'
        $rows[0].City | Should -Be 'Testville, ST'
        $rows[0].License | Should -Be 'CC BY-SA 4.0'
        $rows[0].FetchedAt | Should -Be '2026-11-21T10:00:00Z'
        $rows[0].Revision | Should -Be '99'
        $rows[1].Venue | Should -BeNullOrEmpty
        $rows[1].Revision | Should -BeNullOrEmpty
    }
}
