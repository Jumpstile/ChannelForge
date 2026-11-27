function Resolve-ChannelForgeResetAdmin {
    <#
    .SYNOPSIS
        The one Admin a console reset applies to, or a plain refusal. Names the Admins only when the choice is open.
    #>
    param([Parameter(Mandatory)]$Store, [string]$Name = '')
    if ($Store.Status -ne 'Ok') { throw 'The sign-in file is damaged. Nothing was changed.' }
    $admins = @($Store.Users | Where-Object { $_.Role -ceq 'admin' })
    $wanted = $Name.Trim()
    if ($wanted -eq '') {
        if ($admins.Count -eq 1) { return $admins[0] }
        $list = ($admins.Name | Sort-Object) -join ', '
        throw "There is more than one Admin ($list). Run the command again with -Name and one of those names."
    }
    $found = @($Store.Users | Where-Object { $_.Name -ieq $wanted })[0]
    if ($null -eq $found) { throw "There is no user named '$wanted'. The names are: $(($Store.Users.Name | Sort-Object) -join ', ')." }
    if ($found.Role -cne 'admin') { throw "'$($found.Name)' is not an Admin. Choose an Admin name: $(($admins.Name | Sort-Object) -join ', ')." }
    return $found
}

function Set-ChannelForgeAdminTemporaryPassword {
    <#
    .SYNOPSIS
        Gives one Admin a new random temporary password under the users.json lock and returns Name and Password. Never stores the password.
    .DESCRIPTION
        Same write as an Admin reset in the Users API (MustChange, new PasswordChangedUtc), and the Admin is enabled again.
        Writes the console-reset audit event. A failed audit write never fails the reset.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot, [string]$Name = '')
    $password = New-ChannelForgeSetupCode -Setup @{}
    $record = New-ChannelForgeAdminPasswordRecord -Password $password
    $target = Invoke-ChannelForgeUserStoreLocked -ConfigRoot $ConfigRoot -Action {
        $found = Resolve-ChannelForgeResetAdmin -Store (Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot) -Name $Name
        $saved = Set-ChannelForgeUserPassword -ConfigRoot $ConfigRoot -TargetId $found.Id -PasswordRecord $record -MustChange -Enable
        if (-not $saved.Success) { throw 'The sign-in file could not be saved. Nothing was changed. Check the config folder and run the command again.' }
        $found
    }
    Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'console-reset' -Actor ([pscustomobject]@{ Id = ''; Name = 'console' }) -Target $target -Reason 'Admin set to a temporary password'
    return [pscustomobject]@{ Name = [string]$target.Name; Password = $password }
}

function Remove-ChannelForgeAllSignInData {
    <#
    .SYNOPSIS
        Console reset back to setup state: removes users.json, admin-password.json and admin-password.json.migrated. Touches no other file.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)]$Cmdlet)
    $names = @(@('admin-password.json', 'users.json', 'admin-password.json.migrated') | Where-Object { Test-Path -LiteralPath (Join-Path $ConfigRoot $_) -PathType Leaf })
    if ($names.Count -eq 0) {
        return [pscustomobject]@{ Reset = $false; Message = 'There is no sign-in file in that folder. Nothing was changed.' }
    }
    if (-not $Cmdlet.ShouldProcess((Join-Path $ConfigRoot $names[0]), 'Remove all sign-in data')) {
        return [pscustomobject]@{ Reset = $false; Message = 'Nothing was changed.' }
    }
    foreach ($name in $names) {
        if (-not (Remove-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot -FileName $name).Success) {
            throw 'A sign-in file could not be removed. Check the config folder and run the command again.'
        }
    }
    Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'console-reset' -Actor ([pscustomobject]@{ Id = ''; Name = 'console' }) -Target ([pscustomobject]@{ Id = 'all'; Name = 'all' }) -Reason 'all sign-in data removed'
    $time = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
    return [pscustomobject]@{
        Reset   = $true
        Message = "admin password reset $time. All sign-in data was removed. The next server start prints a new setup code. A server that is already running must be restarted to get one."
    }
}
