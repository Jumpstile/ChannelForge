param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$IPTVBossData = "/srv/dev-disk-by-uuid-4d39f891-6950-43f3-9ac1-ba3dd583c8e8/appdata/iptvboss/data"
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $Root "backups"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$archive = Join-Path $backupDir "iptvboss-data-$stamp.tar.gz"
tar -czf $archive -C (Split-Path -Parent $IPTVBossData) (Split-Path -Leaf $IPTVBossData)
Write-Host "Backup written: $archive" -ForegroundColor Green
