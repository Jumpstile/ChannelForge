# =============================================================================
# ChannelForge updater helper functions
# =============================================================================
# Pure/testable logic for tools/Invoke-ChannelForgeAutoUpdate.ps1, split out so
# Pester can import and exercise it without triggering the orchestrator's
# top-level network calls. Importing this module has no side effects.

# A module's $ErrorActionPreference is snapshotted from the caller's scope at
# *import* time, not read live from the current caller on every call. If this
# module is already loaded (e.g. by a test harness, or a future long-running
# host) with a looser preference, a plain `Import-Module` (without -Force, as
# the orchestrator intentionally uses -- see its own comment) is a no-op and
# never re-snapshots it. Cmdlet calls in this module (Copy-Item, New-Item,
# etc.) must fail closed on error regardless of that history, so set it
# explicitly here rather than depending on inheritance. (Found via destructive
# -path testing: a locked destination file during Copy-ChannelForgeUpdatePackageContent
# silently produced a non-terminating error and reported "success" until this
# was added.)
$ErrorActionPreference = 'Stop'

# Fail-closed allowlist for auto-update package content (ADR-0006). Only these
# top-level names may be replaced by an update package. Everything else --
# data/, config/, output/, backups/, logs, caches, secrets, and local
# overrides -- is left untouched even if an update package happens to contain
# an entry with the same name.
$script:ChannelForgeUpdateAllowedTopLevelNames = @(
    'src', 'tools', 'scripts', 'schemas', 'engineering', 'docs', 'gui', 'runtime',
    'VERSION', 'README.md', 'LICENSE', 'CHANGELOG.md', 'package-manifest.json',
    'Start ChannelForge.cmd', 'Install ChannelForge.cmd', 'Update ChannelForge.cmd',
    'Uninstall ChannelForge.cmd'
)

function Get-ChannelForgeUpdateAllowedTopLevelNames {
    [CmdletBinding()]
    param()

    return $script:ChannelForgeUpdateAllowedTopLevelNames
}

function Test-ChannelForgeUpdateAllowedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return $script:ChannelForgeUpdateAllowedTopLevelNames -icontains $Name
}

function ConvertTo-ChannelForgeUpdateVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionText
    )

    $normalized = ($VersionText -replace '^v', '').Trim()
    try {
        return [version]$normalized
    } catch {
        throw "Version '$VersionText' is not a valid System.Version value after normalization."
    }
}

function Get-ChannelForgeLocalVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $value = (Get-Content -LiteralPath $Path -Raw).Trim()
        if ($value) { return $value }
    }

    throw "Could not determine local ChannelForge version. Create a VERSION file or pass -VersionFile."
}

function Test-ChannelForgeUpdateAssetUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    # URI-parsed validation (not string -like/prefix matching) so the host
    # check inspects the actual parsed authority, not a substring of the raw
    # URL text. Rejects userinfo tricks (https://github.com@evil.com/...) and
    # lookalike hosts (https://github.com.evil.com/...) that a naive -like
    # prefix check could be fooled by.
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsedUri)) {
        return $false
    }

    if ($parsedUri.Scheme -ne 'https') {
        return $false
    }

    if ($parsedUri.Host -ne 'github.com') {
        return $false
    }

    if (-not [string]::IsNullOrEmpty($parsedUri.UserInfo)) {
        return $false
    }

    $expectedPrefix = "/$Owner/$Repository/releases/download/"
    return $parsedUri.AbsolutePath.StartsWith($expectedPrefix, [System.StringComparison]::Ordinal)
}

function Invoke-GitHubJsonRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $headers = @{ 'User-Agent' = 'ChannelForge-Updater' }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -UseBasicParsing
}

function Get-ChannelForgeLatestReleaseInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    $uri = "https://api.github.com/repos/$Owner/$Repository/releases/latest"

    try {
        $release = Invoke-GitHubJsonRequest -Uri $uri
        return [pscustomobject]@{
            Found   = $true
            Release = $release
        }
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($statusCode -eq 404) {
            return [pscustomobject]@{
                Found   = $false
                Release = $null
            }
        }

        throw
    }
}

function Select-ChannelForgeUpdateAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Release,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    $asset = @($Release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1)
    if (-not $asset) {
        throw "Latest release '$($Release.tag_name)' does not contain an asset matching $Pattern"
    }

    if (-not (Test-ChannelForgeUpdateAssetUrl -Url $asset.browser_download_url -Owner $Owner -Repository $Repository)) {
        throw "Refusing non-release GitHub asset URL: $($asset.browser_download_url)"
    }

    return $asset
}

function Assert-ChannelForgeWritableTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Copy-Item -Force (and Move-Item -Force) silently clear the ReadOnly
    # attribute and replace the file anyway rather than failing (verified
    # empirically during destructive-path testing). A read-only target --
    # or any read-only file underneath it, if it is a directory being
    # replaced wholesale -- is never overridden here; the update is refused
    # with an actionable message so the user can decide whether to unlock it.
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $readOnlyFiles = @(
        if (Test-Path -LiteralPath $Path -PathType Container) {
            Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Where-Object { $_.IsReadOnly }
        } else {
            Get-Item -LiteralPath $Path -Force | Where-Object { $_.IsReadOnly }
        }
    )

    if ($readOnlyFiles.Count -gt 0) {
        $names = ($readOnlyFiles | Select-Object -ExpandProperty FullName) -join ', '
        throw "Refusing to update: read-only file(s) found at update target -- $names. Remove the read-only attribute (e.g. Set-ItemProperty -LiteralPath '<file>' -Name IsReadOnly -Value `$false) and re-run the update; this updater will not silently clear it."
    }
}

function New-ChannelForgeUpdateBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Install root does not exist: $Root"
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path (Join-Path $Root 'UpdateBackups') $stamp
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    foreach ($name in $script:ChannelForgeUpdateAllowedTopLevelNames) {
        $source = Join-Path $Root $name
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $backupDir -Recurse -Force
        }
    }

    if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
        throw "Backup creation failed: $backupDir"
    }

    return $backupDir
}

function Save-ChannelForgeReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Asset
    )

    $extension = [System.IO.Path]::GetExtension($Asset.name)
    if (-not $extension) { $extension = '.download' }
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("channelforge-update-" + [guid]::NewGuid().ToString('N') + $extension)
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $tempPath -UseBasicParsing

    $downloaded = Get-Item -LiteralPath $tempPath -ErrorAction Stop
    if ($downloaded.Length -le 0) {
        throw "Downloaded update asset is empty: $tempPath"
    }

    return $tempPath
}

function Copy-ChannelForgeUpdatePackageContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationRoot
    )

    # Enumerate concrete child items instead of Copy-Item -LiteralPath with a
    # '*' wildcard: -LiteralPath disables wildcard expansion, so a literal
    # '...\*' path silently matches nothing and Copy-Item copies zero files
    # without ever throwing. Enumerating first also gives us a single place to
    # enforce the protected-data allowlist per item.
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw "Extracted update content not found: $SourcePath"
    }

    $items = Get-ChildItem -LiteralPath $SourcePath -Force
    $allowedItems = @($items | Where-Object { Test-ChannelForgeUpdateAllowedPath -Name $_.Name })

    # Check every allowed target for a read-only conflict before copying
    # anything, so a conflict discovered partway through never leaves a
    # partial update (some allowed items copied, others not).
    foreach ($item in $allowedItems) {
        Assert-ChannelForgeWritableTarget -Path (Join-Path $DestinationRoot $item.Name)
    }

    $copied = @()
    $skipped = @()

    foreach ($item in $items) {
        if (Test-ChannelForgeUpdateAllowedPath -Name $item.Name) {
            Copy-Item -LiteralPath $item.FullName -Destination $DestinationRoot -Recurse -Force

            # Defense in depth beyond $ErrorActionPreference: verify the item
            # actually landed rather than trusting that Copy-Item's error (if
            # any) was surfaced as terminating, matching the equivalent
            # post-copy check in New-TpmUpdateBackup / New-ChannelForgeUpdateBackup.
            $destinationItemPath = Join-Path $DestinationRoot $item.Name
            if (-not (Test-Path -LiteralPath $destinationItemPath)) {
                throw "Copy reported no error but '$($item.Name)' is missing from the destination: $destinationItemPath"
            }

            $copied += $item.Name
        } else {
            $skipped += $item.Name
        }
    }

    return [pscustomobject]@{
        Copied  = $copied
        Skipped = $skipped
    }
}
function Get-ChannelForgePackageFileHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ChannelForgeWindowsPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [switch]$AllowProtectedState,
        [switch]$AllowUnmanifestedFiles
    )

    $root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([char]92, [char]47)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Package root does not exist: $root"
    }
    $manifestPath = Join-Path $root 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'Package manifest is missing.'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$manifest.SchemaVersion -ne 'windows-package/v1') { throw 'Unsupported package manifest schema.' }
    if ([string]$manifest.PackageTarget -ne 'windows-x64-portable-server') { throw 'Unsupported package target.' }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.SourceCommitSha)) { throw 'Package source commit is missing.' }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.ChannelForgeVersion)) { throw 'Package version is missing.' }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.BundledPowerShellVersion)) { throw 'Bundled PowerShell version is missing.' }

    $files = @($manifest.Files)
    if ($files.Count -eq 0) { throw 'Package manifest contains no files.' }
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $files) {
        $relative = ([string]$entry.Path).Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or $relative -match '(^|/)\.\.(/|$)' -or $relative -match '(^|/)\.git(/|$)') {
            throw "Package manifest contains an unsafe path: $relative"
        }
        if (-not $expected.Add($relative)) { throw "Package manifest contains a duplicate path: $relative" }
        $topLevel = ($relative -split '/')[0]
        $protected = @('data', 'state', 'config', 'output', 'cache', 'logs', 'UpdateBackups') -contains $topLevel
        if ($AllowProtectedState -and $protected) {
            continue
        }
        $path = Join-Path $root ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Manifest file is missing: $relative" }
        $item = Get-Item -LiteralPath $path -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Manifest file is a reparse point: $relative" }
        if ([int64]$item.Length -ne [int64]$entry.ByteLength) { throw "Manifest byte length mismatch: $relative" }
        if ((Get-ChannelForgePackageFileHash -Path $path) -cne ([string]$entry.Sha256).ToLowerInvariant()) { throw "Manifest hash mismatch: $relative" }
    }

    $actual = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object { $_.FullName -ne $manifestPath })
    foreach ($item in $actual) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Package contains a reparse-point file: $($item.FullName)" }
        $relative = [IO.Path]::GetRelativePath($root, $item.FullName).Replace('\', '/')
        $topLevel = ($relative -split '/')[0]
        $protected = @('data', 'state', 'config', 'output', 'cache', 'logs', 'UpdateBackups') -contains $topLevel
        if ($AllowProtectedState -and $protected) { continue }
        if (-not $expected.Contains($relative)) {
            if ($AllowUnmanifestedFiles) { continue }
            throw "Package contains an unmanifested file: $relative"
        }
    }
    return [pscustomobject][ordered]@{
        Manifest = $manifest
        ManifestPath = $manifestPath
        Root = $root
        FileCount = $files.Count
    }
}

function Restore-ChannelForgeUpdateBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$DestinationRoot
    )

    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) { throw "Backup root does not exist: $BackupRoot" }
    foreach ($name in $script:ChannelForgeUpdateAllowedTopLevelNames) {
        $backupPath = Join-Path $BackupRoot $name
        $destinationPath = Join-Path $DestinationRoot $name
        if (Test-Path -LiteralPath $backupPath) {
            Assert-ChannelForgeWritableTarget -Path $destinationPath
            if (Test-Path -LiteralPath $destinationPath) { Remove-Item -LiteralPath $destinationPath -Recurse -Force }
            Copy-Item -LiteralPath $backupPath -Destination $DestinationRoot -Recurse -Force
        } elseif (Test-Path -LiteralPath $destinationPath) {
            Assert-ChannelForgeWritableTarget -Path $destinationPath
            Remove-Item -LiteralPath $destinationPath -Recurse -Force
        }
    }
}


Export-ModuleMember -Function @(
    'Get-ChannelForgeUpdateAllowedTopLevelNames',
    'Test-ChannelForgeUpdateAllowedPath',
    'ConvertTo-ChannelForgeUpdateVersion',
    'Get-ChannelForgeLocalVersion',
    'Test-ChannelForgeUpdateAssetUrl',
    'Invoke-GitHubJsonRequest',
    'Get-ChannelForgeLatestReleaseInfo',
    'Select-ChannelForgeUpdateAsset',
    'Assert-ChannelForgeWritableTarget',
    'New-ChannelForgeUpdateBackup',
    'Save-ChannelForgeReleaseAsset',
    'Copy-ChannelForgeUpdatePackageContent',
    'Get-ChannelForgePackageFileHash',
    'Test-ChannelForgeWindowsPackage',
    'Restore-ChannelForgeUpdateBackup'
)
