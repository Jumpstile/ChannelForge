function Get-ChannelForgeEventChannelReport {
    <#
    .SYNOPSIS
    Lists every channel the event detector rated, with its confidence, reasons and your override.

    .DESCRIPTION
    Read-only (contract event-channel/v2). Reads merged.m3u from a sealed candidate directory and
    any choices in state\event-channels.json. Pass -Programme (provider guide programmes, as the
    build reads them) to let the detector see guide times. A choice whose channel is no longer in
    the candidate is listed as stale; nothing acts on it. A damaged overrides file stops the command.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [AllowEmptyCollection()][object[]]$Programme = @(),
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $directory = [System.IO.Path]::GetFullPath($CandidateDirectory).TrimEnd([char]92, [char]47)
    if (-not (Test-ChannelForgeCandidateNamespace -Directory $directory -ManifestHash (Split-Path -Leaf $directory))) {
        throw 'The candidate directory is not a valid sealed candidate.'
    }
    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $records = @(Read-ChannelForgeEventChannelOverrides -Path (Join-Path $paths.StateRoot 'event-channels.json'))
    $decisionOf = @{}
    foreach ($record in $records) { $decisionOf[$record.key] = $record.decision }

    $inputRows = @(Get-ChannelForgeEventChannelInput -CandidateDirectory $directory -CategoryReport (Get-ChannelForgeCategoryReport -CandidateDirectory $directory -RepositoryRoot $RepositoryRoot) -Programme $Programme)
    $rows = @(Get-ChannelForgeEventChannelCandidate -Channel $inputRows | ForEach-Object {
            [pscustomobject][ordered]@{ ChannelKey = $_.Key; DisplayName = $_.DisplayName; Confidence = $_.Confidence; Reasons = @($_.Reasons); Override = $decisionOf[$_.Key] }
        })
    # A choice on a playlist channel the detector did not score still gets a row, so it can be seen and cleared.
    $rows += @($inputRows | Where-Object { $decisionOf.ContainsKey($_.Key) -and @($rows.ChannelKey) -cnotcontains $_.Key } | ForEach-Object {
            [pscustomobject][ordered]@{ ChannelKey = $_.Key; DisplayName = $_.DisplayName; Confidence = 'none'; Reasons = @('not rated by the detector'); Override = $decisionOf[$_.Key] }
        })
    $stale = @($records | Where-Object { @($inputRows.Key) -cnotcontains $_.key } | ForEach-Object { [pscustomobject][ordered]@{ Key = $_.key; Name = $_.name; Decision = $_.decision } })

    [pscustomobject][ordered]@{ Contract = 'event-channel/v2'; ChannelCount = $rows.Count; Rows = $rows; Stale = $stale }
}
