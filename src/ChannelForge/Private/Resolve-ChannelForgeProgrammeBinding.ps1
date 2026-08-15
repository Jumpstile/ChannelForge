function Resolve-ChannelForgeProgrammeBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$Programme
    )

    if ($null -eq $Programme -or $Programme -isnot [Programme]) {
        throw 'Programme binding requires a Programme domain object.'
    }

    $sourceId = if ($null -eq $Programme.SourceId) { '' } else { $Programme.SourceId.Trim() }
    $channelReference = if ($null -eq $Programme.ChannelId) { '' } else { $Programme.ChannelId.Trim() }

    if ([string]::IsNullOrWhiteSpace($sourceId)) {
        throw 'Programme binding requires a non-empty Programme SourceId.'
    }

    if ([string]::IsNullOrWhiteSpace($channelReference)) {
        throw 'Programme binding requires a non-empty Programme ChannelId.'
    }

    if ($Programme.End -le $Programme.Start) {
        throw 'Programme binding requires a positive Programme interval.'
    }

    if ($null -ne $Programme.Evidence -and $null -ne $Programme.Evidence.PSObject.Properties['SourceId']) {
        $evidenceSourceId = [string]$Programme.Evidence.SourceId
        if (-not [string]::IsNullOrWhiteSpace($evidenceSourceId) -and
            -not [string]::Equals($sourceId, $evidenceSourceId.Trim(), [System.StringComparison]::Ordinal)) {
            throw "Programme SourceId '$sourceId' does not match evidence SourceId '$($evidenceSourceId.Trim())'."
        }
    }

    $binding = [ProgrammeChannelBinding]::new()
    $binding.SourceId = $sourceId
    $binding.ChannelReference = $channelReference
    $binding.BindingKey = New-ChannelForgeProgrammeBindingKey -SourceId $sourceId -ChannelReference $channelReference
    $binding.BindingKind = 'SourceScoped'

    return $binding
}
