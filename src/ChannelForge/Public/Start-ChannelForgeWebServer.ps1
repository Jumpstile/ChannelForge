function Start-ChannelForgeWebServer {
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
    $server = New-ChannelForgeWebServer -Port $Port -BindAddress $BindAddress -RepositoryRoot $RepositoryRoot -StaticRoot $StaticRoot -RequireSignIn:$RequireSignIn -ConfigRoot $ConfigRoot -AllowedHost $AllowedHost
    try {
        $server.Listener.Start()
        $server.Started = $true
        Write-Host "ChannelForge is running at $($server.Prefix)"
        Write-Host 'Open Guided Setup to begin.'
        if ($server.RequireSignIn -and (Test-ChannelForgeSetupState -ConfigRoot $server.ConfigRoot)) {
            # The one place the setup code is shown. It is kept nowhere else and is never written to a file.
            Write-Host "First-time setup: open $($server.Prefix)first-run and type this one-time setup code: $(New-ChannelForgeSetupCode -Setup $server.Setup)"
            Write-Host "The code works once and stops working after $([int](Get-ChannelForgeSetupCodeLifetime).TotalMinutes) minutes. Start the server again for a new one."
        }

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
                $requestPathAndQuery = $context.Request.Url.PathAndQuery
                $isBodyPost = $context.Request.HttpMethod.ToUpperInvariant() -eq 'POST' -and $requestPath.ToLowerInvariant() -in @('/api/guided-setup/proposal', '/api/guided-setup/accept', '/api/sources/refresh', '/api/sources/remove')
                $gateResponse = $null
                if ($server.RequireSignIn) {
                    $request = $context.Request
                    $gateResponse = Get-ChannelForgeWebRequestRefusal -Method $request.HttpMethod -Port $server.Port -AllowedHost $server.AllowedHost -Scheme $request.Url.Scheme -HostHeader $request.Headers['Host'] -Origin $request.Headers['Origin'] -Referer $request.Headers['Referer'] -ContentType $request.ContentType
                    if ($null -eq $gateResponse) {
                        # The peer address, never a header: X-Forwarded-For can be forged.
                        $gateResponse = Get-ChannelForgeWebSignInResponse -Store $server.Sessions -Setup $server.Setup -Limiter $server.Limiter -SourceAddress $request.RemoteEndPoint.Address.ToString() -RequestHost $request.Url.Host -Method $request.HttpMethod -Path $requestPathAndQuery -CookieHeader $request.Headers['Cookie'] -BodyStream $request.InputStream -ContentLength $request.ContentLength64 -ConfigRoot $server.ConfigRoot -Secure:($server.Prefix -like 'https:*')
                    }
                }
                if ($null -ne $gateResponse) {
                    $response = $gateResponse
                }
                elseif ($isBodyPost) {
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
                    $response = Get-ChannelForgeWebResponse -Method $context.Request.HttpMethod -Path $requestPathAndQuery -RepositoryRoot $server.RepositoryRoot -StaticRoot $server.StaticRoot
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
