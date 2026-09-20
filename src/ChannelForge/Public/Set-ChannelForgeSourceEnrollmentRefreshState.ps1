function Set-ChannelForgeSourceEnrollmentRefreshState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][ValidateSet('up-to-date', 'changes-found')][string]$RefreshStatus
    )

    return Update-ChannelForgeSourceEnrollmentRefreshState -RepositoryRoot $RepositoryRoot -RefreshStatus $RefreshStatus
}
