function New-ChannelForgeEnrolledCandidate {
    param(
        [Parameter(Mandatory)]$EnrollmentInputs,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ReplacementSourceId,
        [Parameter(Mandatory)][string]$ReplacementPath,
        [Parameter(Mandatory)][string]$OutputRoot
    )
    $makeSources = {
        param($records, [string]$kind)
        foreach ($record in @($records | Where-Object Enabled | Sort-Object Priority, OrderKey, SourceId) ) {
            $path = if ([string]$record.SourceId -eq $ReplacementSourceId) {
                $ReplacementPath
            } elseif ([string]::IsNullOrWhiteSpace([string]$record.ManagedPath)) {
                throw "Enrolled $kind source has no last-known-good snapshot."
            } else {
                Join-Path $RepositoryRoot ([string]$record.ManagedPath -replace '/', '\')
            }
            if (-not [IO.File]::Exists($path)) { throw "Enrolled $kind source snapshot is unavailable." }
            [pscustomobject]@{
                Kind = $kind
                SourceId = [string]$record.SourceId
                SourceKey = [string]$record.SourceId
                Label = [string]$record.Label
                Priority = [int]$record.Priority
                SourceKind = [string]$record.SourceKind
                Url = if ($record.PSObject.Properties.Name -contains 'Url') { [string]$record.Url } else { $null }
                Path = [IO.Path]::GetFullPath($path)
            }
        }
    }
    $playlists = @(& $makeSources $EnrollmentInputs.Enrollment.Playlists 'M3U')
    $guides = @(& $makeSources $EnrollmentInputs.Enrollment.Guides 'XMLTV')
    return New-ChannelForgeSourceSetCandidateProposal `
        -Root $RepositoryRoot `
        -PlaylistSources $playlists `
        -GuideSources $guides `
        -Bindings @($EnrollmentInputs.Bindings) `
        -OutputRoot $OutputRoot `
        -CandidateContractVersion 'blocker-2-contract/v7'
}
