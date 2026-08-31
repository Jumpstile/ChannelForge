function Recover-ChannelForgeAcceptedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RepositoryRoot
    )
    Recover-ChannelForgeAcceptedStateCore -RepositoryRoot $RepositoryRoot
}
