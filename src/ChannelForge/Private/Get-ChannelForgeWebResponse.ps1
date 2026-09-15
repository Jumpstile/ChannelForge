function New-ChannelForgeWebResponse {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][string]$ContentType,
        [Parameter(Mandatory)][string]$Body,
        [System.Collections.IDictionary]$Headers = [ordered]@{}
    )

    return [pscustomobject][ordered]@{
        StatusCode  = $StatusCode
        ContentType = $ContentType
        Body        = $Body
        Headers     = $Headers
    }
}

function New-ChannelForgeWebStatusUnavailableResponse {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [Parameter(Mandatory)][string]$ContentType
    )

    return New-ChannelForgeWebResponse -StatusCode 503 -ContentType $ContentType -Body (@{
        Error   = 'status-unavailable'
        Message = 'ChannelForge status is temporarily unavailable.'
    } | ConvertTo-Json -Compress) -Headers $Headers
}

function Get-ChannelForgeWebResponse {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot = (Get-Location).Path
    )

    $commonHeaders = [ordered]@{
        'Cache-Control'            = 'no-store'
        'X-Content-Type-Options'  = 'nosniff'
        'Content-Security-Policy' = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"
    }
    $contentType = 'application/json; charset=utf-8'
    $methodName = if ($null -eq $Method) { '' } else { $Method.ToUpperInvariant() }
    $requestPath = if ([string]::IsNullOrWhiteSpace($Path)) { '/' } else { ($Path -split '\?', 2)[0] }

    if ($methodName -notin @('GET', 'HEAD')) {
        $headers = [ordered]@{}
        foreach ($header in $commonHeaders.GetEnumerator()) { $headers[$header.Key] = $header.Value }
        $headers['Allow'] = 'GET, HEAD'
        return New-ChannelForgeWebResponse -StatusCode 405 -ContentType $contentType -Body (@{
            Error   = 'method-not-allowed'
            Message = 'Only read-only GET and HEAD requests are supported.'
        } | ConvertTo-Json -Compress) -Headers $headers
    }

    switch ($requestPath.ToLowerInvariant()) {
        '/' {
            try {
                $webStatus = Get-ChannelForgeWebStatus -RepositoryRoot $RepositoryRoot
            }
            catch {
                return New-ChannelForgeWebStatusUnavailableResponse -Headers $commonHeaders -ContentType $contentType
            }
            $guidance = [System.Net.WebUtility]::HtmlEncode([string]$webStatus.Guidance)
            $nextAction = [System.Net.WebUtility]::HtmlEncode([string]$webStatus.NextAction)
            $body = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ChannelForge</title>
  <style>
    :root { color-scheme: light; font-family: system-ui, sans-serif; }
    body { margin: 0; min-height: 100vh; background: #f5f7fa; color: #172033; }
    main { box-sizing: border-box; max-width: 44rem; margin: 0 auto; padding: 12vh 1.5rem; }
    .eyebrow { color: #52627a; font-size: .8rem; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; }
    h1 { margin: .5rem 0 1rem; font-size: clamp(2rem, 6vw, 3.5rem); }
    p { font-size: 1.15rem; line-height: 1.6; }
    .status { border-left: .3rem solid #28784a; padding-left: 1rem; }
  </style>
</head>
<body>
  <main>
    <p class="eyebrow">ChannelForge</p>
    <h1>ChannelForge is running</h1>
    <div class="status">
      <p>$guidance</p>
      <p>$nextAction</p>
    </div>
  </main>
</body>
</html>
"@
            $headers = [ordered]@{}
            foreach ($header in $commonHeaders.GetEnumerator()) { $headers[$header.Key] = $header.Value }
            return New-ChannelForgeWebResponse -StatusCode 200 -ContentType 'text/html; charset=utf-8' -Body $body -Headers $headers
        }
        '/index.html' {
            return Get-ChannelForgeWebResponse -Method $methodName -Path '/' -RepositoryRoot $RepositoryRoot
        }
        '/health' {
            try {
                $body = Get-ChannelForgeWebStatus -RepositoryRoot $RepositoryRoot | ConvertTo-Json -Depth 4 -Compress
            }
            catch {
                return New-ChannelForgeWebStatusUnavailableResponse -Headers $commonHeaders -ContentType $contentType
            }
            return New-ChannelForgeWebResponse -StatusCode 200 -ContentType $contentType -Body $body -Headers $commonHeaders
        }
        '/api/status' {
            try {
                $body = Get-ChannelForgeWebStatus -RepositoryRoot $RepositoryRoot | ConvertTo-Json -Depth 4 -Compress
            }
            catch {
                return New-ChannelForgeWebStatusUnavailableResponse -Headers $commonHeaders -ContentType $contentType
            }
            return New-ChannelForgeWebResponse -StatusCode 200 -ContentType $contentType -Body $body -Headers $commonHeaders
        }
        default {
            return New-ChannelForgeWebResponse -StatusCode 404 -ContentType $contentType -Body (@{
                Error   = 'not-found'
                Message = 'Not found.'
            } | ConvertTo-Json -Compress) -Headers $commonHeaders
        }
    }
}

function Write-ChannelForgeWebResponse {
    param(
        [Parameter(Mandatory)][System.Net.HttpListenerContext]$Context,
        [Parameter(Mandatory)]$Response
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Response.Body)
    $httpResponse = $Context.Response
    $httpResponse.StatusCode = $Response.StatusCode
    $httpResponse.ContentType = $Response.ContentType
    $httpResponse.ContentEncoding = [System.Text.Encoding]::UTF8
    $httpResponse.ContentLength64 = $bytes.Length
    foreach ($header in $Response.Headers.GetEnumerator()) {
        $httpResponse.Headers[$header.Key] = [string]$header.Value
    }

    if ($Context.Request.HttpMethod -ne 'HEAD') {
        $httpResponse.OutputStream.Write($bytes, 0, $bytes.Length)
    }
}
