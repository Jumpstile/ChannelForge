function Get-ChannelForgeWebStatus {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $module = Get-Module -Name ChannelForge | Select-Object -First 1
    $version = if ($null -eq $module) { 'unknown' } else { [string]$module.Version }
    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $RepositoryRoot
    $current = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $RepositoryRoot -Paths $paths
    $lineupStatus = if ($null -eq $current) { 'not-accepted' } else { 'accepted' }
    $guidance = if ($null -eq $current) { 'No lineup has been accepted yet' } else { 'An accepted lineup is available' }
    $nextAction = if ($null -eq $current) { 'Open Guided Setup to begin' } else { 'Open Guided Setup to review' }

    return [pscustomobject][ordered]@{
        Service                = 'ChannelForge'
        Version                = $version
        Status                 = 'ok'
        Message                = 'ChannelForge is running'
        LineupStatus           = $lineupStatus
        Guidance               = $guidance
        NextAction             = $nextAction
        ReadOnly               = $true
        ProviderMutation       = 'none'
        DownstreamMutation     = 'none'
        GuidePublication       = 'none'
        AcceptedStateMutation = 'none'
    }
}
