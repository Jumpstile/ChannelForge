function Reset-ChannelForgeAdminPassword {
    <#
    .SYNOPSIS
        Forgot the admin password: removes the sign-in files on the server machine so the next start returns to setup.
    .DESCRIPTION
        Run this on the server machine. On Windows it needs an administrator window. It deletes only
        users.json and admin-password.json (the old one is removed first, so it cannot be upgraded back). A leftover
        admin-password.json.migrated is not touched. Lineups, accepted state, settings and outputs are not touched.
        The setup code is made only when the server starts, so a running server must be restarted to get a new code.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][string]$ConfigRoot)

    if (-not (Test-ChannelForgeElevated)) {
        throw 'Resetting the admin password needs an administrator window. Open one and run the command again.'
    }
    $names = @(@('admin-password.json', 'users.json') | Where-Object { Test-Path -LiteralPath (Join-Path $ConfigRoot $_) -PathType Leaf })
    if ($names.Count -eq 0) {
        return [pscustomobject]@{ Reset = $false; Message = 'There is no admin password file in that folder. Nothing was changed.' }
    }
    if (-not $PSCmdlet.ShouldProcess((Join-Path $ConfigRoot $names[0]), 'Remove the sign-in files')) {
        return [pscustomobject]@{ Reset = $false; Message = 'Nothing was changed.' }
    }
    foreach ($name in $names) {
        if (-not (Remove-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot -FileName $name).Success) {
            throw 'A sign-in file could not be removed. Check the config folder and run the command again.'
        }
    }
    $time = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
    return [pscustomobject]@{
        Reset   = $true
        Message = "admin password reset $time. The next server start prints a new setup code. A server that is already running must be restarted to get one."
    }
}
