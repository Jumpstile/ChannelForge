function Get-ChannelForgeSourceBindingFingerprint {
    [CmdletBinding()]
    param(
        $Binding,
        [AllowEmptyCollection()][string[]]$EffectivePlaylistLogicalId = @(),
        [Parameter(Mandatory)][bool]$IsSimpleSet
    )

    if ($IsSimpleSet) { return '' }
    $hasBinding = $null -ne $Binding
    $unbound = -not $hasBinding -or [bool]$Binding.ExplicitlyUnbound
    return Get-ChannelForgeDomainHash -Domain 'source-binding-identity/v2' -InputObject ([ordered]@{
            Revision = if ($hasBinding) { [int]$Binding.Revision } else { 0 }
            Enabled = $hasBinding -and [bool]$Binding.Enabled
            Mode = if ($unbound) { 'none' } else { 'playlists' }
            PlaylistLogicalIds = @($EffectivePlaylistLogicalId | Sort-Object -Unique)
        })
}
