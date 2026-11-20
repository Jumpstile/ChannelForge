function Get-ChannelForgePublishGroup {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Channel = @(),

        # TvgId -> group. Accepted and ignored in this slice.
        [hashtable]$GroupPin = @{},

        # Not built yet. Turning it on throws, so nobody enables it by accident.
        [switch]$FillFromCategories
    )

    # Publish group step (issue #191, slice 1). Returns one object per channel,
    # in order: RawGroup (what the provider sent), Group (what to publish),
    # Source (Provider when the raw group is not empty, otherwise None) and
    # ReviewCandidates (always empty here). Filling is off, so Group is always
    # RawGroup. Never drops a channel and never changes the channel itself.
    if ($FillFromCategories) { throw 'Get-ChannelForgePublishGroup: -FillFromCategories is not implemented in this slice.' }

    foreach ($ch in @($Channel)) {
        $raw = [string]$ch.Group
        [pscustomobject]@{
            RawGroup         = $raw
            Group            = $raw
            Source           = if ($raw.Length -gt 0) { 'Provider' } else { 'None' }
            ReviewCandidates = @()
        }
    }
}
