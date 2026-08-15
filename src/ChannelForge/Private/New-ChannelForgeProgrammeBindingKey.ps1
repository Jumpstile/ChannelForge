function New-ChannelForgeProgrammeBindingKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$ChannelReference
    )

    $normalizedSourceId = $SourceId.Trim()
    $normalizedChannelReference = $ChannelReference.Trim()

    if ([string]::IsNullOrWhiteSpace($normalizedSourceId)) {
        throw 'Programme binding SourceId cannot be empty.'
    }

    if ([string]::IsNullOrWhiteSpace($normalizedChannelReference)) {
        throw 'Programme binding ChannelReference cannot be empty.'
    }

    # Length prefixes keep the key unambiguous even when either opaque
    # identifier contains the separator or another identifier's prefix.
    return ('{0}:{1}|{2}:{3}' -f
        $normalizedSourceId.Length,
        $normalizedSourceId,
        $normalizedChannelReference.Length,
        $normalizedChannelReference)
}
