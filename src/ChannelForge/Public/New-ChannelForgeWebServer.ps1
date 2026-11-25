function New-ChannelForgeWebServer {
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)]
        [int]$Port = 8765,

        [ValidateSet('127.0.0.1', '[::1]')]
        [string]$BindAddress = '127.0.0.1',

        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),

        [string]$StaticRoot = '',

        [switch]$RequireSignIn,

        [string]$ConfigRoot = '',

        [string[]]$AllowedHost = @()
    )

    if ($RequireSignIn -and [string]::IsNullOrWhiteSpace($ConfigRoot)) {
        throw [System.ArgumentException]::new('Sign-in required mode needs a ConfigRoot that holds the admin password file.')
    }

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
        RequireSignIn = [bool]$RequireSignIn
        ConfigRoot    = $ConfigRoot
        Sessions      = @{}
        Setup         = @{}
        Limiter       = (New-ChannelForgeSignInLimiter)
        AllowedHost   = @($AllowedHost)
    }
}
