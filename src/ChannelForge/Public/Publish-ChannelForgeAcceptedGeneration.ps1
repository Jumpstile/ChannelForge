function Publish-ChannelForgeAcceptedGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RepositoryRoot,
        [Parameter(Mandatory)][ValidateNotNull()]$GenerationManifest,
        [Parameter(Mandatory)][ValidateNotNull()]$AcceptedState,
        [Parameter(Mandatory)][ValidateNotNull()]$AcceptedOutputManifest,
        [Parameter(Mandatory)][ValidateNotNull()]$DecisionManifest,
        [Parameter(Mandatory)][ValidateNotNull()][byte[]]$M3UBytes,
        [AllowNull()][byte[]]$XMLTVBytes,
        [AllowNull()][ValidateNotNullOrEmpty()][string]$FaultHook
    )
    Publish-ChannelForgeGenerationCore @PSBoundParameters
}
