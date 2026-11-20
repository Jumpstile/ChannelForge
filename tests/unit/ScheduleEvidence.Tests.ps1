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
