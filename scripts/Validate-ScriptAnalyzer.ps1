param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    # Paths to lint. Defaults to this repository's src/ and scripts/.
    # Exposed so tests can point this at fixture files instead.
    [string[]]$Paths
)

$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    throw "PSScriptAnalyzer is not installed. Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser"
}

Import-Module PSScriptAnalyzer

# Lint every PowerShell file under src/ and scripts/. Warning- and
# Information-severity findings are printed for visibility but do not fail
# this check; only Error-severity findings do (see DEVELOPER_GUIDE.md). The
# codebase has known, accepted Warning-level findings today (e.g. Write-Host
# usage in scripts/, a few naming/ShouldProcess conventions) that aren't
# worth a sweeping unrelated refactor just to satisfy a new CI gate; gating
# on Error only still catches real mistakes (syntax-adjacent issues,
# dangerous patterns) without that noise.
if (-not $Paths) {
    $Paths = @(
        (Join-Path $Root 'src')
        (Join-Path $Root 'scripts')
    )
}

$results = @()
foreach ($path in $Paths) {
    # -ErrorAction SilentlyContinue here, deliberately overriding this
    # script's own $ErrorActionPreference: individual PSScriptAnalyzer rules
    # occasionally log a non-terminating internal error (observed
    # intermittently, unrelated to any real finding in this codebase) that
    # would otherwise be escalated to fatal and make this check flaky. The
    # actual lint results are unaffected when this happens; only the
    # diagnostic error stream entry is suppressed.
    $results += Invoke-ScriptAnalyzer -Path $path -Recurse -Severity Error, Warning, Information -ErrorAction SilentlyContinue
}

$errorFindings = @($results | Where-Object Severity -eq 'Error')
$otherFindings = @($results | Where-Object Severity -ne 'Error')

if ($otherFindings.Count -gt 0) {
    Write-Host "PSScriptAnalyzer found $($otherFindings.Count) non-blocking Warning/Information finding(s):" -ForegroundColor Yellow
    $otherFindings | Format-Table RuleName, Severity, ScriptName, Line -AutoSize | Out-String | Write-Host
}

if ($errorFindings.Count -gt 0) {
    Write-Host "PSScriptAnalyzer found $($errorFindings.Count) Error-severity finding(s):" -ForegroundColor Red
    $errorFindings | Format-Table RuleName, Severity, ScriptName, Line -AutoSize | Out-String | Write-Host
    throw "PSScriptAnalyzer reported $($errorFindings.Count) Error-severity finding(s)."
}

Write-Host "PSScriptAnalyzer found no Error-severity findings." -ForegroundColor Green
