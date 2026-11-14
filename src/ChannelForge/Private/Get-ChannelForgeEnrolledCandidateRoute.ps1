function Get-ChannelForgeEnrolledCandidateRoute {
    # The one place that picks the builder for a saved source set.
    # 'single-source': a simple set that came from the old config keeps its old hashes.
    # 'source-set': everything else.
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Playlist = @(),
        [AllowEmptyCollection()][object[]]$Guide = @(),
        [AllowEmptyCollection()][object[]]$Binding = @()
    )

    $legacyOrigins = @('legacy-source-enrollment/v1', 'guided-setup')
    if (@($Playlist).Count -ne 1 -or [string]$Playlist[0].Origin -notin $legacyOrigins) { return 'source-set' }
    $guideBinding = if (@($Guide).Count -eq 1) { @($Binding | Where-Object { [string]$_.GuideId -eq [string]$Guide[0].SourceId })[0] } else { $null }
    $effective = if ($null -eq $guideBinding -or [bool]$guideBinding.ExplicitlyUnbound) { @() }
    elseif ([bool]$guideBinding.AppliesToAll -or [string]$Playlist[0].SourceId -in @($guideBinding.PlaylistIds | ForEach-Object { [string]$_ })) { @([string]$Playlist[0].SourceId) }
    else { @() }
    $simple = Test-ChannelForgeSimpleSourceSet -PlaylistCount @($Playlist).Count -GuideCount @($Guide).Count -Binding $guideBinding -EffectivePlaylistLogicalId $effective
    if ($simple) { return 'single-source' }
    return 'source-set'
}
