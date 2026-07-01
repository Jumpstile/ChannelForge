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
    [string]$VersionFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'),
    [string]$InstallRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Owner = 'Jumpstile',
    [string]$Repository = 'ChannelForge',
    [string]$AssetNamePattern = '^ChannelForge\.(zip|ps1|psm1)$'
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
    try {
        $backupPath = New-ChannelForgeUpdateBackup -Root $InstallRoot
        Write-UpdaterInfo "Backup created : $backupPath"

        $downloadedPath = Save-ChannelForgeReleaseAsset -Asset $asset
        Write-UpdaterInfo "Downloaded     : $downloadedPath"

        Install-DownloadedUpdate -DownloadedPath $downloadedPath -Root $InstallRoot
        Write-UpdaterInfo 'Update installed successfully.'
        Write-UpdaterInfo 'Restart ChannelForge before continuing work.'
    } finally {
        if ($downloadedPath -and (Test-Path -LiteralPath $downloadedPath -PathType Leaf)) {
            Remove-Item -LiteralPath $downloadedPath -Force -ErrorAction SilentlyContinue
        }
    }
}
