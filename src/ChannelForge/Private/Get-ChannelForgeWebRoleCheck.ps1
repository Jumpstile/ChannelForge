function Get-ChannelForgeWebRouteRoleTable {
    <#
    .SYNOPSIS
        The one table of who may use which route. First matching row wins. A route with no row is refused for everyone.
    .DESCRIPTION
        Pattern is matched against the lowercase path. Methods is a list, or '*' for any method.
        A new route must get a row here before anyone can use it.
    #>
    return @(
        @{ Pattern = '^/(health|api/status|api/lineup/channels)$'; Methods = @('GET', 'HEAD'); Role = 'viewer' }
        @{ Pattern = '^/api/one-guide/(live-now|starting-soon|category/[^/]+|items/[^/]+)$'; Methods = @('GET', 'HEAD'); Role = 'viewer' }
        @{ Pattern = '^/api/guided-setup/(proposal|accept)$'; Methods = '*'; Role = 'editor' }
        @{ Pattern = '^/api/sources/(refresh|remove)$'; Methods = '*'; Role = 'editor' }
        @{ Pattern = '^/api/settings$'; Methods = @('GET', 'HEAD'); Role = 'viewer' }
        # Every role changes only its own settings: the user comes from the session, never from the request.
        @{ Pattern = '^/api/settings/me$'; Methods = @('GET', 'HEAD', 'PUT'); Role = 'viewer' }
        @{ Pattern = '^/api/settings$'; Methods = '*'; Role = 'admin' }
        @{ Pattern = '^/api/users$'; Methods = '*'; Role = 'admin' }
        @{ Pattern = '^/api/users/[0-9a-f]{32}(/reset-password)?$'; Methods = '*'; Role = 'admin' }
        @{ Pattern = '^/api/audit$'; Methods = @('GET'); Role = 'admin' }
        # The page shell and its program files. Everything under /api/ that is not listed above stays refused.
        @{ Pattern = '^/(?!api/)'; Methods = @('GET', 'HEAD'); Role = 'viewer' }
    )
}

function Get-ChannelForgeWebRouteMinimumRole {
    # The lowest role that may use this method and path, or $null when the route is not in the table.
    param([Parameter(Mandatory)][string]$Method, [Parameter(Mandatory)][AllowEmptyString()][string]$Path)
    $requestPath = ($Path -split '\?', 2)[0].ToLowerInvariant()
    $methodName = $Method.ToUpperInvariant()
    foreach ($row in Get-ChannelForgeWebRouteRoleTable) {
        if ($requestPath -match $row.Pattern -and ($row.Methods -eq '*' -or $methodName -in $row.Methods)) { return $row.Role }
    }
    return $null
}

function Get-ChannelForgeWebSessionUser {
    # The CURRENT users.json record for a session, or $null when the user is gone or disabled. Read on every request.
    param([Parameter(Mandatory)][string]$ConfigRoot, [AllowNull()][string]$UserId)
    $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
    if ($store.Status -ne 'Ok') { return $null }
    return @($store.Users | Where-Object { $_.Id -ceq $UserId -and -not $_.Disabled })[0]
}

function Get-ChannelForgeWebRoleRefusal {
    <#
    .SYNOPSIS
        Returns a 403 response when the role may not use this route, else $null. An unknown role or route is refused.
        With -MustChange every /api/ route is refused until the person has chosen a new password; the page shell and program files still load so the Change password form can show. The sign-in, session, sign-out and change-password routes never reach this check.
    #>
    param(
        [AllowNull()][string]$Role,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [switch]$MustChange
    )
    if ($MustChange -and $Path.ToLowerInvariant().StartsWith('/api/')) {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 403 -Body @{ Error = 'not-allowed'; Code = 'must-change-password'; Message = 'You must choose a new password first. Use Change password, then try again.' }
    }
    $rank = @{ viewer = 1; editor = 2; admin = 3 }
    $needed = Get-ChannelForgeWebRouteMinimumRole -Method $Method -Path $Path
    if ($null -ne $needed -and $null -ne $Role -and $rank.ContainsKey($Role) -and $rank[$Role] -ge $rank[$needed]) { return $null }
    return New-ChannelForgeWebSignInJsonResponse -StatusCode 403 -Body @{ Error = 'not-allowed'; Message = 'Your account is not allowed to do that.' }
}
