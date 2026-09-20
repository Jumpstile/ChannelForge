# =============================================================================
# ChannelForge backup-first updater helper
# =============================================================================
# Standalone first-pass updater. It checks GitHub Releases and can replace one
# packaged release asset only after an explicit -Apply and a successful backup.
#
# Orchestration only -- the testable logic lives in
# ChannelForgeAutoUpdate.Core.psm1.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$CheckOnly,
    [switch]$Apply,
    [string]$PackagePath = '',
    [string]$PackageRoot = '',
    [switch]$SkipRestart,
    [string]$VersionFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'),
    [string]$InstallRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Owner = 'Jumpstile',
    [string]$Repository = 'ChannelForge',
    [string]$AssetNamePattern = '^ChannelForge-v.*-windows-x64\.zip$'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# No -Force: this must not clobber an already-loaded instance of the module.
# A future caller may import the module once for a long-running session;
# reloading it here on every invocation would also defeat that caller's
# ability to mock or otherwise control it (observed directly: an earlier
# version of this line broke Pester's -ModuleName mocking of the
# destructive-path test suite).
Import-Module (Join-Path $PSScriptRoot 'ChannelForgeAutoUpdate.Core.psm1')

function Write-UpdaterInfo {
    param([string]$Message)
    Write-Host "[ChannelForge updater] $Message"
}

function Install-DownloadedUpdate {
    param([string]$DownloadedPath, [string]$Root)

    $extension = [System.IO.Path]::GetExtension($DownloadedPath)
    switch -Regex ($extension) {
        '^\.zip$' {
            $extractPath = Join-Path ([System.IO.Path]::GetTempPath()) ("channelforge-extract-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
            try {
                Expand-Archive -LiteralPath $DownloadedPath -DestinationPath $extractPath -Force
                $manifestPath = Join-Path $extractPath 'package-manifest.json'
                if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
                    throw 'Windows package manifest is missing.'
                }
                Test-ChannelForgeWindowsPackage -PackageRoot $extractPath | Out-Null
                $result = Copy-ChannelForgeUpdatePackageContent -SourcePath $extractPath -DestinationRoot $Root
                if ($result.Copied.Count -gt 0) {
                    Write-UpdaterInfo "Updated       : $($result.Copied -join ', ')"
                }
                if ($result.Skipped.Count -gt 0) {
                    Write-UpdaterInfo "Skipped (protected, not overwritten): $($result.Skipped -join ', ')"
                }
            } finally {
                if (Test-Path -LiteralPath $extractPath) {
                    Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        '^\.(ps1|psm1)$' {
            $singleFileDestination = Join-Path $Root (Split-Path -Leaf $DownloadedPath)
            Assert-ChannelForgeWritableTarget -Path $singleFileDestination
            Copy-Item -LiteralPath $DownloadedPath -Destination $Root -Force
        }
        default {

            throw "Unsupported update asset extension: $extension"
        }
    }
}
function Resolve-ChannelForgePackageRoot {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.File]::Exists($full)) {
        if ([IO.Path]::GetExtension($full) -ine '.zip') { throw 'PackagePath must be a ZIP file.' }
        $temp = Join-Path ([IO.Path]::GetTempPath()) ('channelforge-package-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $temp | Out-Null
        Expand-Archive -LiteralPath $full -DestinationPath $temp -Force
        return [pscustomobject][ordered]@{ Root = $temp; Temporary = $true }
    }
    if (-not [IO.Directory]::Exists($full)) { throw "Package path does not exist: $full" }
    return [pscustomobject][ordered]@{ Root = $full.TrimEnd([char]92, [char]47); Temporary = $false }
}

function Invoke-ChannelForgeLocalPackageUpdate {
    param([Parameter(Mandatory)][string]$SourceRoot)
    $validated = Test-ChannelForgeWindowsPackage -PackageRoot $SourceRoot
    if (-not $PSCmdlet.ShouldProcess($InstallRoot, "update ChannelForge to $($validated.Manifest.ChannelForgeVersion)")) { return }
    $stopScript = Join-Path $InstallRoot 'scripts/Stop-ChannelForge.ps1'
    $startScript = Join-Path $InstallRoot 'scripts/Start-ChannelForge.ps1'
    $runtime = Join-Path $InstallRoot 'runtime/pwsh/pwsh.exe'
    if (-not $SkipRestart -and [IO.File]::Exists($stopScript) -and [IO.File]::Exists($runtime)) {
        & $runtime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $stopScript
    }
    $backup = $null
    try {
        $backup = New-ChannelForgeUpdateBackup -Root $InstallRoot
        Copy-ChannelForgeUpdatePackageContent -SourcePath $SourceRoot -DestinationRoot $InstallRoot | Out-Null
        Test-ChannelForgeWindowsPackage -PackageRoot $InstallRoot -AllowProtectedState -AllowUnmanifestedFiles | Out-Null
        if (-not $SkipRestart) {
            $newRuntime = Join-Path $InstallRoot 'runtime/pwsh/pwsh.exe'
            $newStart = Join-Path $InstallRoot 'scripts/Start-ChannelForge.ps1'
            & $newRuntime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $newStart
            if ($LASTEXITCODE -ne 0) { throw 'Updated ChannelForge failed its startup health check.' }
        }
        Write-UpdaterInfo "Update installed successfully: $($validated.Manifest.ChannelForgeVersion)"
    } catch {
        if ($null -ne $backup) {
            Restore-ChannelForgeUpdateBackup -BackupRoot $backup -DestinationRoot $InstallRoot
        }
        if (-not $SkipRestart -and [IO.File]::Exists($runtime) -and [IO.File]::Exists($startScript)) {
            & $runtime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $startScript -NoBrowser
        }
        throw
    }
}

if (-not [string]::IsNullOrWhiteSpace($PackagePath) -and -not [string]::IsNullOrWhiteSpace($PackageRoot)) {
    throw 'Specify only one of PackagePath or PackageRoot.'
}
if (-not [string]::IsNullOrWhiteSpace($PackagePath) -or -not [string]::IsNullOrWhiteSpace($PackageRoot)) {
    if (-not $CheckOnly -and -not $Apply) { $CheckOnly = $true }
    $source = if (-not [string]::IsNullOrWhiteSpace($PackageRoot)) { Resolve-ChannelForgePackageRoot -Path $PackageRoot } else { Resolve-ChannelForgePackageRoot -Path $PackagePath }
    try {
        $validated = Test-ChannelForgeWindowsPackage -PackageRoot $source.Root
        Write-UpdaterInfo "Package valid   : $($validated.Manifest.ChannelForgeVersion)"
        Write-UpdaterInfo "Package source  : $($validated.Manifest.SourceCommitSha)"
        if ($Apply) { Invoke-ChannelForgeLocalPackageUpdate -SourceRoot $source.Root }
    } finally {
        if ($source.Temporary -and (Test-Path -LiteralPath $source.Root)) { Remove-Item -LiteralPath $source.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return
}


if (-not $CheckOnly -and -not $Apply) {
    $CheckOnly = $true
}

$localVersionText = Get-ChannelForgeLocalVersion -Path $VersionFile
$localVersion = ConvertTo-ChannelForgeUpdateVersion -VersionText $localVersionText

$releaseInfo = Get-ChannelForgeLatestReleaseInfo -Owner $Owner -Repository $Repository
Write-UpdaterInfo "Local version : $localVersionText"

if (-not $releaseInfo.Found) {
    Write-UpdaterInfo 'No GitHub release is available yet for this repository.'
    return
}

$release = $releaseInfo.Release
$latestVersionText = ($release.tag_name -replace '^v', '').Trim()
$latestVersion = ConvertTo-ChannelForgeUpdateVersion -VersionText $latestVersionText

Write-UpdaterInfo "Latest release: $($release.tag_name)"

if ($latestVersion -le $localVersion) {
    Write-UpdaterInfo 'Already current. No update needed.'
    return
}

$asset = Select-ChannelForgeUpdateAsset -Release $release -Pattern $AssetNamePattern -Owner $Owner -Repository $Repository
Write-UpdaterInfo "Update available: $localVersionText -> $($release.tag_name)"
Write-UpdaterInfo "Selected asset  : $($asset.name)"

if ($CheckOnly -and -not $Apply) {
    Write-UpdaterInfo 'Check only. Re-run with -Apply to update.'
    return
}

if ($Apply) {
    if (-not $PSCmdlet.ShouldProcess($InstallRoot, "update ChannelForge to $($release.tag_name)")) {
        return
    }

    $downloadedPath = $null
    $backupPath = $null
    try {
        $stopScript = Join-Path $InstallRoot 'scripts/Stop-ChannelForge.ps1'
        $oldRuntime = Join-Path $InstallRoot 'runtime/pwsh/pwsh.exe'
        if (-not $SkipRestart -and (Test-Path -LiteralPath $stopScript) -and (Test-Path -LiteralPath $oldRuntime)) {
            & $oldRuntime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $stopScript
        }
        $backupPath = New-ChannelForgeUpdateBackup -Root $InstallRoot
        Write-UpdaterInfo "Backup created : $backupPath"

        $downloadedPath = Save-ChannelForgeReleaseAsset -Asset $asset
        Write-UpdaterInfo "Downloaded     : $downloadedPath"
        Install-DownloadedUpdate -DownloadedPath $downloadedPath -Root $InstallRoot
        Test-ChannelForgeWindowsPackage -PackageRoot $InstallRoot -AllowProtectedState -AllowUnmanifestedFiles | Out-Null
        if (-not $SkipRestart) {
            $newRuntime = Join-Path $InstallRoot 'runtime/pwsh/pwsh.exe'
            $newStart = Join-Path $InstallRoot 'scripts/Start-ChannelForge.ps1'
            if ((Test-Path -LiteralPath $newRuntime) -and (Test-Path -LiteralPath $newStart)) {
                & $newRuntime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $newStart
                if ($LASTEXITCODE -ne 0) { throw 'Updated ChannelForge failed its startup health check.' }
            }
        }
        Write-UpdaterInfo 'Update installed successfully.'
    } catch {
        if ($null -ne $backupPath) {
            Restore-ChannelForgeUpdateBackup -BackupRoot $backupPath -DestinationRoot $InstallRoot
        }
        if (-not $SkipRestart -and (Test-Path -LiteralPath $oldRuntime) -and (Test-Path -LiteralPath $stopScript)) {
            $restoredStart = Join-Path $InstallRoot 'scripts/Start-ChannelForge.ps1'
            if (Test-Path -LiteralPath $restoredStart) {
                & $oldRuntime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $restoredStart -NoBrowser
            }
        }
        throw
    } finally {
        if ($downloadedPath -and (Test-Path -LiteralPath $downloadedPath -PathType Leaf)) {
            Remove-Item -LiteralPath $downloadedPath -Force -ErrorAction SilentlyContinue
        }
    }
}
