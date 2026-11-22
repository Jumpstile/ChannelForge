function Read-ChannelForgeEvidenceCache {
    # Reads a cached evidence set written by Save-ChannelForgeEvidenceCache. Never throws.
    # Status: Fresh | Stale (older than -MaxAge; the records are still returned, flagged) | Missing | Corrupt (Reason says why).
    # Default MaxAge is 24 hours (TV episodes); pass 7 days for league pages. Nothing here is called by the build.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [timespan]$MaxAge = [timespan]::FromHours(24),
        [datetime]$Now = [datetime]::UtcNow
    )

    $result = { param($Status, $Reason, $Set) [pscustomobject]@{
            Status = $Status; Reason = $Reason; Records = @($Set.records); Source = $Set.source; Revision = $Set.revision
            FetchedAt = $Set.fetchedAt; ExpiresAt = $Set.expiresAt } }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return & $result 'Missing' 'No cached evidence.' $null }
    try {
        $set = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -DateKind String -ErrorAction Stop
        $fetched = [datetime]::Parse([string]$set.fetchedAt, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
        if ($null -eq $set.records -or -not $set.source) { throw 'The cached set has no records or source.' }
    }
    catch { return & $result 'Corrupt' "The cached evidence could not be read: $($_.Exception.Message)" $null }
    $set | Add-Member -NotePropertyName expiresAt -NotePropertyValue ($fetched + $MaxAge).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture) -Force
    if ($Now.ToUniversalTime() -gt $fetched + $MaxAge) { return & $result 'Stale' 'The cached evidence is past its expiry.' $set }
    & $result 'Fresh' $null $set
}
