function Set-ChannelForgeUserNumber {
    # Feeds the user's saved channel numbers into Channel.AssignedNumber, after block numbering.
    # A saved number beats a block number: the displaced block channel moves to the next free
    # number in its block, or is left unnumbered. Two saved numbers that are equal are both
    # left unused, nothing is picked, and the pair is returned as a review item.
    # Returns Applied (plain sentences) and Collisions (plain sentences).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Channel[]]$Channel,
        [AllowEmptyCollection()][object[]]$Record = @(),
        [AllowEmptyCollection()][object[]]$NumberingBlock = @()
    )

    $applied = [System.Collections.Generic.List[string]]::new()
    $collisions = [System.Collections.Generic.List[string]]::new()
    $byKey = @{}
    foreach ($ch in $Channel) {
        $key = Get-ChannelForgeChannelIdentityKey -Channel $ch
        if (-not $byKey.ContainsKey($key)) { $byKey[$key] = $ch }
    }
    $wanted = @($Record | Where-Object { $byKey.ContainsKey([string]$_.channelKey) } | ForEach-Object {
            [pscustomobject]@{ Channel = $byKey[[string]$_.channelKey]; Number = [int]$_.number }
        })

    $userChannels = [System.Collections.Generic.List[Channel]]::new()
    foreach ($group in @($wanted | Group-Object -Property Number | Sort-Object { [int]$_.Name })) {
        if ($group.Count -gt 1) {
            $names = @($group.Group | ForEach-Object { "'$($_.Channel.DisplayName)'" } | Sort-Object) -join ' and '
            [void]$collisions.Add("Review needed: channel number $($group.Name) is saved for $names. Nothing was picked and neither saved number is used. Change one of them in state/channel-decisions.json.")
            foreach ($member in $group.Group) { [void]$member.Channel.Warnings.Add("Review needed: saved channel number $($group.Name) is also saved for another channel; the saved number is not used.") }
            continue
        }
        $member = $group.Group[0]
        $member.Channel.AssignedNumber = [int]$group.Name
        [void]$userChannels.Add($member.Channel)
        [void]$applied.Add("'$($member.Channel.DisplayName)' uses your saved channel number $($group.Name).")
    }

    $taken = @{}
    foreach ($ch in $userChannels) { $taken[[int]$ch.AssignedNumber] = $true }
    $displaced = @($Channel | Where-Object { $null -ne $_.AssignedNumber -and -not $userChannels.Contains($_) -and $taken.ContainsKey([int]$_.AssignedNumber) } |
            Sort-Object { [int]$_.AssignedNumber }, { $_.DisplayName.ToLowerInvariant() })
    $oldNumber = @{}
    foreach ($ch in $displaced) { $oldNumber[$ch] = [int]$ch.AssignedNumber; $ch.AssignedNumber = $null }
    $used = @{}
    foreach ($ch in $Channel) { if ($null -ne $ch.AssignedNumber) { $used[[int]$ch.AssignedNumber] = $true } }
    foreach ($ch in $displaced) {
        $block = @($NumberingBlock | Where-Object { $_.category.Trim().ToLowerInvariant() -eq $ch.Group.Trim().ToLowerInvariant() }) | Select-Object -First 1
        $moved = $null
        if ($null -ne $block) {
            for ($n = $oldNumber[$ch] + 1; $n -le [int]$block.end; $n++) {
                if (-not $used.ContainsKey($n)) { $moved = $n; break }
            }
        }
        if ($null -ne $moved) {
            $ch.AssignedNumber = $moved
            $used[$moved] = $true
            [void]$ch.Warnings.Add("A saved channel number took this channel's number; it moved to $moved.")
        }
        elseif ($null -ne $block) {
            [void]$ch.Warnings.Add("Numbering block '$($block.category)' ($($block.start)-$($block.end)) is full; channel left unassigned.")
        }
        else {
            [void]$ch.Warnings.Add('A saved channel number took this channel''s number and it has no numbering block; channel left unassigned.')
        }
    }

    return [pscustomobject]@{ Applied = @($applied.ToArray()); Collisions = @($collisions.ToArray()) }
}
