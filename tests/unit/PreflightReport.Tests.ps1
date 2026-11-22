BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'src/ChannelForge/ChannelForge.psd1') -Force

    . (Join-Path $PSScriptRoot 'PreflightFixture.ps1')
    function Get-Snapshot([string]$Root) { @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object { '{0}|{1}' -f $_.FullName, $(if ($_.PSIsContainer) { 'dir' } else { (Get-FileHash -LiteralPath $_.FullName).Hash }) }) }
    function Get-Finding($Report, [string]$Check) { @($Report.Findings | Where-Object { $_.Check -eq $Check }) }
}

Describe 'Get-ChannelForgePreflightReport' {
    It 'passes a healthy project and leaves the roots exactly as they were' {
        $p = New-Project
        Set-Content -LiteralPath (Join-Path $p 'output/reports/keep.txt') -Value 'keep'
        $before = Get-Snapshot $p
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p
        $r.Version | Should -Be 'preflight-report/v1'
        @($r.Findings | Where-Object { $_.Status -eq 'Fail' }).Count | Should -Be 0
        (Get-Finding $r 'OutputRoot writable').Status | Should -Be 'Pass'
        Get-Snapshot $p | Should -Be $before
        Test-Path -LiteralPath (Join-Path $p 'output/reports/.preflight') | Should -BeFalse
    }

    It 'fails a missing root with a next step and does not create it' {
        $p = New-Project
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p -BackupRoot (Join-Path $p 'backups')
        $f = Get-Finding $r 'BackupRoot exists'
        $f.Status | Should -Be 'Fail'
        $f.NextStep | Should -Not -BeNullOrEmpty
        $r.Summary.Overall | Should -Be 'Fail'
        Test-Path -LiteralPath (Join-Path $p 'backups') | Should -BeFalse
    }

    It 'fails a root outside the project' {
        $p = New-Project
        $other = Join-Path $TestDrive 'elsewhere'; New-Item -ItemType Directory -Path $other | Out-Null
        (Get-Finding (Get-ChannelForgePreflightReport -RepositoryRoot $p -OutputRoot $other) 'OutputRoot inside project').Status | Should -Be 'Fail'
    }

    It 'fails an unwritable root and removes nothing of the user''s' {
        $p = New-Project
        New-Item -ItemType File -Path (Join-Path $p 'output/reports/.preflight') | Out-Null
        $f = Get-Finding (Get-ChannelForgePreflightReport -RepositoryRoot $p) 'OutputRoot writable'
        $f.Status | Should -Be 'Fail'
        $f.NextStep | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $p 'output/reports/.preflight') | Should -BeTrue
    }

    It 'fails when the free-space floor is larger than the drive' {
        $p = New-Project
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p -MinimumFreeSpaceMB 1000000000
        (Get-Finding $r 'OutputRoot free space').Status | Should -Be 'Fail'
    }

    It 'fails a root that is a junction' {
        $p = New-Project
        $target = Join-Path $TestDrive 'target'; New-Item -ItemType Directory -Path $target | Out-Null
        $link = Join-Path $p 'linked'
        try { New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null } catch { Set-ItResult -Skipped -Because 'this process cannot create a junction'; return }
        (Get-Finding (Get-ChannelForgePreflightReport -RepositoryRoot $p -OutputRoot $link) 'OutputRoot no link').Status | Should -Be 'Fail'
    }

    It 'reports Unknown, not Pass, when nothing is published yet' {
        $r = Get-ChannelForgePreflightReport -RepositoryRoot (New-Project)
        (Get-Finding $r 'published M3U matches manifest').Status | Should -Be 'Unknown'
        (Get-Finding $r 'published XMLTV matches manifest').Status | Should -Be 'Unknown'
        $r.Summary.Overall | Should -Be 'Unknown'
    }

    It 'passes matching published files and fails a changed byte' {
        $p = New-Project
        $generation = Publish-Fixture $p
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p
        (Get-Finding $r 'published M3U matches manifest').Status | Should -Be 'Pass'
        (Get-Finding $r 'published XMLTV matches manifest').Status | Should -Be 'Pass'
        $m3u = Join-Path $generation 'merged.m3u'
        Set-ItemProperty -LiteralPath $m3u -Name IsReadOnly -Value $false
        [IO.File]::AppendAllText($m3u, 'x')
        $r = Get-ChannelForgePreflightReport -RepositoryRoot $p
        (Get-Finding $r 'published M3U matches manifest').Status | Should -Be 'Fail'
        $r.Summary.Overall | Should -Be 'Fail'
    }
}
