function Get-ChannelForgeWebAllowedHost {
    <#
    .SYNOPSIS
        The Host header values a "sign-in required" server accepts: the loopback names with the listening port, plus any -AllowedHost entries.
    .DESCRIPTION
        An entry with no port also matches with the listening port. No wildcards.
    #>
    param(
        [Parameter(Mandatory)][int]$Port,
        [string[]]$AllowedHost = @()
    )
    $allowed = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('localhost', '127.0.0.1', '[::1]')) { $allowed.Add("${name}:$Port") }
    foreach ($entry in @($AllowedHost)) {
        $value = ([string]$entry).Trim().ToLowerInvariant()
        if ($value -eq '') { continue }
        $allowed.Add($value)
        if ($value -notmatch ':\d+$') { $allowed.Add("${value}:$Port") }
    }
    return , @($allowed)
}

function Get-ChannelForgeWebRequestRefusal {
    <#
    .SYNOPSIS
        The browser-safety check for "sign-in required" mode. Returns a refusal response, or $null when the request may go on.
    .DESCRIPTION
        Refuses a Host header that is not allowed (DNS rebinding), any preflight (no CORS is ever offered),
        and state-changing requests (POST, PUT, PATCH, DELETE) that do not come from this server's own page:
        the Origin must match the Host, or, when there is no Origin, the Referer must. No Origin and no Referer is refused.
        State-changing requests must also be application/json. Refusals are uniform and never repeat any header value.
    #>
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][int]$Port,
        [string[]]$AllowedHost = @(),
        [string]$Scheme = 'http',
        [AllowNull()][AllowEmptyString()][string]$HostHeader,
        [AllowNull()][AllowEmptyString()][string]$Origin,
        [AllowNull()][AllowEmptyString()][string]$Referer,
        [AllowNull()][AllowEmptyString()][string]$ContentType
    )
    $methodName = $Method.ToUpperInvariant()
    $requestHost = ([string]$HostHeader).Trim().ToLowerInvariant()
    $refuse = {
        param([int]$Status)
        New-ChannelForgeWebSignInJsonResponse -StatusCode $Status -Body @{ Error = 'request-not-allowed'; Message = 'That request was not allowed.' }
    }

    if ($requestHost -eq '' -or $requestHost -notin (Get-ChannelForgeWebAllowedHost -Port $Port -AllowedHost $AllowedHost)) { return & $refuse 403 }
    if ($methodName -eq 'OPTIONS') { return & $refuse 405 }
    if ($methodName -notin @('POST', 'PUT', 'PATCH', 'DELETE')) { return $null }

    $self = "${Scheme}://$requestHost"
    if (-not [string]::IsNullOrEmpty($Origin)) {
        if ($Origin.Trim().ToLowerInvariant() -ne $self) { return & $refuse 403 }
    }
    elseif ([string]::IsNullOrEmpty($Referer) -or -not "$Referer".Trim().ToLowerInvariant().StartsWith("$self/")) {
        return & $refuse 403
    }
    if (([string]$ContentType -split ';')[0].Trim() -ine 'application/json') { return & $refuse 415 }
    return $null
}
