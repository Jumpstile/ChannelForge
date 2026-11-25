function Reset-ChannelForgeAdminPassword {
    <#
    .SYNOPSIS
        Forgot the admin password: removes the password file on the server machine so the next start returns to setup.
    .DESCRIPTION
        Run this on the server machine. On Windows it needs an administrator window. It deletes only
        admin-password.json. Lineups, accepted state, settings and outputs are not touched.
        The setup code is made only when the server starts, so a running server must be restarted to get a new code.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)][string]$ConfigRoot)

    if (-not (Test-ChannelForgeElevated)) {
        throw 'Resetting the admin password needs an administrator window. Open one and run the command again.'
    }
    $path = Join-Path $ConfigRoot 'admin-password.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Reset = $false; Message = 'There is no admin password file in that folder. Nothing was changed.' }
    }
    if (-not $PSCmdlet.ShouldProcess($path, 'Remove the admin password file')) {
        return [pscustomobject]@{ Reset = $false; Message = 'Nothing was changed.' }
    }
    $removed = Remove-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot
    if (-not $removed.Success) {
        throw 'The admin password file could not be removed. Nothing else was changed.'
    }
    $time = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
    return [pscustomobject]@{
        Reset   = $true
        Message = "admin password reset $time. The next server start prints a new setup code. A server that is already running must be restarted to get one."
    }
}
