function Reset-ChannelForgeAdminPassword {
    <#
    .SYNOPSIS
        Forgot an Admin password: sets one named Admin to a new temporary password on the server machine, and keeps everyone else.
    .DESCRIPTION
        Run this on the server machine. On Windows it needs an administrator window. The Admin named by -Name (or the only
        Admin) gets a new random temporary password, shown once on the console and stored nowhere. That Admin must choose a
        new password at the next sign-in, is enabled again if disabled, and every older session of that Admin stops working.
        Other users, lineups, accepted state, settings and outputs are not touched. The running server needs no restart.
        -RemoveAllSignInData instead removes users.json, admin-password.json and admin-password.json.migrated, so the next
        server start is in setup state with a new setup code. It touches no other file.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$ConfigRoot,
        [string]$Name = '',
        [switch]$RemoveAllSignInData
    )

    if (-not (Test-ChannelForgeElevated)) {
        throw 'Resetting the admin password needs an administrator window. Open one and run the command again.'
    }
    if ($RemoveAllSignInData) { return Remove-ChannelForgeAllSignInData -ConfigRoot $ConfigRoot -Cmdlet $PSCmdlet }

    $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
    if ($store.Status -eq 'Missing') {
        return [pscustomobject]@{ Reset = $false; Message = 'There is no sign-in file in that folder. Nothing was changed.' }
    }
    $target = Resolve-ChannelForgeResetAdmin -Store $store -Name $Name
    if (-not $PSCmdlet.ShouldProcess((Join-Path $ConfigRoot 'users.json'), "Set a temporary password for Admin $($target.Name)")) {
        return [pscustomobject]@{ Reset = $false; Message = 'Nothing was changed.' }
    }
    $temporary = Set-ChannelForgeAdminTemporaryPassword -ConfigRoot $ConfigRoot -Name $Name
    Write-Host "Temporary password for $($temporary.Name): $($temporary.Password)"
    $time = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
    return [pscustomobject]@{
        Reset   = $true
        Message = "admin password reset $time for $($temporary.Name). The temporary password was shown once above and is not stored. Sign in with it; you must then choose a new password. A running server needs no restart."
    }
}
