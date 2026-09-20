[CmdletBinding()]
param(
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'ChannelForge'),
    [switch]$SkipStart
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$package = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([char]92, [char]47)
$destination = [IO.Path]::GetFullPath($InstallRoot).TrimEnd([char]92, [char]47)
$tools = Join-Path $package 'tools/ChannelForgeAutoUpdate.Core.psm1'
if (-not [IO.File]::Exists($tools)) { throw "This folder is not a ChannelForge bundle: $tools" }
Import-Module $tools -Force
$validated = Test-ChannelForgeWindowsPackage -PackageRoot $package
if ($destination -cne [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ChannelForge')).TrimEnd([char]92, [char]47)) {
    throw 'InstallRoot must be the per-user LocalAppData ChannelForge directory.'
}
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$existingManifest = Join-Path $destination 'package-manifest.json'
if (Test-Path -LiteralPath $existingManifest -PathType Leaf) {
    $updater = Join-Path $destination 'tools/Invoke-ChannelForgeAutoUpdate.ps1'
    $packageRuntime = Join-Path $package 'runtime/pwsh/pwsh.exe'
    if (-not [IO.File]::Exists($updater) -or -not [IO.File]::Exists($packageRuntime)) { throw 'Existing ChannelForge installation is incomplete or the source bundle runtime is missing; refusing to overwrite it.' }
    # Run from the extracted source bundle so the updater can replace the
    # installed runtime without locking its own DLLs.
    & $packageRuntime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $updater -Apply -PackageRoot $package -InstallRoot $destination -SkipRestart:$SkipStart
    if ($LASTEXITCODE -ne 0) { throw 'ChannelForge upgrade failed.' }
} else {
    Copy-ChannelForgeUpdatePackageContent -SourcePath $package -DestinationRoot $destination | Out-Null
    Test-ChannelForgeWindowsPackage -PackageRoot $destination -AllowProtectedState -AllowUnmanifestedFiles | Out-Null
}
if (-not $SkipStart) {
    $runtime = Join-Path $destination 'runtime/pwsh/pwsh.exe'
    $start = Join-Path $destination 'scripts/Start-ChannelForge.ps1'
    & $runtime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $start
    if ($LASTEXITCODE -ne 0) { throw 'ChannelForge installed but could not start.' }
}
Write-Output "ChannelForge installed at $destination"
