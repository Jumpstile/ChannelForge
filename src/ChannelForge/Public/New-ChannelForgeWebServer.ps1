function New-ChannelForgeWebServer {
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)]
        [int]$Port = 8765,

        [ValidateSet('127.0.0.1', '[::1]')]
        [string]$BindAddress = '127.0.0.1',

        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),

        [string]$StaticRoot = ''
    )

    $staticRoot = if ([string]::IsNullOrWhiteSpace($StaticRoot)) { Join-Path $RepositoryRoot 'gui\dist' } else { $StaticRoot }
    $staticRoot = [IO.Path]::GetFullPath($staticRoot)

    $prefix = "http://$BindAddress`:$Port/"
    $listener = [System.Net.HttpListener]::new()
    [void]$listener.Prefixes.Add($prefix)

    return [pscustomobject][ordered]@{
        Prefix        = $prefix
        BindAddress   = $BindAddress
        Port          = $Port
        RepositoryRoot = $RepositoryRoot
        StaticRoot    = $staticRoot
        Listener      = $listener
        Started       = $false
    }
}
