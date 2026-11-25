function Get-ChannelForgeSetupCodeLifetime {
    # How long a setup code works after the server prints it.
    return [TimeSpan]::FromMinutes(15)
}

function Get-ChannelForgeSetupCodeHash {
    param([AllowNull()][AllowEmptyString()][string]$Code)
    $clean = ([string]$Code -replace '[\s-]', '').ToUpperInvariant()
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($clean)))
}

function Test-ChannelForgeSetupState {
    <#
    .SYNOPSIS
        True when sign-in required mode has no password file yet (a damaged file is never setup).
    .DESCRIPTION
        Asks the start guard as it would for a network address, so the guard stays the one place that decides.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot)
    return (Get-ChannelForgeStartGuard -Address '0.0.0.0' -ConfigRoot $ConfigRoot -AllowSetupMode).State -eq 'SetupRequired'
}

function New-ChannelForgeSetupCode {
    <#
    .SYNOPSIS
        Makes a one-time setup code, keeps only its hash, expiry and used flag in $Setup, and returns the code.
    .DESCRIPTION
        12 characters from 31 look-alike-free characters (about 59 bits), grouped as XXXX-XXXX-XXXX.
        The caller prints the returned code once on the console and keeps it nowhere else.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Setup,
        [datetime]$Now = [datetime]::UtcNow
    )
    $alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'
    $chars = 1..12 | ForEach-Object { $alphabet[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($alphabet.Length)] }
    $code = ((0, 4, 8 | ForEach-Object { -join $chars[$_..($_ + 3)] }) -join '-')
    $Setup.Hash = Get-ChannelForgeSetupCodeHash -Code $code
    $Setup.ExpiresUtc = $Now + (Get-ChannelForgeSetupCodeLifetime)
    $Setup.Used = $false
    return $code
}

function Test-ChannelForgeSetupCode {
    <#
    .SYNOPSIS
        True only for the right code that has not expired and has not been used.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Setup,
        [AllowNull()][AllowEmptyString()][string]$Code,
        [datetime]$Now = [datetime]::UtcNow
    )
    if ($null -eq $Setup.Hash -or $Setup.Used -or $Now -gt $Setup.ExpiresUtc) { return $false }
    return $Setup.Hash -ceq (Get-ChannelForgeSetupCodeHash -Code $Code)
}
