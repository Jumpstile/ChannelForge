function New-ChannelForgeWebServer {
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)]
        [int]$Port = 8765,

        [ValidateSet('127.0.0.1', '[::1]')]
        [string]$BindAddress = '127.0.0.1'
    )

    $prefix = "http://$BindAddress`:$Port/"
    $listener = [System.Net.HttpListener]::new()
    [void]$listener.Prefixes.Add($prefix)

    return [pscustomobject][ordered]@{
        Prefix      = $prefix
        BindAddress = $BindAddress
        Port        = $Port
        Listener    = $listener
        Started     = $false
    }
}
