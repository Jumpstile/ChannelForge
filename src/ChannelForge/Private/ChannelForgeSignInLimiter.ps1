function Get-ChannelForgeSignInLimitSettings {
    <#
    .SYNOPSIS
        The sign-in slow-down numbers. Tests pass their own copy to the functions below; the server always uses these.
    #>
    return @{
        FailureThreshold       = 5     # wrong tries in a row from one address before the wait starts
        GlobalFailureThreshold = 50    # wrong tries from all addresses together before everyone waits
        BaseDelaySeconds       = 1     # the first wait; it doubles with each further wrong try
        CapSeconds             = 900   # longest wait for one address: 15 minutes (needs owner to confirm)
        GlobalCapSeconds       = 30    # longest wait for everyone; short so the real admin is never shut out for long
        QuietResetSeconds      = 900   # no wrong tries for this long: the counts start over
        MaxTrackedAddresses    = 1000  # the oldest address is forgotten past this
    }
}

function New-ChannelForgeSignInLimiter {
    # Memory only. A restart clears it.
    return @{ Addresses = @{}; GlobalFailures = 0; GlobalNextUtc = [datetime]::MinValue; GlobalLastUtc = [datetime]::MinValue }
}

function Get-ChannelForgeSignInDelaySeconds {
    param(
        [Parameter(Mandatory)][int]$Failures,
        [Parameter(Mandatory)][int]$Threshold,
        [Parameter(Mandatory)][hashtable]$Settings,
        [double]$CapSeconds = 0
    )
    if ($Failures -lt $Threshold) { return 0 }
    if ($CapSeconds -le 0) { $CapSeconds = [double]$Settings.CapSeconds }
    $doublings = [Math]::Min($Failures - $Threshold, 30)
    return [Math]::Min($CapSeconds, [double]$Settings.BaseDelaySeconds * [Math]::Pow(2, $doublings))
}

function Get-ChannelForgeSignInWaitSeconds {
    <#
    .SYNOPSIS
        Whole seconds this address must still wait (the longer of its own wait and the global wait), or 0.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Limiter,
        [string]$Address = '',
        [datetime]$Now = [datetime]::UtcNow
    )
    $next = $Limiter.GlobalNextUtc
    $entry = $Limiter.Addresses[$Address]
    if ($null -ne $entry -and $entry.NextUtc -gt $next) { $next = $entry.NextUtc }
    if ($next -le $Now) { return 0 }
    return [int][Math]::Ceiling(($next - $Now).TotalSeconds)
}

function Register-ChannelForgeSignInFailure {
    param(
        [Parameter(Mandatory)][hashtable]$Limiter,
        [string]$Address = '',
        [datetime]$Now = [datetime]::UtcNow,
        [hashtable]$Settings = (Get-ChannelForgeSignInLimitSettings)
    )
    # Old wrong tries are forgiven after a quiet period, so a past attack never keeps counting against the real admin.
    if (($Now - $Limiter.GlobalLastUtc).TotalSeconds -gt $Settings.QuietResetSeconds) { $Limiter.GlobalFailures = 0 }
    $entry = $Limiter.Addresses[$Address]
    if ($null -ne $entry -and ($Now - $entry.LastUtc).TotalSeconds -gt $Settings.QuietResetSeconds) { $entry.Failures = 0 }
    if ($null -eq $entry) {
        if ($Limiter.Addresses.Count -ge $Settings.MaxTrackedAddresses) {
            $oldest = $Limiter.Addresses.GetEnumerator() | Sort-Object { $_.Value.LastUtc } | Select-Object -First 1
            $Limiter.Addresses.Remove($oldest.Key)
        }
        $entry = @{ Failures = 0; NextUtc = [datetime]::MinValue; LastUtc = $Now }
        $Limiter.Addresses[$Address] = $entry
    }
    $entry.Failures++
    $entry.LastUtc = $Now
    $entry.NextUtc = $Now.AddSeconds((Get-ChannelForgeSignInDelaySeconds -Failures $entry.Failures -Threshold $Settings.FailureThreshold -Settings $Settings))
    $Limiter.GlobalFailures++
    $Limiter.GlobalLastUtc = $Now
    $Limiter.GlobalNextUtc = $Now.AddSeconds((Get-ChannelForgeSignInDelaySeconds -Failures $Limiter.GlobalFailures -Threshold $Settings.GlobalFailureThreshold -Settings $Settings -CapSeconds $Settings.GlobalCapSeconds))
}

function Clear-ChannelForgeSignInFailure {
    # A correct password or setup code: forget this address and the global count.
    param(
        [Parameter(Mandatory)][hashtable]$Limiter,
        [string]$Address = ''
    )
    $Limiter.Addresses.Remove($Address)
    $Limiter.GlobalFailures = 0
    $Limiter.GlobalNextUtc = [datetime]::MinValue
}

function Get-ChannelForgeSignInWaitResponse {
    <#
    .SYNOPSIS
        A 429 response while this address (or everyone) must wait, else $null. A refused try does not lengthen the wait.
    #>
    param(
        [hashtable]$Limiter = $null,
        [string]$Address = '',
        [datetime]$Now = [datetime]::UtcNow
    )
    if ($null -eq $Limiter) { return $null }
    $seconds = Get-ChannelForgeSignInWaitSeconds -Limiter $Limiter -Address $Address -Now $Now
    if ($seconds -le 0) { return $null }
    return New-ChannelForgeWebSignInJsonResponse -StatusCode 429 -Body @{ Error = 'too-many-tries'; Message = 'Too many tries. Please wait and try again.' } -ExtraHeaders @{ 'Retry-After' = [string]$seconds }
}
