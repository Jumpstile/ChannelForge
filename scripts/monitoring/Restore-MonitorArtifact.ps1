[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SpoolRoot,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$ArtifactName,
    [Parameter(Mandatory)][string]$MonitorId,
    [Parameter(Mandatory)][string]$Token
)

Set-StrictMode -Version 2.0
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Repository must be an owner/name pair.' }
if ([string]::IsNullOrWhiteSpace($Token)) { throw 'A GitHub token is required to restore the monitor artifact.' }

$modulePath = Join-Path $PSScriptRoot 'MonitorOutbox.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop
$root = [IO.Path]::GetFullPath($SpoolRoot)
[void](Initialize-MonitorOutbox -SpoolRoot $root)
$hasLocalState = (@(Get-ChildItem -LiteralPath (Join-Path $root 'pending') -File -Filter '*.json' -ErrorAction SilentlyContinue).Count -gt 0) -or
    (@(Get-ChildItem -LiteralPath (Join-Path $root 'recorded') -File -Filter '*.json' -ErrorAction SilentlyContinue).Count -gt 0) -or
    [IO.File]::Exists((Join-Path $root 'source-state.json'))
if ($hasLocalState) {
    [pscustomobject]@{ Restored = $false; Source = 'local-spool'; ArtifactName = $ArtifactName; SpoolRoot = $root }
    exit 0
}

$headers = @{ Accept = 'application/vnd.github+json'; Authorization = 'Bearer ' + $Token; 'User-Agent' = 'Jumpstile-development-monitor' }
$listUri = 'https://api.github.com/repos/' + $Repository + '/actions/artifacts?name=' + [uri]::EscapeDataString($ArtifactName) + '&per_page=100'
$listing = Invoke-RestMethod -Method Get -Uri $listUri -Headers $headers -TimeoutSec 30 -MaximumRedirection 0 -ErrorAction Stop
$artifact = @($listing.artifacts | Where-Object { -not $_.expired -and $_.archive_download_url } | Sort-Object created_at -Descending | Select-Object -First 1)
if ($artifact.Count -eq 0) {
    [pscustomobject]@{ Restored = $false; Source = 'empty'; ArtifactName = $ArtifactName; SpoolRoot = $root }
    exit 0
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('monitor-restore-' + [Guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot 'artifact.zip'
$extractRoot = Join-Path $tempRoot 'extracted'
try {
    [void][IO.Directory]::CreateDirectory($tempRoot)
    [void][IO.Directory]::CreateDirectory($extractRoot)
    Invoke-WebRequest -Method Get -Uri ([string]$artifact[0].archive_download_url) -Headers $headers -OutFile $zipPath -TimeoutSec 60 -MaximumRedirection 0 -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($entry in $archive.Entries) {
            $entryName = [string]$entry.FullName
            if ([IO.Path]::IsPathRooted($entryName) -or $entryName -match '(^|[/\\])\.\.([/\\]|$)') { throw 'Monitor artifact contains a traversal path.' }
        }
    } finally { $archive.Dispose() }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force -ErrorAction Stop

    $candidateRoots = @($extractRoot) + @(Get-ChildItem -LiteralPath $extractRoot -Directory -Recurse -ErrorAction Stop | Select-Object -ExpandProperty FullName)
    $payloadRoots = @($candidateRoots | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_ 'pending') -PathType Container) -or
        (Test-Path -LiteralPath (Join-Path $_ 'recorded') -PathType Container) -or
        (Test-Path -LiteralPath (Join-Path $_ 'source-state.json') -PathType Leaf)
    })
    if ($payloadRoots.Count -ne 1) { throw 'Monitor artifact payload root is ambiguous or missing.' }
    $payloadRoot = [string]$payloadRoots[0]
    $files = @(Get-ChildItem -LiteralPath $payloadRoot -File -Recurse -ErrorAction Stop)
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($payloadRoot.Length)
        while ($relative.StartsWith('\') -or $relative.StartsWith('/')) { $relative = $relative.Substring(1) }
        if ($relative -notmatch '^(pending|recorded)\\[A-Fa-f0-9]{64}\.json$' -and
            $relative -notmatch '^runs\\[A-Za-z0-9_.-]+\.json$' -and
            $relative -ne 'source-state.json') {
            throw ('Monitor artifact contains an unexpected file: ' + $relative)
        }
        $destination = Join-Path $root $relative
        $destinationFull = [IO.Path]::GetFullPath($destination)
        if (-not $destinationFull.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Monitor artifact path escaped the spool root.' }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationFull))
        [IO.File]::Copy($file.FullName, $destinationFull, $false)
    }

    [void](Get-MonitorOutboxItems -SpoolRoot $root -IncludeRecorded)
    if ([IO.File]::Exists((Join-Path $root 'source-state.json'))) {
        [void](Read-MonitorSourceState -SpoolRoot $root -MonitorId $MonitorId)
    }
    [pscustomobject]@{ Restored = $true; Source = 'github-artifact'; ArtifactName = $ArtifactName; ArtifactId = [string]$artifact[0].id; SpoolRoot = $root }
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
