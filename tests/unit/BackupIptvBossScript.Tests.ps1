BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Backup-IPTVBoss.ps1'
}

Describe 'Backup-IPTVBoss.ps1' {
    It 'throws and writes nothing when the source data path is missing' {
        $fixtureRoot = Join-Path $TestDrive 'missing-source'
        $missingSource = Join-Path $TestDrive 'missing-source\iptvboss-data'

        { & $script:ScriptPath -Root $fixtureRoot -IPTVBossData $missingSource } | Should -Throw '*IPTVBoss data path*'

        Test-Path -LiteralPath (Join-Path $fixtureRoot 'backups') | Should -BeFalse
    }

    It 'creates a backup archive inside backups/ when the source exists' {
        $fixtureRoot = Join-Path $TestDrive 'happy-path'
        $source = Join-Path $fixtureRoot 'iptvboss-data'
        New-Item -ItemType Directory -Force -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'sample.db') -Value 'fixture data'

        & $script:ScriptPath -Root $fixtureRoot -IPTVBossData $source

        $archives = @(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'backups') -Filter 'iptvboss-data-*.tar.gz')
        $archives.Count | Should -Be 1
    }

    It 'refuses to overwrite an existing archive without -Force' {
        $fixtureRoot = Join-Path $TestDrive 'no-overwrite'
        $source = Join-Path $fixtureRoot 'iptvboss-data'
        New-Item -ItemType Directory -Force -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'sample.db') -Value 'fixture data'

        # Use a fixed timestamp so the second run deterministically collides
        # with the first, instead of depending on both runs landing in the
        # same wall-clock second.
        $fixedStamp = '20260101-000000'

        & $script:ScriptPath -Root $fixtureRoot -IPTVBossData $source -Timestamp $fixedStamp

        { & $script:ScriptPath -Root $fixtureRoot -IPTVBossData $source -Timestamp $fixedStamp } | Should -Throw '*already exists*'
    }

    It 'allows overwriting an existing archive with -Force' {
        $fixtureRoot = Join-Path $TestDrive 'forced-overwrite'
        $source = Join-Path $fixtureRoot 'iptvboss-data'
        New-Item -ItemType Directory -Force -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'sample.db') -Value 'fixture data'

        $fixedStamp = '20260101-000000'

        & $script:ScriptPath -Root $fixtureRoot -IPTVBossData $source -Timestamp $fixedStamp

        { & $script:ScriptPath -Root $fixtureRoot -IPTVBossData $source -Timestamp $fixedStamp -Force } | Should -Not -Throw
    }
}
