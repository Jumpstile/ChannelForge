function Get-ChannelForgeSourceChangeReport {
    <#
    .SYNOPSIS
    Compares the previous and new parsed channel lists of one source and reports new and missing groups and channels. Report only.
    .DESCRIPTION
    Returns name lists (group names and channel names, never URLs) and a counts-only Summary line, which is the part safe to put in the refresh result. A $null Previous list means this is the first refresh.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyCollection()][object[]]$Previous,
        [AllowNull()][AllowEmptyCollection()][object[]]$Current
    )

    if ($null -eq $Previous) {
        return [pscustomobject][ordered]@{
            IsFirstRefresh  = $true
            NewGroups       = @()
            MissingGroups   = @()
            NewChannels     = @()
            MissingChannels = @()
            Summary         = 'First refresh: no earlier list to compare with.'
        }
    }

    $namesOf = {
        param($list, $property)
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in @($list)) {
            $value = if ($property -eq 'Group') { [string]$item.Group } elseif (-not [string]::IsNullOrWhiteSpace([string]$item.OriginalName)) { [string]$item.OriginalName } else { [string]$item.DisplayName }
            if (-not [string]::IsNullOrWhiteSpace($value)) { $set.Add($value.Trim()) | Out-Null }
        }
        return , $set
    }
    $oldGroups = & $namesOf $Previous 'Group'
    $newGroups = & $namesOf $Current 'Group'
    $oldChannels = & $namesOf $Previous 'Channel'
    $newChannels = & $namesOf $Current 'Channel'
    $onlyIn = { param($a, $b) @($a | Where-Object { -not $b.Contains($_) } | Sort-Object) }
    $addedGroups = & $onlyIn $newGroups $oldGroups
    $missingGroups = & $onlyIn $oldGroups $newGroups
    $addedChannels = & $onlyIn $newChannels $oldChannels
    $missingChannels = & $onlyIn $oldChannels $newChannels

    $summary = "Groups added: $($addedGroups.Count). Groups missing: $($missingGroups.Count). Channels added: $($addedChannels.Count). Channels missing: $($missingChannels.Count)."

    return [pscustomobject][ordered]@{
        IsFirstRefresh  = $false
        NewGroups       = $addedGroups
        MissingGroups   = $missingGroups
        NewChannels     = $addedChannels
        MissingChannels = $missingChannels
        Summary         = $summary
    }
}
