function Get-ChannelForgeWebSessionLimits {
    <#
    .SYNOPSIS
        How long a sign-in lasts: 30 minutes without use, 12 hours at most.
    #>
    return [pscustomobject]@{
        IdleTimeout     = [TimeSpan]::FromMinutes(30)
        MaximumLifetime = [TimeSpan]::FromHours(12)
    }
}

function Get-ChannelForgeWebSessionKey {
    # Sessions are stored under a hash of the token, so the token itself is never kept.
    param([Parameter(Mandatory)][string]$Token)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Token)))
}

function Test-ChannelForgeWebSessionExpired {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][datetime]$Now
    )
    $limits = Get-ChannelForgeWebSessionLimits
    return ($Now - $Session.LastSeenUtc) -gt $limits.IdleTimeout -or ($Now - $Session.CreatedUtc) -gt $limits.MaximumLifetime
}

function Remove-ChannelForgeExpiredWebSession {
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [datetime]$Now = [datetime]::UtcNow
    )
    foreach ($key in @($Store.Keys)) {
        if (Test-ChannelForgeWebSessionExpired -Session $Store[$key] -Now $Now) { $Store.Remove($key) }
    }
}

function New-ChannelForgeWebSession {
    <#
    .SYNOPSIS
        Starts an in-memory session for a user (the admin when no id is given) and returns its random token.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [string]$UserId = 'admin',
        [datetime]$Now = [datetime]::UtcNow
    )
    Remove-ChannelForgeExpiredWebSession -Store $Store -Now $Now
    $token = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $Store[(Get-ChannelForgeWebSessionKey -Token $token)] = [pscustomobject]@{ UserId = $UserId; CreatedUtc = $Now; LastSeenUtc = $Now }
    return $token
}

function Get-ChannelForgeWebSession {
    <#
    .SYNOPSIS
        Returns the live session for a token and refreshes its idle time, or $null.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [AllowNull()][AllowEmptyString()][string]$Token,
        [datetime]$Now = [datetime]::UtcNow
    )
    if ($Token -cnotmatch '^[A-Za-z0-9_-]{43}$') { return $null }
    $key = Get-ChannelForgeWebSessionKey -Token $Token
    $session = $Store[$key]
    if ($null -eq $session) { return $null }
    if (Test-ChannelForgeWebSessionExpired -Session $session -Now $Now) {
        $Store.Remove($key)
        return $null
    }
    $session.LastSeenUtc = $Now
    return $session
}

function Remove-ChannelForgeWebSession {
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [AllowNull()][AllowEmptyString()][string]$Token
    )
    if ([string]::IsNullOrEmpty($Token)) { return }
    $Store.Remove((Get-ChannelForgeWebSessionKey -Token $Token))
}

function Remove-ChannelForgeOtherWebSession {
    # Ends every session except the one for this token.
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [AllowNull()][AllowEmptyString()][string]$Token
    )
    $keep = if ([string]::IsNullOrEmpty($Token)) { '' } else { Get-ChannelForgeWebSessionKey -Token $Token }
    foreach ($key in @($Store.Keys)) {
        if ($key -ne $keep) { $Store.Remove($key) }
    }
}
