function Set-ChannelForgeUserChannelNumber {
    <#
    .SYNOPSIS
    Saves your own channel number for one channel in state/channel-decisions.json.

    .DESCRIPTION
    The channel is named by its guide ID (TvgId) or, when it has none, by its display name
    after aliases. The number is a whole number from 1 to 9999. It wins over a block number on
    the next run. Saving a number turns an older plain-list decisions file into the v2 file;
    the existing guide choices are kept as they are.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByTvgId')]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory, ParameterSetName = 'ByTvgId')][string]$TvgId,
        [Parameter(Mandatory, ParameterSetName = 'ByName')][string]$Name,
        [Parameter(Mandatory)][object]$Number
    )

    if ($Number -is [string] -and $Number -match '^[0-9]{1,9}$') { $Number = [int]$Number }
    if (-not (Test-ChannelForgeChannelNumberValue -Value $Number)) {
        throw "A channel number must be a whole number from 1 to 9999. '$Number' is not."
    }
    $label = if ($PSCmdlet.ParameterSetName -eq 'ByName') { $Name } else { $TvgId }
    if ([string]::IsNullOrWhiteSpace($label)) { throw 'Name the channel by its guide ID or its display name.' }
    $key = if ($PSCmdlet.ParameterSetName -eq 'ByName') { "name:$($Name.Trim().ToLowerInvariant())" } else { "id:$($TvgId.Trim().ToLowerInvariant())" }

    $path = Join-Path ([System.IO.Path]::GetFullPath($Root)) 'state\channel-decisions.json'
    $guide = @(Read-ChannelForgeChannelDecisions -Path $path)
    $numbers = @(Read-ChannelForgeChannelDecisions -Path $path -Section ChannelNumbers | Where-Object { $_.channelKey -cne $key })
    $numbers += [pscustomobject][ordered]@{
        channelKey = $key
        name       = $label.Trim()
        number     = [int]$Number
        decidedAt  = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-ChannelForgeChannelDecisions -Path $path -Record $guide -NumberRecord $numbers
}
