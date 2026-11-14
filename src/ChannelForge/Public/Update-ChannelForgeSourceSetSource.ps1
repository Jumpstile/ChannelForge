function Update-ChannelForgeSourceSetSource {
    <#
    .SYNOPSIS
    After a reviewed refresh candidate is accepted, saves its refreshed bytes into the saved source set.
    .DESCRIPTION
    Run this after the candidate was accepted. Give the candidate folder and its manifest hash.
    For a refreshed remote source, pass -Replacement (objects with SourceId and Path) pointing at the refreshed
    bytes the candidate was built from. A changed local source is read from its saved copy.
    Every enabled source must match the candidate's input hashes, or nothing is changed.
    Each changed source keeps its ID, label, priority, enabled state and bindings. Its new copy is named by
    its content hash. The old copy is deleted only after the set file was saved.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [Parameter(Mandatory)][string]$CandidateManifestHash,
        [AllowEmptyCollection()][object[]]$Replacement = @(),
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    if (-not (Test-ChannelForgeCandidateNamespace -Directory $CandidateDirectory -ManifestHash $CandidateManifestHash)) {
        throw 'SOURCE_ENROLLMENT_INVALID: the candidate is not valid.'
    }
    $manifest = Get-Content -LiteralPath (Join-Path $CandidateDirectory 'manifest.json') -Raw | ConvertFrom-Json
    $base = Get-ChannelForgeSourceSetEditBase -RepositoryRoot $RepositoryRoot -AllowChanged
    $replacementPath = @{}
    foreach ($item in $Replacement) { $replacementPath[[string]$item.SourceId] = [string]$item.Path }

    $sources = @(@($base.Playlists) + @($base.Guides))
    $seen = [System.Collections.Generic.List[string]]::new()
    $inputs = [System.Collections.Generic.List[string]]::new()
    $changed = [System.Collections.Generic.List[object]]::new()
    foreach ($source in $sources) {
        $hasReplacement = $replacementPath.ContainsKey([string]$source.SourceId)
        $bytes = if ($hasReplacement) { [System.IO.File]::ReadAllBytes($replacementPath[[string]$source.SourceId]) }
        elseif ($null -ne $source.PSObject.Properties['Bytes']) { $source.Bytes }
        else { $null }
        if ($hasReplacement) { $seen.Add([string]$source.SourceId) }
        if ($null -eq $bytes) {
            if ($source.Enabled) { throw 'SOURCE_ENROLLMENT_INVALID: a saved source has no saved copy.' }
            continue
        }
        $hash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes $bytes
        if ($source.Enabled) {
            $domain = if ($source.Kind -eq 'M3U') { 'input-m3u/v2' } else { 'input-xmltv/v2' }
            $inputs.Add("$($source.Kind)|$(Get-ChannelForgeDomainHash -Domain $domain -Bytes $bytes)")
        }
        if ($hash -ceq [string]$source.ContentHash) { continue }
        # A disabled source is not in the candidate, so its changes are not covered.
        if (-not $source.Enabled) { throw 'SOURCE_ENROLLMENT_INVALID: a disabled source changed and is not covered by the candidate.' }
        $extension = if ($source.Kind -eq 'M3U') { 'm3u' } else { 'xml' }
        $changed.Add([pscustomobject]@{ Source = $source; Bytes = $bytes; Hash = $hash; OldPath = [string]$source.ManagedPath; NewPath = "state/managed-sources/$hash.$extension" })
    }
    if (@($replacementPath.Keys | Where-Object { $_ -notin $seen }).Count -gt 0) { throw 'SOURCE_ENROLLMENT_INVALID: a replacement is not a source of the saved set.' }
    $expected = @($manifest.InputArtifactHashes | ForEach-Object { "$($_.ArtifactKind)|$($_.ArtifactHash)" } | Sort-Object) -join ','
    if ((@($inputs | Sort-Object) -join ',') -cne $expected) { throw 'SOURCE_ENROLLMENT_INVALID: the saved bytes do not match the candidate.' }
    if ($changed.Count -eq 0) { return @() }

    $oldPaths = @($sources | ForEach-Object { [string]$_.ManagedPath } | Where-Object { $_ })
    foreach ($item in $changed) {
        $item.Source | Add-Member -NotePropertyName Bytes -NotePropertyValue $item.Bytes -Force
        $item.Source.ManagedPath = $item.NewPath
    }
    $finalPaths = @($sources | ForEach-Object { [string]$_.ManagedPath } | Where-Object { $_ })
    if ($finalPaths.Count -ne @($finalPaths | Sort-Object -Unique).Count) { throw 'SOURCE_ENROLLMENT_INVALID: two sources would share one saved copy.' }
    try {
        $null = Save-ChannelForgeSourceSetEdit -RepositoryRoot $RepositoryRoot -Base $base -PlaylistSources @($base.Playlists) -GuideSources @($base.Guides) -Bindings @($base.Bindings)
    }
    catch {
        $failure = $_
        # Remove only the new copies this call made. The old record and its old copy are untouched.
        foreach ($item in $changed) {
            if ($item.NewPath -notin $oldPaths) { try { Remove-ChannelForgeManagedSourceSnapshot -RepositoryRoot $RepositoryRoot -ManagedPath $item.NewPath } catch { Write-Warning 'A new saved copy could not be cleaned up after the failure.' } }
        }
        throw $failure
    }
    # The set file is saved. Only now are the replaced copies deleted.
    foreach ($item in $changed) {
        if ($item.OldPath -and $item.OldPath -notin $finalPaths) {
            try { Remove-ChannelForgeManagedSourceSnapshot -RepositoryRoot $RepositoryRoot -ManagedPath $item.OldPath }
            catch { Write-Warning "The source was updated, but its old saved copy could not be deleted: $($_.Exception.Message)" }
        }
    }
    return @($changed | ForEach-Object { [pscustomobject][ordered]@{ SourceId = [string]$_.Source.SourceId; Kind = [string]$_.Source.Kind; Label = [string]$_.Source.Label; ContentHash = $_.Hash } })
}
