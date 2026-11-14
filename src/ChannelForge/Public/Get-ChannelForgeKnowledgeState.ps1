function Get-ChannelForgeKnowledgeState {
    [CmdletBinding()]
    param([string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot))

    return Read-ChannelForgeKnowledgeState -RepositoryRoot $RepositoryRoot
}
