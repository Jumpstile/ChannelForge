[CmdletBinding()]
param(
    [string]$InstallRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateRange(1024, 65535)][int]$Port = 8765,
    [switch]$NoBrowser,
    [int]$HealthTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd([char]92, [char]47)
$runtime = Join-Path $root 'runtime/pwsh/pwsh.exe'
$serverScript = Join-Path $root 'scripts/Start-ChannelForgeWebServer.ps1'
$moduleManifest = Join-Path $root 'src/ChannelForge/ChannelForge.psd1'
$index = Join-Path $root 'gui/dist/index.html'
foreach ($required in @($runtime, $serverScript, $moduleManifest, $index)) {
    if (-not [IO.File]::Exists($required)) { throw "ChannelForge installation is incomplete. Missing: $required" }
}
$runtimeState = Join-Path $root 'state/runtime'
New-Item -ItemType Directory -Force -Path $runtimeState | Out-Null
$pidPath = Join-Path $runtimeState 'server.pid'
$stdoutPath = Join-Path $runtimeState 'server.stdout.log'
$stderrPath = Join-Path $runtimeState 'server.stderr.log'
$url = "http://127.0.0.1:$Port/"
$healthUrl = "http://127.0.0.1:$Port/health"

if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
    $existingPid = 0
    [int]::TryParse((Get-Content -LiteralPath $pidPath -Raw).Trim(), [ref]$existingPid) | Out-Null
    if ($existingPid -gt 0) {
        try {
            $existing = Get-Process -Id $existingPid -ErrorAction Stop
            $health = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($health.StatusCode -eq 200) {
                if (-not $NoBrowser) { Start-Process $url | Out-Null }
                Write-Output "ChannelForge is already running: $url"
                exit 0
            }
        } catch { }
    }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

$arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $serverScript, '-Port', $Port, '-BindAddress', '127.0.0.1')
$process = Start-Process -FilePath $runtime -ArgumentList $arguments -WorkingDirectory $root -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
Set-Content -LiteralPath $pidPath -Value ([string]$process.Id) -NoNewline
$deadline = [DateTime]::UtcNow.AddSeconds($HealthTimeoutSeconds)
$healthy = $false
while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
    try {
        $health = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($health.StatusCode -eq 200) { $healthy = $true; break }
    } catch { }
    if ($process.HasExited) { break }
}
if (-not $healthy) {
    $detail = if (Test-Path -LiteralPath $stderrPath) { (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'The server did not answer /health before the startup timeout.' }
    throw "ChannelForge could not start. $detail"
}
if (-not $NoBrowser) { Start-Process $url | Out-Null }
Write-Output "ChannelForge started: $url"
