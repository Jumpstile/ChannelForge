BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Dir = Join-Path ([IO.Path]::GetTempPath()) ('cf-evcache-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Dir)
    function Invoke-Cache {
        param([string]$Op, [hashtable]$Arguments)
        InModuleScope ChannelForge -Parameters @{ Op = $Op; A = $Arguments } {
            if ($Op -eq 'Save') { Save-ChannelForgeEvidenceCache @A } else { Read-ChannelForgeEvidenceCache @A }
        }
    }
    function New-Args {
        param([string]$Name, [string]$Revision = '100', [string]$Status = 'Ok')
        @{ Path = (Join-Path $script:Dir 'cache.json'); Records = @(@{ Name = $Name; Date = '2026-11-20' }); Source = 'schedule.example.invalid'
            Revision = $Revision; FetchedAt = '2026-11-20T10:00:00Z'; Status = $Status }
    }
}
AfterAll { Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Evidence cache' {
    BeforeEach { Get-ChildItem -LiteralPath $script:Dir | Remove-Item -Force }

    It 'reads Missing when nothing was saved' {
        (Invoke-Cache Read @{ Path = (Join-Path $script:Dir 'cache.json') }).Status | Should -Be 'Missing'
    }
    It 'saves then reads Fresh, then Stale after expiry (records still returned)' {
        (Invoke-Cache Save (New-Args 'Match A')).Status | Should -Be 'Saved'
        $path = Join-Path $script:Dir 'cache.json'
        $fresh = Invoke-Cache Read @{ Path = $path; Now = [datetime]'2026-11-20T20:00:00Z' }
        $fresh.Status | Should -Be 'Fresh'
        $fresh.Records[0].Name | Should -Be 'Match A'
        $fresh.Revision | Should -Be '100'
        $stale = Invoke-Cache Read @{ Path = $path; Now = [datetime]'2026-11-22T10:00:00Z' }
        $stale.Status | Should -Be 'Stale'
        $stale.Records[0].Name | Should -Be 'Match A'
        (Invoke-Cache Read @{ Path = $path; Now = [datetime]'2026-11-22T10:00:00Z'; MaxAge = [timespan]::FromDays(7) }).Status | Should -Be 'Fresh'
    }
    It 'reports Corrupt, never throws' {
        $path = Join-Path $script:Dir 'cache.json'
        Set-Content -LiteralPath $path -Value '{ not json'
        $r = Invoke-Cache Read @{ Path = $path }
        $r.Status | Should -Be 'Corrupt'
        $r.Reason | Should -Not -BeNullOrEmpty
    }
    It 'leaves the cache untouched after a failed fetch' {
        [void](Invoke-Cache Save (New-Args 'Match A'))
        $path = Join-Path $script:Dir 'cache.json'
        $before = (Get-FileHash -LiteralPath $path).Hash
        (Invoke-Cache Save (New-Args 'Bad' '200' 'PageChanged')).Status | Should -Be 'Skipped'
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
        @(Get-ChildItem -LiteralPath $script:Dir).Count | Should -Be 1
    }
    It 'keeps the previous good set as last-known-good on a new Ok save' {
        [void](Invoke-Cache Save (New-Args 'Match A' '100'))
        [void](Invoke-Cache Save (New-Args 'Match B' '200'))
        $now = [datetime]'2026-11-20T11:00:00Z'
        $current = Invoke-Cache Read @{ Path = (Join-Path $script:Dir 'cache.json'); Now = $now }
        $lkg = Invoke-Cache Read @{ Path = (Join-Path $script:Dir 'cache.json.lkg'); Now = $now }
        $current.Records[0].Name | Should -Be 'Match B'
        $lkg.Records[0].Name | Should -Be 'Match A'
        $lkg.Revision | Should -Be '100'
    }
    It 'does not replace last-known-good with a corrupt current file' {
        [void](Invoke-Cache Save (New-Args 'Match A' '100'))
        [void](Invoke-Cache Save (New-Args 'Match B' '200'))
        Set-Content -LiteralPath (Join-Path $script:Dir 'cache.json') -Value 'garbage'
        [void](Invoke-Cache Save (New-Args 'Match C' '300'))
        (Invoke-Cache Read @{ Path = (Join-Path $script:Dir 'cache.json.lkg'); Now = [datetime]'2026-11-20T11:00:00Z' }).Records[0].Name | Should -Be 'Match A'
    }
}
