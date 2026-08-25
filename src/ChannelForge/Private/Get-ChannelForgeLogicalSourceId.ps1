function Get-ChannelForgeLogicalSourceId {
    [CmdletBinding()]
    param(
        [string]$ProviderName = '',
        [string]$SourceName = '',
        [ValidateSet('M3U','XMLTV')]
        [string]$SourceKind = 'M3U',
        [int]$SourceOrdinal = 0
    )

    if ($SourceOrdinal -lt 0) { throw 'SourceOrdinal must be non-negative.' }
    $configuredSourceKey = [ordered]@{
        Version           = 'logical-source-key-v2'
        ProviderComponent = [string]$ProviderName
        SourceComponent   = [string]$SourceName
        SourceKind        = $SourceKind
        SourceOrdinal     = $SourceOrdinal
    }
    $inputObject = [ordered]@{
        Version             = 'logical-source-id-v2'
        SourceKind          = $SourceKind
        ConfiguredSourceKey = $configuredSourceKey
    }
    return Get-ChannelForgeDomainHash -Domain 'logical-source-id/v2' -InputObject $inputObject
}
