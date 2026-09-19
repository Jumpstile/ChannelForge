function Start-ChannelForgeWebServer {
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
    $server = New-ChannelForgeWebServer -Port $Port -BindAddress $BindAddress -RepositoryRoot $RepositoryRoot -StaticRoot $StaticRoot
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
                $isBodyPost = $context.Request.HttpMethod.ToUpperInvariant() -eq 'POST' -and $requestPath.ToLowerInvariant() -in @('/api/guided-setup/proposal', '/api/guided-setup/accept')
                if ($isBodyPost) {
                    try {
                        $bodyBytes = Read-ChannelForgeWebRequestBody -Stream $context.Request.InputStream -ContentLength $context.Request.ContentLength64
                        $response = Get-ChannelForgeWebResponse `
                            -Method $context.Request.HttpMethod `
                            -Path $requestPath `
                            -RepositoryRoot $server.RepositoryRoot `
                            -StaticRoot $server.StaticRoot `
                            -BodyBytes $bodyBytes `
                            -ContentType $context.Request.ContentType `
                            -ContentLength $context.Request.ContentLength64
                    }
                    catch [System.InvalidOperationException] {
                        $headers = [ordered]@{ 'Cache-Control' = 'no-store'; 'X-Content-Type-Options' = 'nosniff' }
                        $response = New-ChannelForgeWebProposalErrorResponse -StatusCode 413 -ErrorCode 'request-too-large' -Message 'The proposal request is too large.' -Headers $headers
                    }
                    catch {
                        $headers = [ordered]@{ 'Cache-Control' = 'no-store'; 'X-Content-Type-Options' = 'nosniff' }
                        $response = New-ChannelForgeWebProposalErrorResponse -StatusCode 400 -ErrorCode 'invalid-request-body' -Message 'The proposal request body is invalid.' -Headers $headers
                    }
                }
                else {
                    $response = Get-ChannelForgeWebResponse -Method $context.Request.HttpMethod -Path $requestPath -RepositoryRoot $server.RepositoryRoot -StaticRoot $server.StaticRoot
                }
                Write-ChannelForgeWebResponse -Context $context -Response $response
            }
            catch {
                $headers = [ordered]@{ 'Cache-Control' = 'no-store'; 'X-Content-Type-Options' = 'nosniff' }
                $response = New-ChannelForgeWebProposalErrorResponse -StatusCode 500 -ErrorCode 'request-failed' -Message 'ChannelForge could not complete the request.' -Headers $headers
                try { Write-ChannelForgeWebResponse -Context $context -Response $response } catch {}
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
