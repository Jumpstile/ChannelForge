param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    # Relative paths to check, rooted at $Root. Defaults to every Git-tracked
    # .md file. Exposed so tests can point this at fixture files without
    # needing a real Git working tree.
    [string[]]$Files
)

$ErrorActionPreference = "Stop"

# Regression guard for the malformed-documentation incident (see
# LESSONS_LEARNED.md and issues #2/#13/#16): docs were once committed as a
# literal PowerShell heredoc generator script, or with every Markdown
# special character backslash-escaped, instead of rendered Markdown. This
# is a narrow, deterministic check for those two specific failure shapes,
# not a general Markdown style linter. A broader linter would surface many
# pre-existing, unrelated style differences across docs/ and is
# deliberately not attempted here (see DEVELOPER_GUIDE.md).
$trackedMarkdown = $Files
if (-not $trackedMarkdown) {
    Push-Location -LiteralPath $Root
    try {
        # Exclude tests/fixtures: it deliberately contains malformed Markdown
        # fixtures for this script's own test suite.
        $trackedMarkdown = @(git ls-files '*.md' ':!tests/fixtures/**')
    }
    finally {
        Pop-Location
    }
}

$escapedPunctuationPattern = '\\[#*_.\[\]>-]'
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($relativePath in $trackedMarkdown) {
    $path = Join-Path $Root $relativePath
    $content = Get-Content -LiteralPath $path -Raw

    if ($content -match $escapedPunctuationPattern) {
        $failures.Add("${relativePath}: contains backslash-escaped Markdown punctuation (looks like an unrendered generator artifact)")
    }

    if ($content -match "@'" -and $content -match 'Set-Content') {
        $failures.Add("${relativePath}: contains a literal PowerShell heredoc/Set-Content pattern (looks like a generator script committed instead of its output)")
    }
}

if ($failures.Count -gt 0) {
    $detail = ($failures | ForEach-Object { " - $_" }) -join "`n"
    throw "Markdown hygiene check failed for $($failures.Count) file(s):`n$detail"
}

Write-Host "All tracked Markdown files passed the hygiene check ($($trackedMarkdown.Count) files checked)." -ForegroundColor Green
