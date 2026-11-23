function Add-ChannelForgeCredentialedSourceSetSource {
    # Adds one credentialed remote source (CredentialRef + DisplayHost, no link) to the saved source set.
    # Optional Bytes become the first snapshot through the same save path as every other source. If the save fails, that snapshot is removed.
    # Same shape and default binding as Add-ChannelForgeSourceSetSource. Failures carry fixed text from the write path.
    param(
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [Parameter(Mandatory)][string]$CredentialRef,
        [Parameter(Mandatory)][string]$DisplayHost,
        [string]$Label,
        [byte[]]$Bytes,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )
    $base = Get-ChannelForgeSourceSetEditBase -RepositoryRoot $RepositoryRoot
    if ($Kind -eq 'XMLTV' -and @($base.Playlists).Count -eq 0) { throw 'SOURCE_ENROLLMENT_INVALID: add a playlist before adding a guide.' }
    $group = if ($Kind -eq 'M3U') { @($base.Playlists) } else { @($base.Guides) }
    $source = [pscustomobject][ordered]@{
        Kind = $Kind; SourceKind = 'public-https'; Url = $null; CredentialRef = $CredentialRef; DisplayHost = $DisplayHost
        SourceId = Get-ChannelForgeSourceSetSourceId -Kind $Kind -SourceKind 'public-https' -SourceKey "$DisplayHost|$CredentialRef"
        Label = if ([string]::IsNullOrWhiteSpace($Label)) { $null } else { $Label }
        Bytes = $Bytes
        Priority = if ($group.Count -eq 0) { 100 } else { [int]($group | Measure-Object -Property Priority -Maximum).Maximum + 1 }
    }
    $playlists = @($base.Playlists)
    $guides = @($base.Guides)
    $bindings = @($base.Bindings)
    if ($Kind -eq 'M3U') { $playlists += $source }
    else {
        $guides += $source
        if ($playlists.Count -eq 1) {
            $bindings += [pscustomobject][ordered]@{ GuideId = $source.SourceId; PlaylistIds = @([string]$playlists[0].SourceId); AppliesToAll = $false; ExplicitlyUnbound = $false; Revision = 1; Enabled = $true }
        }
    }
    try { $null = Save-ChannelForgeSourceSetEdit -RepositoryRoot $RepositoryRoot -Base $base -PlaylistSources $playlists -GuideSources $guides -Bindings $bindings }
    catch {
        $failure = $_
        if ($null -ne $Bytes) { Remove-ChannelForgeManagedSourceSnapshot -RepositoryRoot $RepositoryRoot -ManagedPath "state/managed-sources/$($source.SourceId).$(if ($Kind -eq 'M3U') { 'm3u' } else { 'xml' })" }
        throw $failure
    }
}
