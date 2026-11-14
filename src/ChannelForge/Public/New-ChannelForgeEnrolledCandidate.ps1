function New-ChannelForgeEnrolledCandidate {
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(Mandatory)]$EnrollmentInputs,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory, ParameterSetName = 'Single')][string]$ReplacementSourceId,
        [Parameter(Mandatory, ParameterSetName = 'Single')][string]$ReplacementPath,
        [Parameter(ParameterSetName = 'List')][AllowEmptyCollection()][object[]]$Replacement = @(),
        [Parameter(Mandatory)][string]$OutputRoot
    )
    $replacements = @{}
    if ($PSCmdlet.ParameterSetName -eq 'Single') { $replacements[$ReplacementSourceId] = $ReplacementPath }
    else { foreach ($item in $Replacement) { $replacements[[string]$item.SourceId] = [string]$item.Path } }
    $used = [System.Collections.Generic.HashSet[string]]::new()
    $makeSources = {
        param($records, [string]$kind)
        foreach ($record in @($records | Where-Object Enabled | Sort-Object Priority, OrderKey, SourceId) ) {
            $path = if ($replacements.ContainsKey([string]$record.SourceId)) {
                [void]$used.Add([string]$record.SourceId)
                $replacements[[string]$record.SourceId]
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
    if ($used.Count -ne $replacements.Count) { throw 'Replacement source is not an enabled source of the saved set.' }
    return New-ChannelForgeSourceSetCandidateProposal `
        -Root $RepositoryRoot `
        -PlaylistSources $playlists `
        -GuideSources $guides `
        -Bindings @($EnrollmentInputs.Bindings) `
        -OutputRoot $OutputRoot `
        -CandidateContractVersion 'blocker-2-contract/v7'
}
