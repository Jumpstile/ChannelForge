BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $RepoRoot 'scripts\Validate-MarkdownLinks.ps1'
}

Describe 'Validate-MarkdownLinks.ps1' {
    It 'does not throw against every tracked Markdown file in the repository' {
        { & $script:ScriptPath -Root $RepoRoot } | Should -Not -Throw
    }

    It 'passes a fixture file whose relative link resolves' {
        { & $script:ScriptPath -Root $RepoRoot -Files @('tests/fixtures/markdown/clean.md') } | Should -Not -Throw
    }

    It 'rejects a fixture file with a relative link to a file that does not exist' {
        { & $script:ScriptPath -Root $RepoRoot -Files @('tests/fixtures/markdown/broken-link.md') } |
            Should -Throw '*broken-link.md*'
    }

    It 'ignores external http(s) links without making a network call' {
        $tempFile = Join-Path $TestDrive 'external-link.md'
        Set-Content -LiteralPath $tempFile -Value '[external](https://example.invalid/does-not-matter)'

        { & $script:ScriptPath -Root $TestDrive -Files @('external-link.md') } | Should -Not -Throw
    }
}
