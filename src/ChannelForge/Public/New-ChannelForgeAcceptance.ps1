function New-ChannelForgeAcceptance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CandidateManifest,
        [Parameter(Mandatory)]$DecisionManifest,
        [Parameter(Mandatory)]$M3UDecision,
        [AllowNull()][AllowEmptyCollection()][object[]]$AcceptedParentEntries = @(),
        [Alias('Decisions')][AllowNull()][AllowEmptyCollection()][object[]]$DecisionRecords = @()
    )

    # This is the production acceptance boundary: both output collections are
    # constructed only after the complete decision partition and records pass
    # the same fail-closed coverage validation.
    $acceptedEntries = New-ChannelForgeAcceptedEntries `
        -CandidateManifest $CandidateManifest `
        -DecisionManifest $DecisionManifest `
        -M3UDecision $M3UDecision `
        -AcceptedParentEntries $AcceptedParentEntries `
        -DecisionRecords $DecisionRecords
    $acceptedBindings = New-ChannelForgeAcceptedBindings `
        -CandidateManifest $CandidateManifest `
        -DecisionManifest $DecisionManifest `
        -M3UDecision $M3UDecision `
        -AcceptedParentEntries $AcceptedParentEntries `
        -DecisionRecords $DecisionRecords

    return [pscustomobject][ordered]@{
        AcceptedEntries = @($acceptedEntries)
        AcceptedBindings = @($acceptedBindings)
    }
}
