function New-ChannelForgeSourceSetCandidateProposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object[]]$PlaylistSources,
        [AllowEmptyCollection()][object[]]$GuideSources = @(),
        [AllowEmptyCollection()][object[]]$Bindings = @(),
        [Parameter(Mandatory)][string]$OutputRoot,
        [string]$TransactionId = ([guid]::NewGuid().ToString('N').ToLowerInvariant()),
        [string]$FaultHook = '',
        [ValidateSet('blocker-2-contract/v7')]
        [string]$CandidateContractVersion = 'blocker-2-contract/v7'
    )

    return New-ChannelForgeCandidateProposalFromSourceSet @PSBoundParameters
}
