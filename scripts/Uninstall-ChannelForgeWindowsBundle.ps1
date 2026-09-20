[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'ChannelForge'),
    [switch]$PurgeData,
    [switch]$ConfirmPurge
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$expectedRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ChannelForge')).TrimEnd([char]92, [char]47)
$actualRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd([char]92, [char]47)
if (-not [string]::Equals($expectedRoot, $actualRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "InstallRoot must be exactly the per-user ChannelForge directory: $expectedRoot"
}
if ($PurgeData -and -not $ConfirmPurge) {
    throw 'PurgeData requires ConfirmPurge. Without both switches, user state is retained.'
}
if (-not (Test-Path -LiteralPath $actualRoot -PathType Container)) {
    Write-Output "ChannelForge is not installed at $actualRoot."
    return
}
$currentProcessPath = $null
try { $currentProcessPath = (Get-Process -Id $PID -ErrorAction Stop).Path } catch { }
if ($currentProcessPath -and $currentProcessPath.StartsWith((Join-Path $actualRoot 'runtime'), [StringComparison]::OrdinalIgnoreCase)) {
    $relayRoot = Join-Path ([IO.Path]::GetTempPath()) ('channelforge-uninstall-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $relayRoot | Out-Null
    try {
        $relayRuntime = Join-Path $relayRoot 'runtime'
        $relayPwsh = Join-Path $relayRuntime 'pwsh.exe'
        $relayScript = Join-Path $relayRoot 'Uninstall-ChannelForgeWindowsBundle.ps1'
        Copy-Item -LiteralPath (Split-Path -Parent $currentProcessPath) -Destination $relayRuntime -Recurse -Force
        Copy-Item -LiteralPath $PSCommandPath -Destination $relayScript -Force
        $relayArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $relayScript, '-InstallRoot', $InstallRoot)
        if ($PurgeData) { $relayArgs += '-PurgeData' }
        if ($ConfirmPurge) { $relayArgs += '-ConfirmPurge' }
        $cleanupCommand = '/c timeout /t 30 /nobreak >nul & rmdir /s /q "' + $relayRoot + '"'
        Start-Process -FilePath $env:ComSpec -ArgumentList $cleanupCommand -WindowStyle Hidden | Out-Null
        Start-Process -FilePath $relayPwsh -ArgumentList $relayArgs -WorkingDirectory $relayRoot -WindowStyle Hidden | Out-Null
        exit 0
    } catch {
        Remove-Item -LiteralPath $relayRoot -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}


$runtime = Join-Path $actualRoot 'runtime/pwsh/pwsh.exe'
$stopScript = Join-Path $actualRoot 'scripts/Stop-ChannelForge.ps1'
if ((Test-Path -LiteralPath $runtime -PathType Leaf) -and (Test-Path -LiteralPath $stopScript -PathType Leaf)) {
    & $runtime -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $stopScript
}

$applicationNames = @(
    'src', 'gui', 'runtime', 'scripts', 'tools', 'schemas', 'engineering', 'docs',
    'package-manifest.json', 'README.md', 'LICENSE', 'VERSION', 'CHANGELOG.md',
    'Start ChannelForge.cmd', 'Install ChannelForge.cmd', 'Update ChannelForge.cmd',
    'Uninstall ChannelForge.cmd'
)
foreach ($name in $applicationNames) {
    $path = Join-Path $actualRoot $name
    if (Test-Path -LiteralPath $path) {
        if ($PSCmdlet.ShouldProcess($path, 'remove ChannelForge application files')) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

if ($PurgeData) {
    $dataNames = @('state', 'config', 'output', 'cache', 'logs', 'UpdateBackups')
    foreach ($name in $dataNames) {
        $path = Join-Path $actualRoot $name
        if (Test-Path -LiteralPath $path) {
            if ($PSCmdlet.ShouldProcess($path, 'permanently remove ChannelForge user data')) {
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
    }
}

$remaining = @(Get-ChildItem -LiteralPath $actualRoot -Force -ErrorAction SilentlyContinue)
if ($remaining.Count -eq 0) {
    Remove-Item -LiteralPath $actualRoot -Force -ErrorAction SilentlyContinue
}
if ($PurgeData) {
    Write-Output 'ChannelForge application and user data removed.'
} else {
    Write-Output 'ChannelForge application files removed. User data was retained.'
}
