function Test-ChannelForgeAdminPasswordRule {
    <#
    .SYNOPSIS
        Checks a new admin password: 12 characters minimum and not a very common password.
    .DESCRIPTION
        Returns Ok and a short plain Reason (empty when Ok).
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Password)

    $common = @(
        'password1234', '123456789012', 'qwertyuiop12', 'iloveyou1234', 'administrator',
        'welcome12345', 'letmein12345', 'changeme1234', 'password12345', '1234567890123',
        'abcdefghijkl', 'passwordpassword', 'adminadmin12', 'qwerty123456', 'trustno1trustno1',
        '111111111111', '000000000000', 'channelforge', 'iptvpassword', 'monkeymonkey12'
    )
    if ([string]::IsNullOrWhiteSpace($Password)) {
        return [pscustomobject]@{ Ok = $false; Reason = 'Enter a password.' }
    }
    if ($Password.Length -lt 12) {
        return [pscustomobject]@{ Ok = $false; Reason = 'Use at least 12 characters.' }
    }
    if ($common -contains $Password) {
        return [pscustomobject]@{ Ok = $false; Reason = 'That password is too common. Choose another.' }
    }
    return [pscustomobject]@{ Ok = $true; Reason = '' }
}
