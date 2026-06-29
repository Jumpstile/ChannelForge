param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    # Relative paths to check, rooted at $Root. Defaults to every Git-tracked
    # .md file. Exposed so tests can point this at fixture files without
    # needing a real Git working tree.
    [string[]]$Files
)

$ErrorActionPreference = "Stop"

# Deterministic relative-link checker for tracked Markdown files. This
# intentionally:
# - Only checks relative file links (e.g. "[x](docs/foo.md)"). It does not
#   fetch http(s)/mailto links, so it never depends on network access and
#   can't be flaky in CI.
# - Strips and ignores any "#anchor" fragment rather than trying to confirm
#   the heading exists. Resolving an anchor correctly requires replicating
#   the renderer's exact heading-to-slug rule, which is a common source of
#   false positives; checking only that the target *file* exists is the
#   reliable, low-noise version of this check (see DEVELOPER_GUIDE.md).
$trackedMarkdown = $Files
if (-not $trackedMarkdown) {
    Push-Location -LiteralPath $Root
    try {
        # Exclude tests/fixtures: it deliberately contains a broken-link
        # fixture for this script's own test suite.
        $trackedMarkdown = @(git ls-files '*.md' ':!tests/fixtures/**')
    }
    finally {
        Pop-Location
    }
}

$linkPattern = '\[[^\]]+\]\(([^)]+)\)'
$failures = [System.Collections.Generic.List[string]]::new()
$checkedCount = 0

foreach ($relativePath in $trackedMarkdown) {
    $path = Join-Path $Root $relativePath
    $directory = Split-Path -Parent $path
    $content = Get-Content -LiteralPath $path -Raw

    foreach ($match in [regex]::Matches($content, $linkPattern)) {
        $target = $match.Groups[1].Value.Trim()

        if ($target -match '^(https?|mailto):') { continue }
        if ($target.StartsWith('#')) { continue }

        $targetPath = ($target -split '#')[0]
        if ([string]::IsNullOrWhiteSpace($targetPath)) { continue }

        $checkedCount++
        $resolved = Join-Path $directory $targetPath

        if (-not (Test-Path -LiteralPath $resolved)) {
            $failures.Add("$relativePath -> $target (resolved to $resolved, which does not exist)")
        }
    }
}

if ($failures.Count -gt 0) {
    $detail = ($failures | ForEach-Object { " - $_" }) -join "`n"
    throw "Markdown link check failed for $($failures.Count) link(s):`n$detail"
}

Write-Host "All $checkedCount relative Markdown links resolved across $($trackedMarkdown.Count) tracked files." -ForegroundColor Green
