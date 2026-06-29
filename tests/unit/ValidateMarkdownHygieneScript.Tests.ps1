BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Validate-MarkdownHygiene.ps1'
    $script:FixtureDir = Join-Path $RepoRoot 'tests\fixtures\markdown'
}

Describe 'Validate-MarkdownHygiene.ps1' {
    It 'does not throw against every tracked Markdown file in the repository' {
        { & $script:ScriptPath -Root $RepoRoot } | Should -Not -Throw
    }

    It 'passes a clean fixture file' {
        { & $script:ScriptPath -Root $RepoRoot -Files @('tests/fixtures/markdown/clean.md') } | Should -Not -Throw
    }

    It 'rejects a file with backslash-escaped Markdown punctuation' {
        { & $script:ScriptPath -Root $RepoRoot -Files @('tests/fixtures/markdown/escaped-punctuation.md') } |
            Should -Throw '*escaped-punctuation.md*'
    }

    It 'rejects a file containing a literal heredoc/Set-Content generator stub' {
        { & $script:ScriptPath -Root $RepoRoot -Files @('tests/fixtures/markdown/heredoc-stub.md') } |
            Should -Throw '*heredoc-stub.md*'
    }

    It 'excludes tests/fixtures from the default (no -Files) scan, so its own bad fixtures never fail CI' {
        Get-ChildItem -LiteralPath $script:FixtureDir -Filter '*.md' | Should -Not -BeNullOrEmpty
        { & $script:ScriptPath -Root $RepoRoot } | Should -Not -Throw
    }
}
