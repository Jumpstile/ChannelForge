BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Validate-ConfigSchemas.ps1'
}

Describe 'Validate-ConfigSchemas.ps1' {
    It 'does not throw against the real tracked config files' {
        { & $script:ScriptPath -Root $RepoRoot } | Should -Not -Throw
    }

    It 'throws and names the file when a tracked config file fails schema validation' {
        $fixtureRoot = Join-Path $TestDrive 'broken-config'
        $dataDir = Join-Path $fixtureRoot 'data'

        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'providers') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'epg') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'lineup') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dataDir 'rules') | Out-Null

        # Valid copies of everything except the provider file, which is
        # missing the required "enabled" field.
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'data\epg\epg_sources.json') -Destination (Join-Path $dataDir 'epg\epg_sources.json')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'data\epg\epg_sources.example.json') -Destination (Join-Path $dataDir 'epg\epg_sources.example.json')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'data\providers\provider.example.json') -Destination (Join-Path $dataDir 'providers\provider.example.json')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'data\lineup\locals.json') -Destination (Join-Path $dataDir 'lineup\locals.json')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'data\lineup\numbering_blocks.json') -Destination (Join-Path $dataDir 'lineup\numbering_blocks.json')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'data\lineup\categories.json') -Destination (Join-Path $dataDir 'lineup\categories.json')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'data\rules\aliases.json') -Destination (Join-Path $dataDir 'rules\aliases.json')
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests\fixtures\provider-schema-invalid.json') -Destination (Join-Path $dataDir 'providers\mybunny.json')

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw '*mybunny.json*'
    }

    It 'throws and names the file when a tracked config file is missing' {
        $fixtureRoot = Join-Path $TestDrive 'missing-config'
        New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRoot 'data') | Out-Null

        { & $script:ScriptPath -Root $fixtureRoot } | Should -Throw '*Missing tracked config file*'
    }
}
