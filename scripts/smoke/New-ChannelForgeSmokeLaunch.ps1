# Host side of the clean-machine smoke. Checks the candidate, fills the Windows
# Sandbox template, starts the sandbox, waits for the evidence, prints its path.
# Dot-sourcing this file only loads the functions (the tests use that).
[CmdletBinding()]
param(
    [string]$PackagePath,
    [string]$ResultsRoot = (Join-Path ([IO.Path]::GetTempPath()) 'ChannelForgeSmokeResults'),
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Returns the evidence record when the ZIP exists and its SHA-256 matches the
# <zip>.evidence.json written by the package build. Throws otherwise.
function Assert-SmokeCandidate {
    param([Parameter(Mandatory)][string]$PackagePath)
    if (-not [IO.File]::Exists($PackagePath)) { throw "Candidate ZIP not found: $PackagePath" }
    $evidencePath = $PackagePath + '.evidence.json'
    if (-not [IO.File]::Exists($evidencePath)) { throw "Evidence file not found next to the ZIP: $evidencePath" }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    $expected = ([string]$evidence.PackageSha256).ToLowerInvariant()
    if ($expected -cnotmatch '^[0-9a-f]{64}$') { throw 'The evidence file has no valid PackageSha256.' }
    if (([string]$evidence.PackageSourceCommitSha) -cnotmatch '^[0-9a-f]{40}$') { throw 'The evidence file has no valid PackageSourceCommitSha.' }
    if ([string]$evidence.PackageFilename -cne [IO.Path]::GetFileName($PackagePath)) { throw 'The evidence file names a different ZIP.' }
    $actual = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $expected) { throw "The ZIP SHA-256 ($actual) does not match the evidence file ($expected)." }
    return $evidence
}

# The source checkout must be clean and at the commit the package was built from.
function Assert-SmokeSourceClean {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$ExpectedCommit)
    $head = (& git -C $RepoRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "$RepoRoot is not a git checkout, so the source commit cannot be proven." }
    if ([string]$head -cne $ExpectedCommit) { throw "Checkout HEAD ($head) is not the packaged commit ($ExpectedCommit)." }
    $dirty = @(& git -C $RepoRoot status --porcelain)
    if ($dirty.Count -gt 0) { throw 'The checkout has uncommitted changes. Smoke a clean commit.' }
}

function New-SmokeWsbContent {
    param([Parameter(Mandatory)][string]$TemplatePath, [Parameter(Mandatory)][string]$InputFolder, [Parameter(Mandatory)][string]$ResultsFolder)
    $text = [IO.File]::ReadAllText($TemplatePath)
    $text = $text.Replace('{{INPUT_FOLDER}}', [Security.SecurityElement]::Escape($InputFolder))
    $text = $text.Replace('{{RESULTS_FOLDER}}', [Security.SecurityElement]::Escape($ResultsFolder))
    if ($text -match '\{\{[A-Z_]+\}\}') { throw "The template still has a placeholder: $($Matches[0])" }
    return $text
}

# Copies only what the sandbox needs into one read-only input folder.
function New-SmokeInputFolder {
    param([string]$PackagePath, [string]$InputFolder, [string]$RepoRoot)
    New-Item -ItemType Directory -Force -Path (Join-Path $InputFolder 'fixtures') | Out-Null
    Copy-Item -LiteralPath $PackagePath -Destination $InputFolder
    Copy-Item -LiteralPath ($PackagePath + '.evidence.json') -Destination $InputFolder
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts/smoke/Invoke-ChannelForgeSmoke.ps1') -Destination $InputFolder
    Copy-Item -Path (Join-Path $RepoRoot 'tests/fixtures/smoke/*') -Destination (Join-Path $InputFolder 'fixtures')
}

function Invoke-SmokeLaunch {
    param([string]$PackagePath, [string]$ResultsRoot, [string]$RepoRoot, [int]$TimeoutMinutes)
    if ([string]::IsNullOrWhiteSpace($PackagePath)) { throw 'Give -PackagePath <candidate ZIP>.' }
    $package = [IO.Path]::GetFullPath($PackagePath)
    $evidence = Assert-SmokeCandidate -PackagePath $package
    Assert-SmokeSourceClean -RepoRoot $RepoRoot -ExpectedCommit ([string]$evidence.PackageSourceCommitSha)
    $sandboxExe = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
    if (-not [IO.File]::Exists($sandboxExe)) { throw 'Windows Sandbox is not turned on. Enable the "Windows Sandbox" optional feature and restart.' }

    $run = Join-Path ([IO.Path]::GetFullPath($ResultsRoot)) ('run-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
    $inputFolder = Join-Path $run 'in'
    $resultsFolder = Join-Path $run 'results'
    New-Item -ItemType Directory -Force -Path $resultsFolder | Out-Null
    New-SmokeInputFolder -PackagePath $package -InputFolder $inputFolder -RepoRoot $RepoRoot
    $wsbPath = Join-Path $run 'ChannelForge-Smoke.wsb'
    $wsb = New-SmokeWsbContent -TemplatePath (Join-Path $RepoRoot 'scripts/smoke/ChannelForge-Smoke.wsb.template') -InputFolder $inputFolder -ResultsFolder $resultsFolder
    [IO.File]::WriteAllText($wsbPath, $wsb, (New-Object Text.UTF8Encoding($false)))

    Start-Process -FilePath $sandboxExe -ArgumentList ('"' + $wsbPath + '"') | Out-Null
    $evidencePath = Join-Path $resultsFolder 'ChannelForge-smoke-evidence.json'
    $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
    while (-not [IO.File]::Exists($evidencePath)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw "No evidence appeared in $resultsFolder within $TimeoutMinutes minutes." }
        Start-Sleep -Seconds 5
    }
    $record = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    Write-Output "Smoke result: $($record.Overall). Evidence: $evidencePath"
    if ([string]$record.Overall -cne 'PASS') { exit 1 }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-SmokeLaunch -PackagePath $PackagePath -ResultsRoot $ResultsRoot -RepoRoot $RepoRoot -TimeoutMinutes $TimeoutMinutes
}
