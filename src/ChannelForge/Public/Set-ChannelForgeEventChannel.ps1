function Set-ChannelForgeEventChannel {
    <#
    .SYNOPSIS
    Forces one channel on or off as an event channel, or removes that choice.

    .DESCRIPTION
    Writes state\event-channels.json (contract event-channel/v2). Copy the ChannelKey from
    Get-ChannelForgeEventChannelReport. ForceOn asks for an event guide for the channel
    (it still keeps its normal guide if its times cannot be used). ForceOff keeps the normal
    guide. Only the record for that key changes. A damaged file stops the command; it is
    never repaired or replaced. Nothing needs this command.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Set')]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ChannelKey,
        [Parameter(Mandatory, ParameterSetName = 'Set')][ValidateSet('ForceOn', 'ForceOff')][string]$Decision,
        [Parameter(ParameterSetName = 'Set')][string]$Name = '',
        [Parameter(Mandatory, ParameterSetName = 'Clear')][switch]$Clear,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $paths = Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot
    $path = Join-Path $paths.StateRoot 'event-channels.json'
    $records = @(Read-ChannelForgeEventChannelOverrides -Path $path)
    $others = @($records | Where-Object { $_.key -cne $ChannelKey })
    $existing = @($records | Where-Object { $_.key -ceq $ChannelKey }) | Select-Object -First 1

    if ($Clear) {
        if ($null -eq $existing) { Write-Warning 'That channel has no override. Nothing was written.'; return }
        $new = $others
    }
    else {
        $label = if ($Name) { $Name } elseif ($existing) { $existing.name } else { '' }
        $new = $others + [pscustomobject][ordered]@{
            key       = $ChannelKey
            name      = ConvertTo-ChannelForgeGuideSafeText -Value $label
            decision  = $(if ($Decision -ceq 'ForceOn') { 'forceOn' } else { 'forceOff' })
            decidedAt = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        }
    }

    if ($PSCmdlet.ShouldProcess($path, 'Save event channel overrides')) {
        $document = [ordered]@{ version = 'event-channel/v2'; overrides = @($new | Sort-Object { $_.key }) }
        Write-ChannelForgeSourceEnrollmentAtomicJson -Path $path -Value $document -AllowedRoot $paths.StateRoot
    }
}
