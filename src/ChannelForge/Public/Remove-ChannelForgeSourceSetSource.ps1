function Remove-ChannelForgeSourceSetSource {
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')][string]$SourceId,
        [Parameter(Mandatory, ParameterSetName = 'ByLabel')][string]$Label,
        [Parameter(ParameterSetName = 'ByLabel')][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $base = Get-ChannelForgeSourceSetEditBase -RepositoryRoot $RepositoryRoot
    $target = Find-ChannelForgeSourceSetSource -Base $base -SourceId $SourceId -Label $Label -Kind $Kind

    $playlists = @($base.Playlists)
    $guides = @($base.Guides)
    $bindings = @($base.Bindings)
    if ($target.Kind -eq 'M3U') {
        if ($playlists.Count -le 1) { throw 'SOURCE_ENROLLMENT_INVALID: the last playlist cannot be removed.' }
        $playlists = @($playlists | Where-Object { $_.SourceId -cne $target.SourceId })
        # Drop only this playlist from each binding. A binding left empty stays as a binding with no target; it is never retargeted.
        $bindings = @($bindings | ForEach-Object {
            if ($_.PlaylistIds -ccontains $target.SourceId) {
                $remaining = @($_.PlaylistIds | Where-Object { $_ -cne $target.SourceId })
                $_.PlaylistIds = $remaining
                $_.ExplicitlyUnbound = $remaining.Count -eq 0
                $_.Revision = $_.Revision + 1
            }
            $_
        })
    }
    else {
        $guides = @($guides | Where-Object { $_.SourceId -cne $target.SourceId })
        $bindings = @($bindings | Where-Object { $_.GuideId -cne $target.SourceId })
    }
    $null = Save-ChannelForgeSourceSetEdit -RepositoryRoot $RepositoryRoot -Base $base -PlaylistSources $playlists -GuideSources $guides -Bindings $bindings
    # The set file is saved. Only now is the removed snapshot deleted.
    if (-not [string]::IsNullOrWhiteSpace($target.ManagedPath)) {
        try { Remove-ChannelForgeManagedSourceSnapshot -RepositoryRoot $RepositoryRoot -ManagedPath $target.ManagedPath }
        catch { Write-Warning "The source was removed, but its saved copy could not be deleted: $($_.Exception.Message)" }
    }
    return [pscustomobject][ordered]@{ SourceId = $target.SourceId; Kind = $target.Kind; Label = $target.Label }
}
