function Get-ChannelForgeSourceEnrollment {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    return Get-ChannelForgeSourceEnrollmentStatus -RepositoryRoot $RepositoryRoot
}

