function Get-ChannelForgeWebStatus {
    [CmdletBinding()]
    param()

    $module = Get-Module -Name ChannelForge | Select-Object -First 1
    $version = if ($null -eq $module) { 'unknown' } else { [string]$module.Version }

    return [pscustomobject][ordered]@{
        Service                 = 'ChannelForge'
        Version                 = $version
        Status                  = 'ok'
        Message                 = 'ChannelForge is running'
        LineupStatus            = 'not-accepted'
        Guidance                = 'No lineup has been accepted yet'
        NextAction              = 'Open Guided Setup to begin'
        ReadOnly                = $true
        ProviderMutation        = 'none'
        DownstreamMutation      = 'none'
        GuidePublication        = 'none'
        AcceptedStateMutation  = 'none'
    }
}
