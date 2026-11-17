function Get-ChannelForgePreflightReport {
    <#
    .SYNOPSIS
    Checks, read-only, that the folders ChannelForge writes to are ready.

    .DESCRIPTION
    Report contract preflight-report/v1. For OutputRoot, CacheRoot and an optional BackupRoot it checks: exists, inside
    the project, not a link, writable (one tiny file in a ".preflight" subfolder, removed again) and free space.
    It also checks that the staging and final folders share one volume and that the published M3U and XMLTV match
    their manifest. A check that cannot run is Unknown, never Pass. It never changes accepted state or published output.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),
        [string]$OutputRoot,
        [string]$CacheRoot,
        [string]$BackupRoot,
        [ValidateRange(0, [long]::MaxValue)]
        [long]$MinimumFreeSpaceMB = 100
    )

    $repo = [IO.Path]::GetFullPath($RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repo 'output/reports' }
    if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $repo 'output/cache' }
    $roots = [ordered]@{ OutputRoot = $OutputRoot; CacheRoot = $CacheRoot }
    if (-not [string]::IsNullOrWhiteSpace($BackupRoot)) { $roots['BackupRoot'] = $BackupRoot }

    $floor = [long]([Math]::Min([decimal]$MinimumFreeSpaceMB * 1MB, [decimal][long]::MaxValue))
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $roots.Keys) {
        $path = [IO.Path]::GetFullPath([string]$roots[$name])
        foreach ($f in @(Get-ChannelForgePreflightRootFinding -Name $name -Path $path -RepositoryRoot $repo -MinimumFreeBytes $floor)) { $findings.Add($f) }
    }
    $findings.Add((Get-ChannelForgePreflightVolumeFinding -RepositoryRoot $repo))
    foreach ($f in @(Get-ChannelForgePreflightPublishedFinding -RepositoryRoot $repo)) { $findings.Add($f) }

    $count = { param($s) @($findings | Where-Object { $_.Status -eq $s }).Count }
    $failed = & $count 'Fail'; $unknown = & $count 'Unknown'
    return [pscustomobject][ordered]@{
        Version  = 'preflight-report/v1'
        Findings = @($findings)
        Summary  = [pscustomobject][ordered]@{
            Pass = & $count 'Pass'; Fail = $failed; Unknown = $unknown
            Overall = if ($failed -gt 0) { 'Fail' } elseif ($unknown -gt 0) { 'Unknown' } else { 'Pass' }
        }
    }
}
