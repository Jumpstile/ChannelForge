function Merge-ChannelForgeLineup {
    [CmdletBinding()]
    param(
        # Each entry may provide Path (a local .m3u file) or already-parsed
        # Channels from a configured adapter, plus Provider and Playlist.
        # The adapter owns acquisition and format validation; this function
        # owns deterministic normalization, deduplication, and numbering.
        [Parameter(Mandatory)]
        [psobject[]]$Source,

        [Parameter(Mandatory)]
        [string]$AliasPath,

        [Parameter(Mandatory)]
        [string]$NumberingBlocksPath
    )

    # Prefer the caller's stable, path-independent OrderKey for configured
    # remote sources. Existing local callers without OrderKey retain their
    # historical path ordering exactly.
    $sortedSource = @($Source | Sort-Object {
        if ($_.PSObject.Properties.Name -contains 'OrderKey') {
            [string]$_.OrderKey
        }
        else {
            [string]$_.Path
        }
    })

    $channels = [System.Collections.Generic.List[Channel]]::new()
    foreach ($src in $sortedSource) {
        $parsed = if ($src.PSObject.Properties.Name -contains 'Channels') {
            @($src.Channels)
        }
        else {
            Import-ChannelForgeM3UPlaylist -Path $src.Path -Provider $src.Provider -Playlist $src.Playlist
        }
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
