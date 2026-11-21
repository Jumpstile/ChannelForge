BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    $script:Dir = Join-Path ([IO.Path]::GetTempPath()) ('cf-import-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:Dir)
    function Invoke-Import {
        param([string[]]$Lines, [string]$Evidence)
        $csv = Join-Path $script:Dir ([guid]::NewGuid().ToString('N') + '.csv')
        Set-Content -LiteralPath $csv -Value $Lines
        InModuleScope ChannelForge -Parameters @{ S = $csv; E = $Evidence } { Import-ChannelForgeScheduleEvidence -SourcePath $S -EvidencePath $E }
    }
}
AfterAll { Remove-Item -LiteralPath $script:Dir -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Schedule importer' {
    It 'saves a user schedule and the schedule check then uses it' {
        $path = Join-Path $script:Dir 'state\schedule-evidence.json'
        $r = Invoke-Import -Evidence $path -Lines @('sport,home,away,date,startUtc', 'Football,Dallas Cowboys,New York Giants,2026-11-15,2026-11-15T18:00:00Z')
        $r.Added | Should -Be 1
        $r.Rejected.Count | Should -Be 0
        $records = @(InModuleScope ChannelForge -Parameters @{ P = $path } { Read-ChannelForgeScheduleEvidence -Path $P })
        $records.Count | Should -Be 1
        $records[0].Home | Should -Be 'Dallas Cowboys'
        $records[0].Source | Should -Be 'user-file'
    }

    It 'replaces a repeated game and keeps other saved records' {
        $path = Join-Path $script:Dir 'keep.json'
        @{ records = @(@{ id = 'old'; sport = 'Baseball'; home = 'A'; away = 'B'; date = '2026-11-10'; startUtc = $null; source = 'x'; seen = '2026-11-01T00:00:00Z' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path
        $lines = @('sport,home,away,date,startUtc', 'Football,Dallas Cowboys,New York Giants,2026-11-15,')
        [void](Invoke-Import -Evidence $path -Lines $lines)
        $r = Invoke-Import -Evidence $path -Lines $lines
        $r.Updated | Should -Be 1
        $r.Added | Should -Be 0
        @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).records).Count | Should -Be 2
    }

    It 'rejects bad rows with a plain message and writes the good ones' {
        $path = Join-Path $script:Dir 'mixed.json'
        $r = Invoke-Import -Evidence $path -Lines @('sport,home,away,date,startUtc', 'Football,Dallas Cowboys,,2026-11-15,', 'Football,Dallas Cowboys,New York Giants,11/15/2026,', 'Football,Dallas Cowboys,New York Giants,2026-11-15,')
        $r.Added | Should -Be 1
        $r.Rejected.Count | Should -Be 2
        $r.Rejected[0] | Should -BeLike 'Row 2:*'
    }

    It 'stops and leaves a damaged evidence file untouched' {
        $path = Join-Path $script:Dir 'damaged.json'
        Set-Content -LiteralPath $path -Value '{ not json'
        { Invoke-Import -Evidence $path -Lines @('sport,home,away,date,startUtc', 'Football,Dallas Cowboys,New York Giants,2026-11-15,') } | Should -Throw '*damaged*'
        (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be '{ not json'
    }
    It 'keeps event details from the CSV in the saved file' {
        $path = Join-Path $script:Dir 'details.json'
        $r = Invoke-Import -Evidence $path -Lines @('kind,name,date,time,venue,city,source,license,attribution,revision', 'special,Fixture Showdown,2026-08-27,20:00,Fixture Arena,"Testville, ST",fixture,CC BY-SA 4.0,Fixture,99')
        $r.Added | Should -Be 1
        $rows = @(InModuleScope ChannelForge -Parameters @{ P = $path } { Read-ChannelForgeScheduleEvidence -Path $P })
        $rows[0].Kind | Should -Be 'special'
        $rows[0].Name | Should -Be 'Fixture Showdown'
        $rows[0].Venue | Should -Be 'Fixture Arena'
        $rows[0].City | Should -Be 'Testville, ST'
        $rows[0].Time | Should -Be '20:00'
        $rows[0].Source | Should -Be 'fixture'
        $rows[0].Revision | Should -Be '99'
        $rows[0].FetchedAt | Should -Not -BeNullOrEmpty
    }

    It 'rejects a non-game row with no name' {
        $r = Invoke-Import -Evidence (Join-Path $script:Dir 'noname.json') -Lines @('kind,name,date', 'special,,2026-08-27')
        $r.Added | Should -Be 0
        $r.Rejected.Count | Should -Be 1
    }
}
