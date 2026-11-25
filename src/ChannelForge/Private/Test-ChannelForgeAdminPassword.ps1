function Test-ChannelForgeAdminPassword {
    <#
    .SYNOPSIS
        True only when the password matches the stored record. Any bad or missing record returns false.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Password,
        [AllowNull()]$Record
    )

    try {
        if ([string]::IsNullOrEmpty($Password) -or $null -eq $Record) { return $false }
        if ([int]$Record.Schema -ne 1 -or [string]$Record.Algorithm -cne 'PBKDF2-SHA256') { return $false }
        $iterations = [int]$Record.Iterations
        if ($iterations -lt 1 -or $iterations -gt 10000000) { return $false }
        $salt = [System.Convert]::FromBase64String([string]$Record.Salt)
        $expected = [System.Convert]::FromBase64String([string]$Record.Hash)
        if ($salt.Length -lt 8 -or $expected.Length -lt 16) { return $false }
        $actual = [System.Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2($Password, $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256, $expected.Length)
        return [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($actual, $expected)
    }
    catch {
        return $false
    }
}
