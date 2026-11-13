function Export-ChannelForgeKnowledgeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $paths = Get-ChannelForgeKnowledgePaths -RepositoryRoot $RepositoryRoot
    $state = Read-ChannelForgeKnowledgeState -RepositoryRoot $RepositoryRoot
    $target = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $paths.Root $OutputPath }
    if ([System.IO.Path]::GetFullPath($target) -ceq [System.IO.Path]::GetFullPath($paths.StatePath)) { throw 'KNOWLEDGE_INVALID: export cannot replace the canonical store.' }
    Write-ChannelForgeKnowledgeSnapshot -State $state -Path $target -RepositoryRoot $RepositoryRoot
    return [pscustomobject][ordered]@{ Revision = [int]$state.Revision; StateHash = [string]$state.StateHash; Path = [System.IO.Path]::GetRelativePath($paths.Root,[System.IO.Path]::GetFullPath($target)) }
}
