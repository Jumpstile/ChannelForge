function Set-ChannelForgeChannelNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Channel[]]$Channel,

        [Parameter(Mandatory)]
        [psobject[]]$NumberingBlock
    )

    # Phase 1 numbering (see issue #7) is intentionally simple and
    # explainable: a channel is assigned a number only if its M3U
    # group-title (Group) exactly matches (case-insensitive) a numbering
    # block's category. Smarter category inference - mapping "PPV" to
    # "PPV & Events", for example - belongs to the Confidence Engine
    # (ROADMAP Milestone 2), not here. A channel that doesn't match any
    # block is left unassigned with a warning; nothing is guessed.
    $byGroup = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[Channel]]]::new()

    foreach ($ch in $Channel) {
        $key = $ch.Group.Trim().ToLowerInvariant()
        if (-not $byGroup.ContainsKey($key)) {
            $byGroup[$key] = [System.Collections.Generic.List[Channel]]::new()
        }
        $byGroup[$key].Add($ch)
    }

    foreach ($block in $NumberingBlock) {
        $key = $block.category.Trim().ToLowerInvariant()
        if (-not $byGroup.ContainsKey($key)) {
            continue
        }

        # Deterministic order within a block: ordinal, case-insensitive by
        # the alias-resolved display name, never filesystem or hashtable
        # enumeration order.
        $matched = @($byGroup[$key] | Sort-Object { $_.DisplayName.ToLowerInvariant() })
        $number = [int]$block.start
        $blockEnd = [int]$block.end

        foreach ($ch in $matched) {
            if ($number -gt $blockEnd) {
                [void]$ch.Warnings.Add("Numbering block '$($block.category)' ($($block.start)-$($block.end)) is full; channel left unassigned.")
                continue
            }

            $ch.AssignedNumber = $number
            $number++
        }
    }

    foreach ($ch in $Channel) {
        if ($null -eq $ch.AssignedNumber) {
            [void]$ch.Warnings.Add("No numbering block matched group '$($ch.Group)'.")
        }
    }

    return $Channel
}
