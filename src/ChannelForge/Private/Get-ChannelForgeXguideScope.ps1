function Get-ChannelForgeXguideScope {
    <#
    .SYNOPSIS
    Maps each guide name of a build to the playlist labels it serves, read from the saved source set (xguide-compare/v2).
    Returns $null (compare all guides, as in v1) unless every guide name matches exactly one saved guide label.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$GuideName
    )

    try { $set = Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $RepositoryRoot } catch { return $null }
    $playlists = @($set.Playlists | Where-Object { [bool]$_.Enabled })
    $labels = @($playlists | ForEach-Object { [string]$_.Label })
    if ($playlists.Count -lt 2 -or $labels.Count -ne @($labels | Sort-Object -Unique -CaseSensitive).Count) { return $null }

    $guides = @($set.Guides | Where-Object { [bool]$_.Enabled })
    $scope = @{}
    foreach ($name in $GuideName) {
        $match = @($guides | Where-Object { [string]$_.Label -ceq $name })
        if ($match.Count -ne 1) { return $null }
        $binding = @($set.Bindings | Where-Object { [string]$_.GuideId -ceq [string]$match[0].SourceId })[0]
        $served = if ($null -eq $binding -or -not [bool]$binding.Enabled -or ($null -ne $binding.PSObject.Properties['ExplicitlyUnbound'] -and [bool]$binding.ExplicitlyUnbound)) { @() }
        elseif ([bool]$binding.AppliesToAll) { $playlists }
        else { @($playlists | Where-Object { [string]$_.SourceId -cin @($binding.PlaylistIds | ForEach-Object { [string]$_ }) }) }
        $scope[$name] = [string[]]@($served | ForEach-Object { [string]$_.Label })
    }
    return $scope
}
