function Set-ChannelForgeSourceSetBinding {
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')][string]$SourceId,
        [Parameter(Mandatory, ParameterSetName = 'ByLabel')][string]$Label,
        [Parameter(ParameterSetName = 'ByLabel')][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [string[]]$Playlist,
        [switch]$AllPlaylists,
        [switch]$NoPlaylist,
        [switch]$Disable,
        [switch]$Enable,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    if ((@([bool]$Playlist, $AllPlaylists.IsPresent, $NoPlaylist.IsPresent) | Where-Object { $_ }).Count -ne 1) { throw 'SOURCE_ENROLLMENT_INVALID: use exactly one of -Playlist, -AllPlaylists or -NoPlaylist.' }
    if ($Disable -and $Enable) { throw 'SOURCE_ENROLLMENT_INVALID: use only one of -Disable or -Enable.' }

    $base = Get-ChannelForgeSourceSetEditBase -RepositoryRoot $RepositoryRoot
    $guide = Find-ChannelForgeSourceSetSource -Base $base -SourceId $SourceId -Label $Label -Kind $Kind
    if ($guide.Kind -ne 'XMLTV') { throw 'SOURCE_ENROLLMENT_INVALID: the source is not a guide.' }

    $ids = @()
    foreach ($name in $Playlist) {
        $match = @(@($base.Playlists) | Where-Object { $_.SourceId -ceq $name -or $_.Label -ieq $name })
        if ($match.Count -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: no saved playlist matches.' }
        if ($match.Count -gt 1) { throw 'SOURCE_ENROLLMENT_INVALID: more than one saved playlist matches. Use the playlist ID.' }
        $ids += $match[0].SourceId
    }
    $ids = @($ids | Sort-Object -Unique)

    $old = @($base.Bindings | Where-Object { $_.GuideId -ceq $guide.SourceId })[0]
    $enabled = if ($Disable) { $false } elseif ($Enable) { $true } elseif ($old) { $old.Enabled } else { $true }
    $same = $old -and $old.AppliesToAll -eq $AllPlaylists.IsPresent -and $old.ExplicitlyUnbound -eq $NoPlaylist.IsPresent -and
        ($old.PlaylistIds -join ',') -ceq ($ids -join ',') -and $old.Enabled -eq $enabled
    $result = [pscustomobject][ordered]@{ SourceId = $guide.SourceId; Label = $guide.Label; Changed = -not $same }
    if ($same) { return $result }

    $new = [pscustomobject][ordered]@{
        GuideId = $guide.SourceId; PlaylistIds = $ids; AppliesToAll = $AllPlaylists.IsPresent
        ExplicitlyUnbound = $NoPlaylist.IsPresent; Revision = $(if ($old) { $old.Revision + 1 } else { 1 }); Enabled = $enabled
    }
    $bindings = @(@($base.Bindings | Where-Object { $_.GuideId -cne $guide.SourceId }) + $new)
    $null = Save-ChannelForgeSourceSetEdit -RepositoryRoot $RepositoryRoot -Base $base -PlaylistSources @($base.Playlists) -GuideSources @($base.Guides) -Bindings $bindings
    if ($NoPlaylist -and $old -and ($old.AppliesToAll -or @($old.PlaylistIds).Count -gt 0)) {
        Write-Host "The guide '$($guide.Label)' now serves no playlist."
    }
    return $result
}
