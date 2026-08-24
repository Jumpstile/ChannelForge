param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$IPTVBossData = '',
    [switch]$Force,
    # Exposed for deterministic testing of the overwrite guard below; normal
    # use should rely on the default (the current time).
    [string]$Timestamp = (Get-Date -Format "yyyyMMdd-HHmmss")
)

$ErrorActionPreference = "Stop"

# Always load the module from this script's own location, never from -Root
# (which a caller may point at a different backup location, e.g. in tests).
$ModuleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $ModuleRoot 'src\ChannelForge\ChannelForge.psd1') -Force

# Fail safe: never tar a path that does not exist. A missing source would
# otherwise let tar silently produce an empty or misleading archive.
if ([string]::IsNullOrWhiteSpace($IPTVBossData)) {
    throw 'IPTVBoss data path must be supplied explicitly; no machine-specific NAS default is used.'
}
Assert-ChannelForgePathExists -Path $IPTVBossData -PathType Container -Description 'IPTVBoss data path'

# Defense in depth: reject backing up an entire drive root or a well-known
# system directory, even though it exists and passed the check above.
Assert-ChannelForgeBackupSourcePath -Path $IPTVBossData

$backupDir = Join-Path $Root "backups"

# Path-safety guardrail: backups may only land inside the project's own
# backups/ folder, never wherever $Root happens to resolve to.
Assert-ChannelForgeWritePath -Path $backupDir -AllowedRoot $backupDir
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$archive = Join-Path $backupDir "iptvboss-data-$Timestamp.tar.gz"
Assert-ChannelForgeWritePath -Path $archive -AllowedRoot $backupDir

# Never silently overwrite an existing backup. An archive already present
# at this timestamp means something unexpected happened (clock skew, a
# re-run within the same second); clobbering it could destroy the only
# copy of a prior backup. -Force makes overwriting an explicit choice.
if ((Test-Path -LiteralPath $archive -PathType Leaf) -and -not $Force) {
    throw "Backup archive already exists: $archive. Re-run with -Force to overwrite intentionally."
}

# Run from inside backupDir and pass a relative archive filename. GNU tar
# misreads an absolute Windows path like "C:\foo\bar.tar.gz" as a remote
# "host:path" target because of the drive-letter colon; a relative name has
# no colon, so this works the same way under GNU tar and bsdtar.
$archiveName = Split-Path -Leaf $archive
Push-Location -LiteralPath $backupDir
try {
    tar -czf $archiveName -C (Split-Path -Parent $IPTVBossData) (Split-Path -Leaf $IPTVBossData)
    if ($LASTEXITCODE -ne 0) {
        throw "tar failed with exit code $LASTEXITCODE while creating backup archive: $archive"
    }
}
finally {
    Pop-Location
}

# Verify the archive actually exists before reporting success.
Assert-ChannelForgePathExists -Path $archive -PathType Leaf -Description 'Backup archive'

Write-Host "Backup written: $archive" -ForegroundColor Green
