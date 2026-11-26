function New-ChannelForgeUserRecord {
    <#
    .SYNOPSIS
        Returns one user for users.json. Takes a finished password record, never a password.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)]$PasswordRecord,
        [bool]$MustChange = $false
    )
    return [pscustomobject][ordered]@{
        Id         = [System.Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)).ToLowerInvariant()
        Name       = $Name
        Role       = $Role
        Password   = [ordered]@{
            Schema     = [int]$PasswordRecord.Schema
            Algorithm  = [string]$PasswordRecord.Algorithm
            Iterations = [int]$PasswordRecord.Iterations
            Salt       = [string]$PasswordRecord.Salt
            Hash       = [string]$PasswordRecord.Hash
        }
        MustChange = $MustChange
        Disabled   = $false
        CreatedUtc = [datetime]::UtcNow.ToString('yyyy-MM-dd\THH:mm:ss\Z', [System.Globalization.CultureInfo]::InvariantCulture)
    }
}

function Write-ChannelForgeUserStore {
    <#
    .SYNOPSIS
        Saves users.json with the same durable, protected writer as the old password file.
    .DESCRIPTION
        The document is checked in memory first, so a bad one is refused and nothing reaches the disk.
        Returns Success and Category ('None', 'WriteFailed' or 'PermissionFailed'). Nothing is printed.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)][object[]]$User
    )
    $document = [ordered]@{ Schema = 1; Users = @($User) }
    try {
        $parsed = ConvertTo-ChannelForgeCanonicalJson -InputObject $document | ConvertFrom-Json -DateKind String -ErrorAction Stop
        if (-not (Test-ChannelForgeUserStoreDocument -Document $parsed)) { throw 'invalid' }
    }
    catch { return [pscustomobject]@{ Success = $false; Category = 'WriteFailed' } }
    return Write-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot -Record $document -FileName 'users.json'
}

function Set-ChannelForgeUserPassword {
    <#
    .SYNOPSIS
        Replaces one user's password record in users.json. Same Success and Category answer as Write-ChannelForgeUserStore.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)]$PasswordRecord
    )
    $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
    $target = @($store.Users | Where-Object { $_.Id -ceq $UserId })[0]
    if ($store.Status -ne 'Ok' -or $null -eq $target) { return [pscustomobject]@{ Success = $false; Category = 'WriteFailed' } }
    $target.Password = $PasswordRecord
    return Write-ChannelForgeUserStore -ConfigRoot $ConfigRoot -User @($store.Users)
}

function Invoke-ChannelForgeUserStoreUpgrade {
    <#
    .SYNOPSIS
        Turns a good admin-password.json into users.json with one user, admin, carrying the same password record.
    .DESCRIPTION
        The old file is renamed to admin-password.json.migrated only after users.json is saved and read back.
        If saving fails, what was written is removed (users.json did not exist a moment ago), the old file is left alone,
        and sign-in keeps working from it as before; the upgrade is tried again on the next read.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)]$PasswordRecord
    )
    $user = New-ChannelForgeUserRecord -Name 'admin' -Role 'admin' -PasswordRecord $PasswordRecord
    $path = Join-Path $ConfigRoot 'users.json'
    $saved = Write-ChannelForgeUserStore -ConfigRoot $ConfigRoot -User @($user)
    if ($saved.Success) {
        $read = Read-ChannelForgeUserStoreFile -Path $path -ConfigRoot $ConfigRoot
        if ($read.Status -eq 'Ok') {
            $old = Join-Path $ConfigRoot 'admin-password.json'
            # A rename that fails leaves the old file in place; users.json wins from now on, so that is harmless.
            try { [System.IO.File]::Move($old, "$old.migrated") } catch { $null = $_ }
            return $read
        }
    }
    if ($saved.Success -or $saved.Category -eq 'PermissionFailed') { Remove-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot -FileName 'users.json' | Out-Null }
    return [pscustomobject]@{ Status = 'Ok'; Users = @($user) }
}
