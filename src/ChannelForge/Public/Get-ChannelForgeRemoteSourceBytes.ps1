function Get-ChannelForgeRemoteSourceBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][int]$MaxBytes
    )

    return Read-ChannelForgeGuidedSetupRemoteBytes -Kind $Kind -Url $Url -MaxBytes $MaxBytes
}
