function Get-ChannelForgeEnrolledSourceInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    return Get-ChannelForgeSourceEnrollmentInputs -RepositoryRoot $RepositoryRoot
}
