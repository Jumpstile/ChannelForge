function Merge-ChannelForgeLineup {
    [CmdletBinding()]
    param(
        # Each entry: a pscustomobject with Path (local .m3u file), Provider,
        # and Playlist. HTTP fetch is explicitly out of scope for this
        # function (see issue #7 Phase 1) - every Path must already exist on
        # disk before calling this.
        [Parameter(Mandatory)]
        [psobject[]]$Source,

        [Parameter(Mandatory)]
        [string]$AliasPath,

        [Parameter(Mandatory)]
        [string]$NumberingBlocksPath
    )

    # Deterministic merge pipeline (issue #7 Phase 1): sort sources by path
    # before parsing anything, so caller-supplied ordering (e.g. an
    # unsorted directory listing) can never affect the result. The same
    # input files must always produce the same channel set in the same
    # order, byte-for-byte, on every run.
    $sortedSource = @($Source | Sort-Object { $_.Path })

    $channels = [System.Collections.Generic.List[Channel]]::new()
    foreach ($src in $sortedSource) {
        $parsed = Import-ChannelForgeM3UPlaylist -Path $src.Path -Provider $src.Provider -Playlist $src.Playlist
        foreach ($ch in $parsed) {
            $channels.Add($ch)
        }
    }

    foreach ($ch in $channels) {
        [void](ConvertTo-ChannelForgeNormalizedChannel -Channel $ch)
        # Alias resolution replaces the display name with the canonical
        # name; OriginalName/NormalizedName are left untouched for audit.
        $ch.DisplayName = Resolve-ChannelForgeAlias -Name $ch.NormalizedName -AliasPath $AliasPath
    }

    # Deterministic dedup, after alias resolution so two providers' different
    # raw names for the same canonical channel are recognized as duplicates.
    # Key: tvg-id when present (the strongest identity signal available in
    # Phase 1), otherwise the case-insensitive display name. Within a key,
    # the first channel survives, where "first" is decided entirely by the
    # already-deterministic (sorted-by-path, then in-file) parse order above
    # - never by any later sort. Losers are marked IsDuplicate and excluded
    # from numbering and from the returned/exported set, but are not
    # discarded silently: callers can still see DuplicateCount by comparing
    # the channel count before and after this step.
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new()
    $survivors = [System.Collections.Generic.List[Channel]]::new()
    $duplicates = [System.Collections.Generic.List[Channel]]::new()

    foreach ($ch in $channels) {
        $key = if ($ch.TvgId) { "id:$($ch.TvgId.Trim().ToLowerInvariant())" } else { "name:$($ch.DisplayName.Trim().ToLowerInvariant())" }

        if ($seenKeys.Contains($key)) {
            $ch.IsDuplicate = $true
            [void]$ch.Warnings.Add("Duplicate of an earlier channel with the same identity key; excluded from merged output.")
            $duplicates.Add($ch)
            continue
        }

        [void]$seenKeys.Add($key)
        $survivors.Add($ch)
    }

    if (-not (Test-Path -LiteralPath $NumberingBlocksPath -PathType Leaf)) {
        throw "Numbering blocks file not found: $NumberingBlocksPath"
    }
    $numberingConfig = Get-Content -LiteralPath $NumberingBlocksPath -Raw | ConvertFrom-Json
    Set-ChannelForgeChannelNumber -Channel $survivors -NumberingBlock @($numberingConfig.blocks) | Out-Null

    # Final output order: numbered channels first in ascending channel-number
    # order, then unassigned channels by display name. This is the order
    # written to merged.m3u, so it must be a pure function of channel data,
    # never enumeration order.
    $ordered = @($survivors | Sort-Object -Property `
        @{ Expression = { if ($null -ne $_.AssignedNumber) { 0 } else { 1 } } }, `
        @{ Expression = { if ($null -ne $_.AssignedNumber) { $_.AssignedNumber } else { [int]::MaxValue } } }, `
        @{ Expression = { $_.DisplayName.ToLowerInvariant() } })

    return [pscustomobject]@{
        Channels       = $ordered
        DuplicateCount = $duplicates.Count
        Duplicates     = @($duplicates)
        WarningCount   = @($channels | Where-Object { $_.Warnings.Count -gt 0 }).Count
    }
}
