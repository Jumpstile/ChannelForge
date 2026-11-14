function Add-ChannelForgeSourceSetSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [Parameter(Mandatory)][string]$Path,
        [string]$Label,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $limits = Get-ChannelForgeWebProposalLimits
    if ($PSBoundParameters.ContainsKey('Label') -and ([string]::IsNullOrWhiteSpace($Label) -or $Label.Length -gt $limits.MaxLabelLength -or $Label -match '[\x00-\x1F\x7F]')) {
        throw 'SOURCE_ENROLLMENT_INVALID: the source label is invalid.'
    }
    $bytes = Read-ChannelForgeSourceSetFileBytes -Kind $Kind -Path $Path
    $base = Get-ChannelForgeSourceSetEditBase -RepositoryRoot $RepositoryRoot
    if ($Kind -eq 'XMLTV' -and @($base.Playlists).Count -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: add a playlist before adding a guide.' }

    $group = if ($Kind -eq 'M3U') { @($base.Playlists) } else { @($base.Guides) }
    $source = [pscustomobject][ordered]@{
        Kind = $Kind; SourceKind = 'managed-file'; Bytes = $bytes
        SourceId = Get-ChannelForgeSourceSetSourceId -Kind $Kind -SourceKind 'managed-file' -SourceKey ([guid]::NewGuid().ToString('N'))
        Label = if ($PSBoundParameters.ContainsKey('Label')) { $Label } else { $null }
        Priority = if ($group.Count -eq 0) { 100 } else { [int]($group | Measure-Object -Property Priority -Maximum).Maximum + 1 }
    }
    $playlists = @($base.Playlists)
    $guides = @($base.Guides)
    $bindings = @($base.Bindings)
    if ($Kind -eq 'M3U') { $playlists += $source }
    else {
        $guides += $source
        # The one-playlist default binding, exactly as the browser path makes it. With several playlists the guide stays unbound.
        if ($playlists.Count -eq 1) {
            $bindings += [pscustomobject][ordered]@{ GuideId = $source.SourceId; PlaylistIds = @([string]$playlists[0].SourceId); AppliesToAll = $false; ExplicitlyUnbound = $false; Revision = 1; Enabled = $true }
        }
    }
    try {
        $saved = Save-ChannelForgeSourceSetEdit -RepositoryRoot $RepositoryRoot -Base $base -PlaylistSources $playlists -GuideSources $guides -Bindings $bindings
    }
    catch {
        $failure = $_
        # The new snapshot is the only file this call created. Remove it so a refused add leaves nothing behind.
        $extension = if ($Kind -eq 'M3U') { 'm3u' } else { 'xml' }
        Remove-ChannelForgeManagedSourceSnapshot -RepositoryRoot $RepositoryRoot -ManagedPath "state/managed-sources/$($source.SourceId).$extension"
        throw $failure
    }
    $record = @(@($saved.Playlists) + @($saved.Guides) | Where-Object { [string]$_.SourceId -ceq $source.SourceId })[0]
    return [pscustomobject][ordered]@{ SourceId = [string]$record.SourceId; Kind = $Kind; Label = [string]$record.Label }
}
