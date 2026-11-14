function Read-ChannelForgeCandidateChannels {
    # The channels of a sealed candidate, read from its merged.m3u. Read only.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $manifest = $utf8.GetString([System.IO.File]::ReadAllBytes((Join-Path $Directory 'manifest.json'))) | ConvertFrom-Json
    $reader = [System.IO.StreamReader]::new((Join-Path $Directory 'merged.m3u'), $utf8)
    try { return @(Read-ChannelForgeM3UReader -Reader $reader -CandidateContractVersion ([string]$manifest.ContractVersion)) }
    finally { $reader.Dispose() }
}
