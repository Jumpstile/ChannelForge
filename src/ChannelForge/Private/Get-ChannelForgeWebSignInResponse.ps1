function Get-ChannelForgeWebSessionCookieValue {
    param([AllowNull()][AllowEmptyString()][string]$CookieHeader)
    foreach ($part in ([string]$CookieHeader -split ';')) {
        $pair = $part.Trim() -split '=', 2
        if ($pair.Count -eq 2 -and $pair[0] -ceq 'cf_session') { return $pair[1] }
    }
    return $null
}

function New-ChannelForgeWebSignInJsonResponse {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][hashtable]$Body,
        [System.Collections.IDictionary]$ExtraHeaders = @{}
    )
    $headers = [ordered]@{ 'Cache-Control' = 'no-store'; 'X-Content-Type-Options' = 'nosniff' }
    foreach ($header in $ExtraHeaders.GetEnumerator()) { $headers[$header.Key] = $header.Value }
    return New-ChannelForgeWebResponse -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8' -Body ($Body | ConvertTo-Json -Compress) -Headers $headers
}

function Get-ChannelForgeWebSignInResponse {
    <#
    .SYNOPSIS
        The sign-in check for "sign-in required" mode. Returns a response to send, or $null when the request may go on to the normal routes.
    .DESCRIPTION
        Handles POST /api/auth/sign-in, POST /api/auth/sign-out and GET /api/auth/session.
        /health without a session returns no data. Every other route needs a live session, else a plain 401.
        Passwords, tokens and cookies are never logged or echoed.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][AllowEmptyString()][string]$CookieHeader,
        [System.IO.Stream]$BodyStream = $null,
        [long]$ContentLength = -1,
        [Parameter(Mandatory)][string]$ConfigRoot,
        [hashtable]$Setup = @{},
        [string]$RequestHost = '',
        [switch]$Secure,
        [hashtable]$Limiter = $null,
        [string]$SourceAddress = '',
        [string]$StaticIndexPath = '',
        [datetime]$Now = [datetime]::UtcNow
    )

    $requestPath = ($Path -split '\?', 2)[0].ToLowerInvariant()
    $methodName = $Method.ToUpperInvariant()
    $token = Get-ChannelForgeWebSessionCookieValue -CookieHeader $CookieHeader
    $cookieBase = 'cf_session={0}; Path=/; HttpOnly; SameSite=Strict' + $(if ($Secure) { '; Secure' } else { '' })

    switch ($requestPath) {
        '/api/auth/sign-in' {
            if ($methodName -ne 'POST') { return New-ChannelForgeWebSignInJsonResponse -StatusCode 405 -Body @{ Error = 'method-not-allowed'; Message = 'Only POST requests are supported.' } -ExtraHeaders @{ Allow = 'POST' } }
            $waitResponse = Get-ChannelForgeSignInWaitResponse -Limiter $Limiter -Address $SourceAddress -Now $Now
            if ($null -ne $waitResponse) { return $waitResponse }
            $password = $null
            try {
                $bytes = Read-ChannelForgeWebRequestBody -Stream $BodyStream -ContentLength $ContentLength -MaxBytes 4096
                $password = [string]([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop).password
            }
            catch { $password = $null }
            $record = (Read-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot).Record
            if (-not (Test-ChannelForgeAdminPassword -Password $password -Record $record)) {
                if ($null -ne $Limiter) { Register-ChannelForgeSignInFailure -Limiter $Limiter -Address $SourceAddress -Now $Now }
                return New-ChannelForgeWebSignInJsonResponse -StatusCode 401 -Body @{ Error = 'sign-in-failed'; Message = 'That password did not work.' }
            }
            if ($null -ne $Limiter) { Clear-ChannelForgeSignInFailure -Limiter $Limiter -Address $SourceAddress }
            $newToken = New-ChannelForgeWebSession -Store $Store -Now $Now
            return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ SignedIn = $true } -ExtraHeaders @{ 'Set-Cookie' = ($cookieBase -f $newToken) }
        }
        '/api/auth/sign-out' {
            if ($methodName -ne 'POST') { return New-ChannelForgeWebSignInJsonResponse -StatusCode 405 -Body @{ Error = 'method-not-allowed'; Message = 'Only POST requests are supported.' } -ExtraHeaders @{ Allow = 'POST' } }
            Remove-ChannelForgeWebSession -Store $Store -Token $token
            return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ SignedIn = $false } -ExtraHeaders @{ 'Set-Cookie' = (($cookieBase -f '') + '; Max-Age=0') }
        }
    }

    $signedIn = $null -ne (Get-ChannelForgeWebSession -Store $Store -Token $token -Now $Now)
    if ($requestPath -eq '/api/auth/session' -and $methodName -eq 'GET') {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ SignedIn = $signedIn }
    }
    if ($signedIn -and $requestPath -eq '/api/auth/change-password') {
        if ($methodName -ne 'POST') { return New-ChannelForgeWebSignInJsonResponse -StatusCode 405 -Body @{ Error = 'method-not-allowed'; Message = 'Only POST requests are supported.' } -ExtraHeaders @{ Allow = 'POST' } }
        return Invoke-ChannelForgeChangePassword -Store $Store -Token $token -BodyStream $BodyStream -ContentLength $ContentLength -ConfigRoot $ConfigRoot -Limiter $Limiter -SourceAddress $SourceAddress -Now $Now
    }
    if ($signedIn) { return $null }

    if ($requestPath -in @('/first-run', '/first-run/submit') -and (Test-ChannelForgeSetupState -ConfigRoot $ConfigRoot)) {
        return Get-ChannelForgeFirstRunResponse -Method $methodName -RequestPath $requestPath -Store $Store -Setup $Setup -BodyStream $BodyStream -ContentLength $ContentLength -ConfigRoot $ConfigRoot -CookieFormat $cookieBase -RequestHost $RequestHost -Limiter $Limiter -SourceAddress $SourceAddress -Secure:$Secure -Now $Now
    }
    # The page that shows the sign-in form must load without a session. Only a built page shell and its program files pass.
    # With no built page the server would fall back to a status placeholder, so that stays behind sign-in.
    $hasBuiltPage = -not [string]::IsNullOrWhiteSpace($StaticIndexPath) -and (Test-Path -LiteralPath $StaticIndexPath -PathType Leaf)
    if ($hasBuiltPage -and $methodName -eq 'GET' -and ($requestPath -in @('/', '/index.html') -or $requestPath.StartsWith('/assets/'))) { return $null }
    if ($requestPath -eq '/health') { return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ Status = 'ok' } }
    return New-ChannelForgeWebSignInJsonResponse -StatusCode 401 -Body @{ Error = 'sign-in-required'; Message = 'Sign in is required.' }
}
