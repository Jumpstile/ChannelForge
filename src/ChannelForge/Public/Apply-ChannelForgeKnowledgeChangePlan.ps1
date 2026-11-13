function Apply-ChannelForgeKnowledgeChangePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][ValidateSet('APPLY')][string]$ConfirmApply,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),
        [datetimeoffset]$AppliedAtUtc = ([datetimeoffset]::UtcNow)
    )

    $state = Read-ChannelForgeKnowledgeState -RepositoryRoot $RepositoryRoot
    $next = Invoke-ChannelForgeKnowledgeChangePlanInternal -State $state -Plan $Plan -AppliedAtUtc $AppliedAtUtc
    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    Assert-ChannelForgeKnowledgeState -State $next -SchemaPath $paths.SchemaPath
    Write-ChannelForgeKnowledgeStateAtomic -State $next -RepositoryRoot $RepositoryRoot
    return $next
}
