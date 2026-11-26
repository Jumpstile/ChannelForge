function New-ChannelForgeWebServer {
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)]
        [int]$Port = 8765,

        [ValidateNotNullOrEmpty()]
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

    # Loopback is always allowed. Any other address needs sign-in and a config folder, and the start guard must agree.
    $guard = if ($ConfigRoot) { Get-ChannelForgeStartGuard -Address $BindAddress -ConfigRoot $ConfigRoot -AllowSetupMode } else { $null }
    if ($BindAddress.Trim().Trim('[', ']') -notin @('127.0.0.1', '::1', 'localhost') -and -not ($RequireSignIn -and $guard.State -in @('Ready', 'SetupRequired'))) {
        $reason = if ($guard -and $guard.Reason) { " $($guard.Reason)" } else { '' }
        throw [System.ArgumentException]::new("ChannelForge will only listen on the network with sign-in turned on and a config folder set.$reason")
    }

    $staticRoot = if ([string]::IsNullOrWhiteSpace($StaticRoot)) { Get-ChannelForgeWebDefaultStaticRoot -RepositoryRoot $RepositoryRoot } else { $StaticRoot }
    $staticRoot = [IO.Path]::GetFullPath($staticRoot)

    $listenHost = if ($BindAddress -in @('0.0.0.0', '::', '[::]')) { '+' } elseif ($BindAddress.Contains(':') -and -not $BindAddress.StartsWith('[')) { "[$BindAddress]" } else { $BindAddress }
    $prefix = "http://$listenHost`:$Port/"
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
