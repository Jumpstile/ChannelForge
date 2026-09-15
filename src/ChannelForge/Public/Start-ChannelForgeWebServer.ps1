function Start-ChannelForgeWebServer {
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)]
        [int]$Port = 8765,

        [ValidateSet('127.0.0.1', '[::1]')]
        [string]$BindAddress = '127.0.0.1',

        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $server = New-ChannelForgeWebServer -Port $Port -BindAddress $BindAddress -RepositoryRoot $RepositoryRoot
    try {
        $server.Listener.Start()
        $server.Started = $true
        Write-Host "ChannelForge is running at $($server.Prefix)"
        Write-Host 'Open Guided Setup to begin.'

        while ($server.Listener.IsListening) {
            $context = $null
            try {
                $context = $server.Listener.GetContext()
            }
            catch {
                if ($server.Listener.IsListening) { throw }
                return
            }

            try {
                $requestPath = $context.Request.Url.AbsolutePath
                $response = Get-ChannelForgeWebResponse -Method $context.Request.HttpMethod -Path $requestPath -RepositoryRoot $server.RepositoryRoot
                Write-ChannelForgeWebResponse -Context $context -Response $response
            }
            finally {
                if ($null -ne $context) { $context.Response.Close() }
            }
        }
    }
    finally {
        if ($server.Listener.IsListening) { $server.Listener.Stop() }
        $server.Listener.Close()
    }
}
