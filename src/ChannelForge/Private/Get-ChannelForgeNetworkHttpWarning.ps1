function Get-ChannelForgeNetworkHttpWarning {
    # Plain HTTP on a network: warn only (owner decision). Loopback gets no warning.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BindAddress)
    $bindHost = $BindAddress.Trim('[', ']')
    $ip = $null
    if ($bindHost -eq 'localhost' -or ([Net.IPAddress]::TryParse($bindHost, [ref]$ip) -and [Net.IPAddress]::IsLoopback($ip))) { return $null }
    'This server is open to your network over plain HTTP. Anyone on the network can read what you type, including your password. Put a reverse proxy with HTTPS in front of it.'
}
