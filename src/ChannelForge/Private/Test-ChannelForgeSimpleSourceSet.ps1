function Test-ChannelForgeSimpleSourceSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$PlaylistCount,
        [Parameter(Mandatory)][int]$GuideCount,
        $Binding,
        [AllowEmptyCollection()][string[]]$EffectivePlaylistLogicalId = @()
    )

    if ($PlaylistCount -ne 1 -or $GuideCount -gt 1) { return $false }
    if ($GuideCount -eq 0) { return $true }
    return $null -ne $Binding -and [bool]$Binding.Enabled -and -not [bool]$Binding.ExplicitlyUnbound -and
    [int]$Binding.Revision -eq 1 -and @($EffectivePlaylistLogicalId).Count -eq 1
}
