function Save-ChannelForgeEvidenceCache {
    # Keeps a fetched evidence set at -Path with its source, revision and fetch time. Only Status Ok is saved; any other
    # status (PageChanged, FetchFailed, ...) returns Skipped and leaves the cache untouched. The write goes to a temp file
    # and then replaces the cache, so a half-written file is never left. The set being replaced is first kept at
    # "<Path>.lkg" (last-known-good), but only if it still reads cleanly. Returns Status (Saved | Skipped | WriteFailed), Reason.
    # Nothing here is called by the build.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Records,
        [Parameter(Mandatory)][string]$Source,
        [string]$Revision,
        [Parameter(Mandatory)][string]$FetchedAt,
        [string]$Status = 'Ok'
    )

    if ($Status -ne 'Ok') { return [pscustomobject]@{ Status = 'Skipped'; Reason = "Fetch status was $Status; cache left as it was." } }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
        $json = [ordered]@{ source = $Source; revision = $Revision; fetchedAt = $FetchedAt; records = @($Records) } | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($temporary, $json, [System.Text.UTF8Encoding]::new($false))
        if ((Read-ChannelForgeEvidenceCache -Path $Path).Status -in 'Fresh', 'Stale') { Copy-Item -LiteralPath $Path -Destination "$Path.lkg" -Force }
        [System.IO.File]::Move($temporary, $Path, $true)
    }
    catch { return [pscustomobject]@{ Status = 'WriteFailed'; Reason = $_.Exception.Message } }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    [pscustomobject]@{ Status = 'Saved'; Reason = $null }
}
