function Compare-ChannelForgeLogoLookupMap {
    [CmdletBinding()]
    param(
        [AllowNull()]$Old,
        [Parameter(Mandatory)]$New
    )

    # One job: count keys added, changed and removed between two key-to-link maps.
    $added = 0
    $changed = 0
    $removed = 0
    foreach ($key in $New.Keys) {
        if ($null -eq $Old -or -not $Old.ContainsKey($key)) { $added++ }
        elseif ($Old[$key] -cne $New[$key]) { $changed++ }
    }
    if ($null -ne $Old) {
        foreach ($key in $Old.Keys) { if (-not $New.Contains($key)) { $removed++ } }
    }
    return [pscustomobject][ordered]@{ Added = $added; Changed = $changed; Removed = $removed }
}
