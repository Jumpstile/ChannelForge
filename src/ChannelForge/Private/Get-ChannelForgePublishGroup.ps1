function Get-ChannelForgePublishGroup {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Channel = @(),

        # TvgId -> group. Wins over the category list, never over a provider group.
        [hashtable]$GroupPin = @{},

        # Fill an empty provider group from the category list (candidate v10).
        [switch]$FillFromCategories
    )

    # Publish group step (issue #191). Returns one object per channel, in order:
    # RawGroup (what the provider sent), Group (what to publish), Source
    # (Provider, Pin, CategoryList or None) and ReviewCandidates (category names
    # when two or more match, otherwise empty). A provider group is never
    # overwritten. With filling off and no pin, Group is always RawGroup. Never
    # drops a channel and never changes the channel itself.
    foreach ($ch in @($Channel)) {
        $raw = [string]$ch.Group
        $group = $raw
        $source = if ($raw.Length -gt 0) { 'Provider' } else { 'None' }
        $review = @()
        if ($raw.Length -eq 0) {
            $tvgId = [string]$ch.TvgId
            if ($tvgId.Length -gt 0 -and $GroupPin.ContainsKey($tvgId) -and -not [string]::IsNullOrWhiteSpace([string]$GroupPin[$tvgId])) {
                $group = [string]$GroupPin[$tvgId]
                $source = 'Pin'
            }
            elseif ($FillFromCategories) {
                $decision = Get-ChannelForgeCategoryFromText -Text ([string]$ch.DisplayName)
                if ($null -ne $decision.Category) { $group = [string]$decision.Category; $source = 'CategoryList' }
                elseif ($decision.Review) { $review = @($decision.Candidates) }
            }
        }
        [pscustomobject]@{
            RawGroup         = $raw
            Group            = $group
            Source           = $source
            ReviewCandidates = $review
        }
    }
}
