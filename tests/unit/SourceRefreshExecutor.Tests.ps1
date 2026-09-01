BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Executor = Join-Path $script:Root 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'
}

Describe 'one-shot source refresh executor' {
    It 'reports disabled sources without contacting a source and writes safe reports' {
        $root = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/providers'),(Join-Path $root 'data/epg') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'data/providers/provider.local.json') -Value '{"provider":"fixture","sources":[{"name":"Disabled","url":"https://example.invalid/secret","enabled":false}]}'
        Set-Content -LiteralPath (Join-Path $root 'data/epg/epg_sources.local.json') -Value '{"epg_sources":[]}'
        $result = & $script:Executor -Root $root
        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        $report.Sources[0].Result | Should -Be 'REVIEW_REQUIRED'
        $report.Sources[0].Attempted | Should -BeFalse
        $report.Sources[0].SafeReason | Should -Not -Match 'example.invalid|secret'
        Test-Path $result.MarkdownPath | Should -BeTrue
    }

    It 'does not create accepted-state or generation output' {
        $root = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/providers'),(Join-Path $root 'data/epg') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'data/providers/provider.local.json') -Value '{"provider":"fixture","sources":[]}'
        Set-Content -LiteralPath (Join-Path $root 'data/epg/epg_sources.local.json') -Value '{"epg_sources":[]}'
        $null = & $script:Executor -Root $root
        Test-Path (Join-Path $root 'output/accepted') | Should -BeFalse
        Test-Path (Join-Path $root 'output/generations') | Should -BeFalse
    }

    It 'orders results deterministically and excludes private source details' {
        $root = Join-Path $TestDrive 'ordered-project'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/providers'),(Join-Path $root 'data/epg') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'data/providers/provider.local.json') -Value '{"provider":"fixture","sources":[{"name":"Zulu","url":"https://example.invalid/ACCOUNT_ID/API_TOKEN/z","enabled":false},{"name":"Alpha","url":"https://example.invalid/ACCOUNT_ID/API_TOKEN/a","enabled":false}]}'
        Set-Content -LiteralPath (Join-Path $root 'data/epg/epg_sources.local.json') -Value '{"epg_sources":[{"name":"Guide","url":"https://example.invalid/ACCOUNT_ID/API_TOKEN/g","enabled":false,"role":"primary"}]}'
        $result = & $script:Executor -Root $root
        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        @($report.Sources | ForEach-Object Name) | Should -Be @('Alpha','Zulu','Guide')
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match 'ACCOUNT_ID|API_TOKEN|example.invalid'
    }
}
