BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
}

Describe 'Build-Lineup.ps1' {
    BeforeAll {
        $script:FixtureRoot = Join-Path $TestDrive 'project'
        $dataDir = Join-Path $script:FixtureRoot 'data'

        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null

        @{
            provider = 'fixture-provider'
            sources  = @(
                @{ name = 'Sports'; group = 'Sports'; url = 'https://example.invalid/iptv/ACCOUNT_ID/API_TOKEN/Sports'; enabled = $true }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding UTF8

        @{
            epg_sources = @(
                @{ name = 'Public EPG'; priority = 10; url = 'https://example.invalid/epg/public/all-sources.xml.gz'; enabled = $true; role = 'primary' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding UTF8

        @{
            locals = @(
                @{ number = 2; station = 'WCBS'; network = 'CBS'; market = 'New York'; display = 'WCBS CBS New York' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding UTF8

        @{
            blocks = @(
                @{ start = 100; end = 199; category = 'Sports'; notes = 'fixture block' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding UTF8

        & $script:ScriptPath -Root $script:FixtureRoot
    }

    It 'writes the build summary report inside output/' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        Test-Path -LiteralPath $summaryPath -PathType Leaf | Should -BeTrue
    }

    It 'reports M3U and XMLTV as not generated' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json

        $summary.M3UGenerated | Should -BeFalse
        $summary.XMLTVGenerated | Should -BeFalse
        $summary.Status | Should -Be 'SOURCE_OF_TRUTH_VALIDATED'
    }

    It 'does not claim output files exist that were never generated' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        $raw = Get-Content -LiteralPath $summaryPath -Raw

        $raw | Should -Not -Match 'merged\.m3u'
        $raw | Should -Not -Match 'merged\.xmltv'
    }

    It 'notes in the human-readable plan that output generation is not implemented' {
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'
        $plan = Get-Content -LiteralPath $planPath -Raw

        $plan | Should -Match 'not implemented yet'
    }

    It 'does not leak full provider or EPG URLs into the human-readable report' {
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'
        $plan = Get-Content -LiteralPath $planPath -Raw

        $plan | Should -Not -Match 'https?://'
        $plan | Should -Not -Match 'example\.invalid'
    }

    It 'does not leak token- or account-shaped values into the human-readable report' {
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'
        $plan = Get-Content -LiteralPath $planPath -Raw

        $plan | Should -Not -Match 'ACCOUNT_ID'
        $plan | Should -Not -Match 'API_TOKEN'
    }

    It 'still identifies provider sources by name and enabled state without their URLs' {
        $planPath = Join-Path $script:FixtureRoot 'output\reports\lineup-plan.md'
        $plan = Get-Content -LiteralPath $planPath -Raw

        $plan | Should -Match 'Sports \(enabled\)'
    }

    It 'does not leak full provider or EPG URLs into the machine-readable summary' {
        $summaryPath = Join-Path $script:FixtureRoot 'output\reports\build-summary.json'
        $raw = Get-Content -LiteralPath $summaryPath -Raw

        $raw | Should -Not -Match 'https?://'
        $raw | Should -Not -Match 'ACCOUNT_ID'
        $raw | Should -Not -Match 'API_TOKEN'
    }

    It 'throws when a required source file is missing' {
        $brokenRoot = Join-Path $TestDrive 'broken-project'
        New-Item -ItemType Directory -Force -Path (Join-Path $brokenRoot 'data\providers') | Out-Null

        { & $script:ScriptPath -Root $brokenRoot } | Should -Throw
    }
}
