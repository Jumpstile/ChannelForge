function Get-ChannelForgeWebRepositoryRoot {
    $module = Get-Module -Name ChannelForge | Select-Object -First 1
    if ($null -eq $module) { return (Get-Location).Path }

    $moduleRoot = [IO.Path]::GetFullPath($module.ModuleBase)
    return Split-Path -Parent (Split-Path -Parent $moduleRoot)
}

function New-ChannelForgeWebResponse {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][string]$ContentType,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [System.Collections.IDictionary]$Headers = [ordered]@{},
        [byte[]]$Bytes = $null
    )

    return [pscustomobject][ordered]@{
        StatusCode  = $StatusCode
        ContentType = $ContentType
        Body        = $Body
        Bytes       = $Bytes
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

function Get-ChannelForgeWebStaticContentType {
    param([Parameter(Mandatory)][string]$Extension)

    switch ($Extension.ToLowerInvariant()) {
        '.css' { return 'text/css; charset=utf-8' }
        '.gif' { return 'image/gif' }
        '.html' { return 'text/html; charset=utf-8' }
        '.ico' { return 'image/x-icon' }
        '.jpeg' { return 'image/jpeg' }
        '.jpg' { return 'image/jpeg' }
        '.js' { return 'text/javascript; charset=utf-8' }
        '.mjs' { return 'text/javascript; charset=utf-8' }
        '.png' { return 'image/png' }
        '.svg' { return 'image/svg+xml' }
        '.ttf' { return 'font/ttf' }
        '.webp' { return 'image/webp' }
        '.woff' { return 'font/woff' }
        '.woff2' { return 'font/woff2' }
        default { return $null }
    }
}

function Get-ChannelForgeWebStaticFileResponse {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$StaticRoot,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers
    )

    try {
        if (-not (Test-Path -LiteralPath $StaticRoot -PathType Container)) { return $null }

        $rootItem = Get-Item -LiteralPath $StaticRoot -Force

        $repositoryRootFullPath = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char]92, [char]47)
        $allowedStaticRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRootFullPath 'gui\dist')).TrimEnd([char]92, [char]47)
        $staticRootFullPath = [IO.Path]::GetFullPath($StaticRoot).TrimEnd([char]92, [char]47)
        $allowedPrefix = "$allowedStaticRoot$([IO.Path]::DirectorySeparatorChar)"
        if (
            $staticRootFullPath -ne $allowedStaticRoot -and
            -not $staticRootFullPath.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)
        ) { return $null }
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }

        $decodedPath = [Uri]::UnescapeDataString($Path)
        if (
            [string]::IsNullOrWhiteSpace($decodedPath) -or
            $decodedPath[0] -ne '/' -or
            $decodedPath.IndexOf([char]0) -ge 0 -or
            $decodedPath.Contains('\') -or
            $decodedPath.Contains(':')
        ) { return $null }

        $relativePath = $decodedPath.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($relativePath)) { return $null }

        $segments = $relativePath -split '/'
        $invalidFileNameChars = [IO.Path]::GetInvalidFileNameChars()
        foreach ($segment in $segments) {
            if (
                [string]::IsNullOrWhiteSpace($segment) -or
                $segment -in @('.', '..') -or
                $segment.IndexOfAny($invalidFileNameChars) -ge 0
            ) { return $null }
        }

        $rootFullPath = $staticRootFullPath
        $candidatePath = [IO.Path]::GetFullPath((Join-Path $rootFullPath ($relativePath -replace '/', '\')))
        $rootPrefix = "$rootFullPath$([IO.Path]::DirectorySeparatorChar)"
        if (-not $candidatePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { return $null }
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { return $null }

        $fileItem = Get-Item -LiteralPath $candidatePath -Force
        if (($fileItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }

        $contentType = Get-ChannelForgeWebStaticContentType -Extension $fileItem.Extension
        if ($null -eq $contentType) { return $null }

        $bytes = [IO.File]::ReadAllBytes($candidatePath)
        $body = if ($contentType.StartsWith('text/', [StringComparison]::OrdinalIgnoreCase)) { [Text.Encoding]::UTF8.GetString($bytes) } else { '' }
        return New-ChannelForgeWebResponse -StatusCode 200 -ContentType $contentType -Body $body -Bytes $bytes -Headers $Headers
    }
    catch {
        return $null
    }
}

function Get-ChannelForgeWebPlaceholderResponse {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [Parameter(Mandatory)][string]$ContentType
    )

    try {
        $webStatus = Get-ChannelForgeWebStatus -RepositoryRoot $RepositoryRoot
    }
    catch {
        return New-ChannelForgeWebStatusUnavailableResponse -Headers $Headers -ContentType $ContentType
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
    return New-ChannelForgeWebResponse -StatusCode 200 -ContentType 'text/html; charset=utf-8' -Body $body -Headers $Headers
}

function Get-ChannelForgeWebResponse {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot),
        [string]$StaticRoot = '',
        [byte[]]$BodyBytes = $null,
        [string]$ContentType = '',
        [long]$ContentLength = -1
    )

    $staticRoot = if ([string]::IsNullOrWhiteSpace($StaticRoot)) { Join-Path $RepositoryRoot 'gui\dist' } else { $StaticRoot }

    $commonHeaders = [ordered]@{
        'Cache-Control'            = 'no-store'
        'X-Content-Type-Options'  = 'nosniff'
        'Content-Security-Policy' = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"
    }
    $staticHeaders = [ordered]@{}
    foreach ($header in $commonHeaders.GetEnumerator()) { $staticHeaders[$header.Key] = $header.Value }
    $staticHeaders['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'"
    $requestContentType = $ContentType
    $contentType = 'application/json; charset=utf-8'
    $methodName = if ($null -eq $Method) { '' } else { $Method.ToUpperInvariant() }
    $requestPath = if ([string]::IsNullOrWhiteSpace($Path)) { '/' } else { ($Path -split '\?', 2)[0] }
    $acceptPath = '/api/guided-setup/accept'
    if ($requestPath.ToLowerInvariant() -eq $acceptPath) {
        if ($methodName -ne 'POST') {
            $headers = [ordered]@{}
            foreach ($header in $commonHeaders.GetEnumerator()) { $headers[$header.Key] = $header.Value }
            $headers['Allow'] = 'POST'
            return New-ChannelForgeWebProposalErrorResponse -StatusCode 405 -ErrorCode 'method-not-allowed' -Message 'Only POST requests are supported for guided setup acceptance.' -Headers $headers
        }
        if ($null -eq $BodyBytes) { return New-ChannelForgeWebProposalErrorResponse -StatusCode 400 -ErrorCode 'missing-request-body' -Message 'An acceptance request is required.' -Headers $commonHeaders }
        if ($ContentLength -gt (Get-ChannelForgeWebAcceptanceLimits).MaxRequestBodyBytes) { return New-ChannelForgeWebProposalErrorResponse -StatusCode 413 -ErrorCode 'request-too-large' -Message 'The acceptance request is too large.' -Headers $commonHeaders }
        if ($ContentLength -ge 0 -and $ContentLength -ne $BodyBytes.Length) { return New-ChannelForgeWebProposalErrorResponse -StatusCode 400 -ErrorCode 'request-length-mismatch' -Message 'The acceptance request length does not match its body.' -Headers $commonHeaders }
        return Get-ChannelForgeGuidedSetupAcceptanceResponse -BodyBytes $BodyBytes -RepositoryRoot $RepositoryRoot -Headers $commonHeaders -ContentType $requestContentType
    }

    $proposalPath = '/api/guided-setup/proposal'
    if ($requestPath.ToLowerInvariant() -eq $proposalPath) {
        if ($methodName -ne 'POST') {
            $headers = [ordered]@{}
            foreach ($header in $commonHeaders.GetEnumerator()) { $headers[$header.Key] = $header.Value }
            $headers['Allow'] = 'POST'
            return New-ChannelForgeWebProposalErrorResponse -StatusCode 405 -ErrorCode 'method-not-allowed' -Message 'Only POST requests are supported for guided setup proposals.' -Headers $headers
        }
        if ($null -eq $BodyBytes) {
            return New-ChannelForgeWebProposalErrorResponse -StatusCode 400 -ErrorCode 'missing-request-body' -Message 'A guided setup proposal request is required.' -Headers $commonHeaders
        }
        if ($ContentLength -gt (Get-ChannelForgeWebProposalLimits).MaxRequestBodyBytes) {
            return New-ChannelForgeWebProposalErrorResponse -StatusCode 413 -ErrorCode 'request-too-large' -Message 'The proposal request is too large.' -Headers $commonHeaders
        }
        if ($ContentLength -ge 0 -and $ContentLength -ne $BodyBytes.Length) {
            return New-ChannelForgeWebProposalErrorResponse -StatusCode 400 -ErrorCode 'request-length-mismatch' -Message 'The proposal request length does not match its body.' -Headers $commonHeaders
        }
        return Get-ChannelForgeGuidedSetupProposalResponse -BodyBytes $BodyBytes -RepositoryRoot $RepositoryRoot -Headers $commonHeaders -ContentType $requestContentType
    }

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
            $staticResponse = Get-ChannelForgeWebStaticFileResponse -Path '/index.html' -StaticRoot $staticRoot -RepositoryRoot $RepositoryRoot -Headers $staticHeaders
            if ($null -ne $staticResponse) { return $staticResponse }
            return Get-ChannelForgeWebPlaceholderResponse -RepositoryRoot $RepositoryRoot -Headers $commonHeaders -ContentType $contentType
        }
        '/index.html' {
            $staticResponse = Get-ChannelForgeWebStaticFileResponse -Path '/index.html' -StaticRoot $staticRoot -RepositoryRoot $RepositoryRoot -Headers $staticHeaders
            if ($null -ne $staticResponse) { return $staticResponse }
            return Get-ChannelForgeWebPlaceholderResponse -RepositoryRoot $RepositoryRoot -Headers $commonHeaders -ContentType $contentType
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
            $staticResponse = Get-ChannelForgeWebStaticFileResponse -Path $requestPath -StaticRoot $staticRoot -RepositoryRoot $RepositoryRoot -Headers $staticHeaders
            if ($null -ne $staticResponse) { return $staticResponse }
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

    $bytes = if ($null -ne $Response.Bytes) { [byte[]]$Response.Bytes } else { [System.Text.Encoding]::UTF8.GetBytes($Response.Body) }
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
