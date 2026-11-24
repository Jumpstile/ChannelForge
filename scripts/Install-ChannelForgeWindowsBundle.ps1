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
if (-not [IO.File]::Exists($tools)) { throw "This folder does not look like a full ChannelForge download. Download ChannelForge again and unzip it completely, then run Install ChannelForge.cmd.`nDetails: This folder is not a ChannelForge bundle: $tools" }
Import-Module $tools -Force
$validated = Test-ChannelForgeWindowsPackage -PackageRoot $package
if ($destination -cne [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ChannelForge')).TrimEnd([char]92, [char]47)) {
    throw "ChannelForge can only be installed in its own folder under your user profile. Run Install ChannelForge.cmd without changing the install folder.`nDetails: InstallRoot must be the per-user LocalAppData ChannelForge directory."
}
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$existingManifest = Join-Path $destination 'package-manifest.json'
if (Test-Path -LiteralPath $existingManifest -PathType Leaf) {
    # Use the NEW updater from the source bundle, not the installed (older) one: the old
    # one may not know about newer files such as data\. Running from the bundle also lets
    # it replace the installed runtime without locking its own DLLs.
    $updater = Join-Path $package 'tools/Invoke-ChannelForgeAutoUpdate.ps1'
    $packageRuntime = Join-Path $package 'runtime/pwsh/pwsh.exe'
    if (-not [IO.File]::Exists($updater) -or -not [IO.File]::Exists($packageRuntime)) { throw 'The install package is incomplete (its updater or runtime is missing), so nothing was changed. Download the package again and unzip it fully. Details: missing tools/Invoke-ChannelForgeAutoUpdate.ps1 or runtime/pwsh/pwsh.exe in the package.' }
    & $packageRuntime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $updater -Apply -PackageRoot $package -InstallRoot $destination -SkipRestart:$SkipStart
    if ($LASTEXITCODE -ne 0) { throw 'The upgrade did not finish, so your previous ChannelForge was put back. See the lines above for the reason, fix it, then run Install ChannelForge.cmd again. Details: the updater exited with a non-zero code.' }
} else {
    Copy-ChannelForgeUpdatePackageContent -SourcePath $package -DestinationRoot $destination | Out-Null
    Test-ChannelForgeWindowsPackage -PackageRoot $destination -AllowProtectedState -AllowUnmanifestedFiles | Out-Null
}
if (-not $SkipStart) {
    $runtime = Join-Path $destination 'runtime/pwsh/pwsh.exe'
    $start = Join-Path $destination 'scripts/Start-ChannelForge.ps1'
    & $runtime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $start
    if ($LASTEXITCODE -ne 0) { throw "ChannelForge was installed, but it did not start. Double-click Start ChannelForge.cmd to try again. If that fails, look at the log files in the state\runtime folder.`nDetails: ChannelForge installed but could not start." }
}
Write-Output "ChannelForge installed at $destination"
