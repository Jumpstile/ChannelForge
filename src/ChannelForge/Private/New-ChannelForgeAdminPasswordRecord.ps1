function New-ChannelForgeAdminPasswordRecord {
    <#
    .SYNOPSIS
        Returns the record to store for an admin password: salted PBKDF2-SHA256 hash, never the password.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Password,
        [int]$Iterations = 600000
    )

    $salt = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
    $hash = [System.Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2($Password, $salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256, 32)
    return [ordered]@{
        Schema     = 1
        Algorithm  = 'PBKDF2-SHA256'
        Iterations = $Iterations
        Salt       = [System.Convert]::ToBase64String($salt)
        Hash       = [System.Convert]::ToBase64String($hash)
    }
}
