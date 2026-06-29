BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Validate-ScriptAnalyzer.ps1'
}

Describe 'Validate-ScriptAnalyzer.ps1' {
    It 'does not throw against the real src/ and scripts/ trees (no Error-severity findings today)' {
        { & $script:ScriptPath -Root $RepoRoot } | Should -Not -Throw
    }

    It 'throws when a file has an Error-severity finding' {
        $fixturePath = Join-Path $RepoRoot 'tests\fixtures\analyzer'

        { & $script:ScriptPath -Root $RepoRoot -Paths @($fixturePath) } | Should -Throw '*Error-severity*'
    }
}
