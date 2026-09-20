[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'output/packages'),
    [string]$PowerShellVersion = '7.6.6',
    [string]$PowerShellRuntimeZipPath = '',
    [string]$PowerShellRuntimeCacheRoot = '',
    [string]$SourceCommitSha = '',
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FullPath([string]$Path) { return [IO.Path]::GetFullPath($Path) }
function Assert-File([string]$Path, [string]$Label) {
    if (-not [IO.File]::Exists($Path)) { throw "Required $Label is missing: $Path" }
}
function Copy-Tree([string]$Source, [string]$Destination) {
    if (-not [IO.Directory]::Exists($Source)) { throw "Required directory is missing: $Source" }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}
function Copy-File([string]$Source, [string]$Destination) {
    Assert-File $Source 'package file'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}
function Get-TreeHash([string]$RootPath) {
    $rows = foreach ($item in @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($RootPath, $item.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative`0$($item.Length)`0$hash"
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($rows -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Write-CanonicalJson([object]$Value, [string]$Path) {
    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}
function Resolve-PortablePowerShellRuntime {
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$CacheRoot,
        [string]$ArchivePath = ''
    )

    $expectedHashes = @{
        '7.6.6' = '02fe458be20493fbdf43f61ea20610b811ee6c738ab1676c61b9cfcd1a33c860'
    }
    if (-not $expectedHashes.ContainsKey($Version)) {
        throw "Unsupported bundled PowerShell version '$Version'. Add its official win-x64 ZIP SHA256 before packaging."
    }

    $archiveUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-x64.zip"
    $expectedHash = $expectedHashes[$Version]
    if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
        New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
        $ArchivePath = Join-Path $CacheRoot "PowerShell-$Version-win-x64.zip"
    } else {
        $ArchivePath = Get-FullPath $ArchivePath
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ArchivePath) | Out-Null

    $archiveHash = if ([IO.File]::Exists($ArchivePath)) {
        (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    } else {
        ''
    }
    if ($archiveHash -ne $expectedHash) {
        $downloadPath = "$ArchivePath.download"
        if (Test-Path -LiteralPath $downloadPath) { Remove-Item -LiteralPath $downloadPath -Force }
        Write-Host "Downloading official PowerShell portable runtime: $archiveUrl"
        Invoke-WebRequest -Uri $archiveUrl -OutFile $downloadPath -UseBasicParsing
        $downloadHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($downloadHash -ne $expectedHash) {
            Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
            throw "PowerShell portable runtime hash mismatch. Expected $expectedHash, received $downloadHash."
        }
        Move-Item -LiteralPath $downloadPath -Destination $ArchivePath -Force
    }

    $archiveHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne $expectedHash) {
        throw "PowerShell portable runtime hash mismatch. Expected $expectedHash, received $archiveHash."
    }

    $extractRoot = Join-Path ([IO.Path]::GetTempPath()) ("channelforge-powershell-" + [guid]::NewGuid().ToString('N'))
    $runtimeRoot = Join-Path $extractRoot 'runtime'
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $runtimeRoot -Force
    Assert-File (Join-Path $runtimeRoot 'pwsh.exe') 'portable PowerShell executable'
    return [pscustomobject][ordered]@{
        ArchivePath = $ArchivePath
        ArchiveUrl = $archiveUrl
        ArchiveSha256 = $archiveHash
        ExtractRoot = $extractRoot
        RuntimeRoot = $runtimeRoot
    }
}
function Write-DeterministicZip([string]$SourceRoot, [string]$ZipPath) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ([IO.File]::Exists($ZipPath)) { Remove-Item -LiteralPath $ZipPath -Force }
    $archive = [IO.Compression.ZipFile]::Open($ZipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $fixedTime = [DateTimeOffset]::new([DateTime]::new(1980, 1, 1, 0, 0, 0, [DateTimeKind]::Utc))
        foreach ($item in @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force | Sort-Object FullName)) {
            $relative = [IO.Path]::GetRelativePath($SourceRoot, $item.FullName).Replace('\', '/')
            $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $fixedTime
            $input = [IO.File]::OpenRead($item.FullName)
            try {
                $output = $entry.Open()
                try { $input.CopyTo($output) } finally { $output.Dispose() }
            } finally { $input.Dispose() }
        }
    } finally { $archive.Dispose() }
}

$rootFull = Get-FullPath $Root
$outputFull = Get-FullPath $OutputRoot
if (-not [IO.Directory]::Exists($rootFull)) { throw "Repository root is missing: $rootFull" }
$runtimeInfo = $null

$gitHead = (& git -C $rootFull rev-parse HEAD 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitHead)) { throw 'Could not determine source commit SHA.' }
if ([string]::IsNullOrWhiteSpace($SourceCommitSha)) { $SourceCommitSha = $gitHead }
if ($SourceCommitSha -notmatch '^[0-9a-f]{40}$') { throw 'SourceCommitSha must be a full 40-character commit SHA.' }
if ($gitHead -cne $SourceCommitSha) { throw "Source HEAD '$gitHead' does not match requested '$SourceCommitSha'." }
$dirty = @(& git -C $rootFull status --porcelain 2>$null)
if (-not $AllowDirty -and $dirty.Count -gt 0) { throw 'Refusing to package a dirty source tree. Commit the source or pass -AllowDirty for local development only.' }

$versionPath = Join-Path $rootFull 'VERSION'
Assert-File $versionPath 'VERSION file'
$version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Unsupported ChannelForge version: $version" }
$guiDist = Join-Path $rootFull 'gui/dist'
if (-not [IO.File]::Exists((Join-Path $guiDist 'index.html'))) { throw 'Built GUI is missing. Run npm run build in gui before packaging.' }

$runtimeCacheRoot = if ([string]::IsNullOrWhiteSpace($PowerShellRuntimeCacheRoot)) {
    Join-Path ([IO.Path]::GetTempPath()) 'ChannelForge-PowerShell'
} else {
    Get-FullPath $PowerShellRuntimeCacheRoot
}
$runtimeInfo = Resolve-PortablePowerShellRuntime -Version $PowerShellVersion -CacheRoot $runtimeCacheRoot -ArchivePath $PowerShellRuntimeZipPath
$runtimeFull = $runtimeInfo.RuntimeRoot

$stageParent = Join-Path $outputFull '.staging'
$stage = Join-Path $stageParent ("windows-x64-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
    Copy-Tree (Join-Path $rootFull 'src/ChannelForge') (Join-Path $stage 'src/ChannelForge')
    Copy-Tree (Join-Path $rootFull 'gui/dist') (Join-Path $stage 'gui/dist')
    Copy-Tree (Join-Path $rootFull 'schemas') (Join-Path $stage 'schemas')
    Copy-Tree (Join-Path $rootFull 'tools') (Join-Path $stage 'tools')
    Copy-Tree $runtimeFull (Join-Path $stage 'runtime/pwsh')

    $scriptNames = @(
        'Start-ChannelForgeWebServer.ps1', 'Invoke-ChannelForgeSourceRefresh.ps1',
        'Start-ChannelForge.ps1', 'Stop-ChannelForge.ps1',
        'Install-ChannelForgeWindowsBundle.ps1', 'Uninstall-ChannelForgeWindowsBundle.ps1'
    )
    foreach ($name in $scriptNames) { Copy-File (Join-Path $rootFull "scripts/$name") (Join-Path $stage "scripts/$name") }
    foreach ($name in @('Start ChannelForge.cmd', 'Install ChannelForge.cmd', 'Update ChannelForge.cmd', 'Uninstall ChannelForge.cmd')) {
        Copy-File (Join-Path $rootFull $name) (Join-Path $stage $name)
    }
    foreach ($path in @('README.md', 'LICENSE', 'VERSION')) { Copy-File (Join-Path $rootFull $path) (Join-Path $stage $path) }
    foreach ($path in @(
        'docs/user/INSTALL-WINDOWS.md', 'docs/user/UPDATE-WINDOWS.md', 'docs/user/UNINSTALL-WINDOWS.md',
        'docs/user/Build-Your-First-Lineup.md', 'docs/user/CURRENT_LIMITATIONS.md', 'docs/user/TROUBLESHOOTING.md'
    )) { Copy-File (Join-Path $rootFull $path) (Join-Path $stage $path) }
    if ([IO.Directory]::Exists((Join-Path $rootFull 'docs/user/assets'))) {
        Copy-Tree (Join-Path $rootFull 'docs/user/assets') (Join-Path $stage 'docs/user/assets')
    }
    $forbiddenNames = @('.git', '.worktrees', 'state', 'config', 'output', 'cache', 'logs', 'test-results', 'node_modules', 'target')
    foreach ($item in @(Get-ChildItem -LiteralPath $stage -Recurse -Force)) {
        if ($forbiddenNames -contains $item.Name) {
            throw "Package stage contains forbidden path component: $($item.FullName)"
        }
    }
    $runtimeStage = [IO.Path]::GetFullPath((Join-Path $stage 'runtime'))
    $textExtensions = @('.ps1', '.psm1', '.psd1', '.json', '.md', '.cmd', '.txt', '.html', '.js', '.css', '.map')
    foreach ($item in @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force | Where-Object { $_.FullName -notlike "$runtimeStage*" -and $textExtensions -contains $_.Extension.ToLowerInvariant() })) {
        $text = Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop
        if ($text.Contains($rootFull)) { throw "Package contains an absolute source path: $($item.FullName)" }
    }


    $runtimeVersion = (& (Join-Path $stage 'runtime/pwsh/pwsh.exe') -NoProfile -Command '$PSVersionTable.PSVersion.ToString()').Trim()
    if ($LASTEXITCODE -ne 0 -or $runtimeVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Bundled PowerShell runtime did not execute.' }
    $runtimeHash = Get-TreeHash (Join-Path $stage 'runtime/pwsh')
    $files = foreach ($item in @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force | Where-Object { $_.FullName -ne (Join-Path $stage 'package-manifest.json') } | Sort-Object FullName)) {
        [ordered]@{
            Path = [IO.Path]::GetRelativePath($stage, $item.FullName).Replace('\', '/')
            ByteLength = [int64]$item.Length
            Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $manifest = [ordered]@{
        SchemaVersion = 'windows-package/v1'
        PackageTarget = 'windows-x64-portable-server'
        ChannelForgeVersion = $version
        SourceCommitSha = $SourceCommitSha.ToLowerInvariant()
        BundledPowerShellVersion = $runtimeVersion
        BundledPowerShellHash = $runtimeHash
        BundledPowerShellArchiveUrl = $runtimeInfo.ArchiveUrl
        BundledPowerShellArchiveSha256 = $runtimeInfo.ArchiveSha256
        Files = @($files)
    }
    Write-CanonicalJson $manifest (Join-Path $stage 'package-manifest.json')
    Import-Module (Join-Path $stage 'tools/ChannelForgeAutoUpdate.Core.psm1') -Force
    Test-ChannelForgeWindowsPackage -PackageRoot $stage | Out-Null

    New-Item -ItemType Directory -Force -Path $outputFull | Out-Null
    $packageName = "ChannelForge-v$version-alpha.1-windows-x64.zip"
    $packagePath = Join-Path $outputFull $packageName
    Write-DeterministicZip $stage $packagePath
    $packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $evidence = [ordered]@{
        SchemaVersion = 'windows-package-evidence/v1'
        PackageFilename = $packageName
        PackageSha256 = $packageHash
        PackageManifestSha256 = (Get-FileHash -LiteralPath (Join-Path $stage 'package-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        PackageSourceCommitSha = $SourceCommitSha.ToLowerInvariant()
        BundledPowerShellVersion = $runtimeVersion
        BundledPowerShellHash = $runtimeHash
        BundledPowerShellArchiveUrl = $runtimeInfo.ArchiveUrl
        BundledPowerShellArchiveSha256 = $runtimeInfo.ArchiveSha256
        FileCount = $files.Count
    }
    Write-CanonicalJson $evidence (Join-Path $outputFull ($packageName + '.evidence.json'))
    [pscustomobject][ordered]@{
        PackagePath = $packagePath
        PackageFilename = $packageName
        PackageSha256 = $packageHash
        PackageSourceCommitSha = $SourceCommitSha.ToLowerInvariant()
        PackageManifestPath = Join-Path $stage 'package-manifest.json'
        BundledPowerShellVersion = $runtimeVersion
        BundledPowerShellHash = $runtimeHash
        FileCount = $files.Count
    }
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    if ($runtimeInfo -and (Test-Path -LiteralPath $runtimeInfo.ExtractRoot)) {
        Remove-Item -LiteralPath $runtimeInfo.ExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
