function New-ChannelForgeUsersApiError {
    param([Parameter(Mandatory)][int]$StatusCode, [Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)
    return New-ChannelForgeWebSignInJsonResponse -StatusCode $StatusCode -Body @{ Error = $Code; Message = $Message }
}

function ConvertTo-ChannelForgeUserView {
    # The fields a browser may see. The password record is never copied.
    param([Parameter(Mandatory)]$Record)
    return [ordered]@{
        Id                 = [string]$Record.Id
        Name               = [string]$Record.Name
        Role               = [string]$Record.Role
        MustChange         = [bool]$Record.MustChange
        Disabled           = [bool]$Record.Disabled
        CreatedUtc         = [string]$Record.CreatedUtc
        PasswordChangedUtc = [string]$Record.PasswordChangedUtc
    }
}

function Read-ChannelForgeUsersApiBody {
    # The JSON object in the request body, or $null when it is missing, too big or not an object.
    param([System.IO.Stream]$BodyStream = $null, [long]$ContentLength = -1)
    try {
        $bytes = Read-ChannelForgeWebRequestBody -Stream $BodyStream -ContentLength $ContentLength -MaxBytes 4096
        $body = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
        if ($body -is [pscustomobject]) { return $body }
    }
    catch { $null = $_ }
    return $null
}

function Get-ChannelForgeUsersApiText {
    # A string field of the body, or $null when the body or the field is missing or not text.
    param([AllowNull()]$Body, [Parameter(Mandatory)][string]$Field)
    if ($null -eq $Body -or $null -eq $Body.PSObject.Properties[$Field]) { return $null }
    $value = $Body.PSObject.Properties[$Field].Value
    return $(if ($value -is [string]) { $value } else { $null })
}

function Get-ChannelForgeUserNameProblem {
    # Plain words for a bad or taken name, or '' when it is fine.
    param([AllowNull()][string]$Name, [Parameter(Mandatory)][object[]]$Users, [string]$ExceptId = '')
    if ($null -eq $Name -or $Name -cnotmatch '^[A-Za-z0-9._-]{3,32}\z') { return 'Use 3 to 32 letters, numbers, dots, dashes or underscores for the name.' }
    if (@($Users | Where-Object { $_.Id -cne $ExceptId -and $_.Name -ieq $Name }).Count -gt 0) { return 'That name is already used.' }
    return ''
}

function Test-ChannelForgeLastActiveAdmin {
    # True when this user is the only enabled Admin.
    param([Parameter(Mandatory)][object[]]$Users, [Parameter(Mandatory)]$Target)
    $isActiveAdmin = $Target.Role -ceq 'admin' -and -not $Target.Disabled
    $others = @($Users | Where-Object { $_.Id -cne $Target.Id -and $_.Role -ceq 'admin' -and -not $_.Disabled })
    return $isActiveAdmin -and $others.Count -eq 0
}

function Confirm-ChannelForgeUsersApiAdmin {
    <#
    .SYNOPSIS
        $null when the signed-in Admin typed their OWN password right (field adminPassword); otherwise the response to send.
    .DESCRIPTION
        Uses the sign-in wrong-try guard: a wrong try counts, a waiting address gets a 429, a right try clears the count.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)][string]$ActorId,
        [AllowNull()]$Body,
        [hashtable]$Limiter = $null,
        [string]$SourceAddress = '',
        [datetime]$Now = [datetime]::UtcNow
    )
    $waitResponse = Get-ChannelForgeSignInWaitResponse -Limiter $Limiter -Address $SourceAddress -Now $Now
    if ($null -ne $waitResponse) { return $waitResponse }
    $actor = Get-ChannelForgeWebSessionUser -ConfigRoot $ConfigRoot -UserId $ActorId
    $typed = Get-ChannelForgeUsersApiText -Body $Body -Field 'adminPassword'
    if ($null -eq $actor -or -not (Test-ChannelForgeAdminPassword -Password $typed -Record $actor.Password)) {
        if ($null -ne $Limiter) { Register-ChannelForgeSignInFailure -Limiter $Limiter -Address $SourceAddress -Now $Now }
        $who = if ($null -ne $actor) { $actor } else { Get-ChannelForgeAuditPerson -ConfigRoot $ConfigRoot -UserId $ActorId }
        Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'admin-password-wrong' -Result refused -Actor $who -Reason 'own password typed wrong' -RemoteAddress $SourceAddress -Now $Now
        return New-ChannelForgeUsersApiError -StatusCode 403 -Code 'admin-password-wrong' -Message 'Your own password did not work. Nothing was changed.'
    }
    if ($null -ne $Limiter) { Clear-ChannelForgeSignInFailure -Limiter $Limiter -Address $SourceAddress }
    return $null
}

function New-ChannelForgeUsersApiSaveResult {
    # The answer after a write: the given success response, or a plain 500 that says nothing changed.
    param([Parameter(Mandatory)]$Saved, [Parameter(Mandatory)][int]$StatusCode, [Parameter(Mandatory)][hashtable]$Body)
    if ($Saved.Success) { return New-ChannelForgeWebSignInJsonResponse -StatusCode $StatusCode -Body $Body }
    return New-ChannelForgeUsersApiError -StatusCode 500 -Code 'users-not-saved' -Message 'The change could not be saved. Check that ChannelForge can write to its settings folder.'
}

function Get-ChannelForgeUsersApiStoreProblem {
    param([Parameter(Mandatory)]$Store)
    if ($Store.Status -eq 'Ok') { return $null }
    return New-ChannelForgeUsersApiError -StatusCode 500 -Code 'users-unreadable' -Message 'The users file could not be read. Nothing was changed.'
}

function Add-ChannelForgeUserFromRequest {
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)]$Body, $Actor = $null, [string]$SourceAddress = '')
    $name = Get-ChannelForgeUsersApiText -Body $Body -Field 'name'
    $role = Get-ChannelForgeUsersApiText -Body $Body -Field 'role'
    $temporary = Get-ChannelForgeUsersApiText -Body $Body -Field 'temporaryPassword'
    if ($null -eq $role -or $role -cnotin @('admin', 'editor', 'viewer')) { return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'role-invalid' -Message 'The role must be admin, editor or viewer.' }
    $rule = Test-ChannelForgeAdminPasswordRule -Password $temporary
    if (-not $rule.Ok) { return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'password-rule' -Message $rule.Reason }
    $record = New-ChannelForgeAdminPasswordRecord -Password $temporary
    return Invoke-ChannelForgeUserStoreLocked -ConfigRoot $ConfigRoot -Action {
        $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
        $problem = Get-ChannelForgeUsersApiStoreProblem -Store $store
        if ($null -ne $problem) { return $problem }
        $nameProblem = Get-ChannelForgeUserNameProblem -Name $name -Users @($store.Users)
        if ($nameProblem -ne '') { return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'name-invalid' -Message $nameProblem }
        $user = New-ChannelForgeUserRecord -Name $name -Role $role -PasswordRecord $record -MustChange $true
        $saved = Write-ChannelForgeUserStore -ConfigRoot $ConfigRoot -User @(@($store.Users) + $user)
        if ($saved.Success) { Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'user-added' -Actor $Actor -Target $user -Reason "role $role" -RemoteAddress $SourceAddress }
        New-ChannelForgeUsersApiSaveResult -Saved $saved -StatusCode 201 -Body @{ User = (ConvertTo-ChannelForgeUserView -Record $user) }
    }
}

function Update-ChannelForgeUserFromRequest {
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)][string]$TargetId, [Parameter(Mandatory)]$Body, $Actor = $null, [string]$SourceAddress = '')
    $name = Get-ChannelForgeUsersApiText -Body $Body -Field 'name'
    $role = Get-ChannelForgeUsersApiText -Body $Body -Field 'role'
    $hasDisabled = $null -ne $Body.PSObject.Properties['disabled']
    $disabled = if ($hasDisabled) { $Body.disabled } else { $null }
    if (($hasDisabled -and $disabled -isnot [bool]) -or ($null -ne $role -and $role -cnotin @('admin', 'editor', 'viewer'))) {
        return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'invalid-request' -Message 'The change was not understood. Nothing was changed.'
    }
    if ($null -eq $name -and $null -eq $role -and -not $hasDisabled) {
        return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'invalid-request' -Message 'Say what to change: name, role or disabled.'
    }
    return Invoke-ChannelForgeUserStoreLocked -ConfigRoot $ConfigRoot -Action {
        $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
        $problem = Get-ChannelForgeUsersApiStoreProblem -Store $store
        if ($null -ne $problem) { return $problem }
        $target = @($store.Users | Where-Object { $_.Id -ceq $TargetId })[0]
        if ($null -eq $target) { return New-ChannelForgeUsersApiError -StatusCode 404 -Code 'user-not-found' -Message 'That user was not found.' }
        if ($null -ne $name) {
            $nameProblem = Get-ChannelForgeUserNameProblem -Name $name -Users @($store.Users) -ExceptId $TargetId
            if ($nameProblem -ne '') { return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'name-invalid' -Message $nameProblem }
        }
        $newRole = if ($null -ne $role) { $role } else { $target.Role }
        $newDisabled = if ($hasDisabled) { $disabled } else { $target.Disabled }
        if ((Test-ChannelForgeLastActiveAdmin -Users @($store.Users) -Target $target) -and ($newRole -cne 'admin' -or $newDisabled)) {
            Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'last-admin' -Result refused -Actor $Actor -Target $target -Reason 'change refused: last active Admin' -RemoteAddress $SourceAddress
            return New-ChannelForgeUsersApiError -StatusCode 409 -Code 'last-admin' -Message 'There must always be at least one active Admin.'
        }
        $changes = @()
        if ($null -ne $name -and $name -cne $target.Name) { $changes += "name $($target.Name) to $name" }
        if ($newRole -cne $target.Role) { $changes += "role $($target.Role) to $newRole" }
        if ($newDisabled -ne $target.Disabled) { $changes += $(if ($newDisabled) { 'disabled' } else { 'enabled' }) }
        if ($null -ne $name) { $target.Name = $name }
        $target.Role = $newRole
        $target.Disabled = $newDisabled
        $saved = Write-ChannelForgeUserStore -ConfigRoot $ConfigRoot -User @($store.Users)
        if ($saved.Success) { Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'user-changed' -Actor $Actor -Target $target -Reason ($changes -join ', ') -RemoteAddress $SourceAddress }
        New-ChannelForgeUsersApiSaveResult -Saved $saved -StatusCode 200 -Body @{ User = (ConvertTo-ChannelForgeUserView -Record $target) }
    }
}

function Reset-ChannelForgeUserFromRequest {
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)][string]$TargetId, [Parameter(Mandatory)]$Body, $Actor = $null, [string]$SourceAddress = '')
    $temporary = Get-ChannelForgeUsersApiText -Body $Body -Field 'temporaryPassword'
    $rule = Test-ChannelForgeAdminPasswordRule -Password $temporary
    if (-not $rule.Ok) { return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'password-rule' -Message $rule.Reason }
    $record = New-ChannelForgeAdminPasswordRecord -Password $temporary
    return Invoke-ChannelForgeUserStoreLocked -ConfigRoot $ConfigRoot -Action {
        $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
        $problem = Get-ChannelForgeUsersApiStoreProblem -Store $store
        if ($null -ne $problem) { return $problem }
        $target = @($store.Users | Where-Object { $_.Id -ceq $TargetId })[0]
        if ($null -eq $target) { return New-ChannelForgeUsersApiError -StatusCode 404 -Code 'user-not-found' -Message 'That user was not found.' }
        $saved = Set-ChannelForgeUserPassword -ConfigRoot $ConfigRoot -TargetId $TargetId -PasswordRecord $record -MustChange
        if ($saved.Success) { Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'password-reset' -Actor $Actor -Target $target -RemoteAddress $SourceAddress }
        New-ChannelForgeUsersApiSaveResult -Saved $saved -StatusCode 200 -Body @{ Reset = $true }
    }
}

function Remove-ChannelForgeUserFromRequest {
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)][string]$TargetId, $Actor = $null, [string]$SourceAddress = '')
    return Invoke-ChannelForgeUserStoreLocked -ConfigRoot $ConfigRoot -Action {
        $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
        $problem = Get-ChannelForgeUsersApiStoreProblem -Store $store
        if ($null -ne $problem) { return $problem }
        $target = @($store.Users | Where-Object { $_.Id -ceq $TargetId })[0]
        if ($null -eq $target) { return New-ChannelForgeUsersApiError -StatusCode 404 -Code 'user-not-found' -Message 'That user was not found.' }
        if (Test-ChannelForgeLastActiveAdmin -Users @($store.Users) -Target $target) {
            Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'last-admin' -Result refused -Actor $Actor -Target $target -Reason 'delete refused: last active Admin' -RemoteAddress $SourceAddress
            return New-ChannelForgeUsersApiError -StatusCode 409 -Code 'last-admin' -Message 'There must always be at least one active Admin.'
        }
        $saved = Write-ChannelForgeUserStore -ConfigRoot $ConfigRoot -User @($store.Users | Where-Object { $_.Id -cne $TargetId })
        if ($saved.Success) {
            Remove-ChannelForgeUserSettingsEntry -ConfigRoot $ConfigRoot -UserId $TargetId
            Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'user-deleted' -Actor $Actor -Target $target -RemoteAddress $SourceAddress
        }
        New-ChannelForgeUsersApiSaveResult -Saved $saved -StatusCode 200 -Body @{ Deleted = $true }
    }
}

function Invoke-ChannelForgeUsersApi {
    <#
    .SYNOPSIS
        The Users routes for a signed-in Admin (the role table has already let the request through).
    .DESCRIPTION
        GET and POST /api/users; PUT and DELETE /api/users/{id}; POST /api/users/{id}/reset-password.
        Add, delete and reset need the Admin's own password in the body (adminPassword). Passwords are never echoed.
    #>
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ActorId,
        [System.IO.Stream]$BodyStream = $null,
        [long]$ContentLength = -1,
        [Parameter(Mandatory)][string]$ConfigRoot,
        [hashtable]$Limiter = $null,
        [string]$SourceAddress = '',
        [datetime]$Now = [datetime]::UtcNow
    )
    $route = [regex]::Match($Path, '^/api/users(?:/([0-9a-f]{32})(/reset-password)?)?$')
    if (-not $route.Success) { return New-ChannelForgeUsersApiError -StatusCode 404 -Code 'not-found' -Message 'That page was not found.' }
    $targetId = $route.Groups[1].Value
    $verb = if ($targetId -eq '') { "$Method /" } elseif ($route.Groups[2].Success) { "$Method /id/reset" } else { "$Method /id" }

    $needsPassword = $verb -in @('POST /', 'DELETE /id', 'POST /id/reset')
    $needsBody = $needsPassword -or $verb -eq 'PUT /id'
    $allowed = @{ '/' = 'GET, POST'; '/id' = 'PUT, DELETE'; '/id/reset' = 'POST' }[($verb -split ' ', 2)[1]]
    if ($verb -ne 'GET /' -and -not $needsBody) {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 405 -Body @{ Error = 'method-not-allowed'; Message = 'That method is not supported here.' } -ExtraHeaders @{ Allow = $allowed }
    }
    if ($verb -eq 'GET /') {
        $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
        $problem = Get-ChannelForgeUsersApiStoreProblem -Store $store
        if ($null -ne $problem) { return $problem }
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ Users = @($store.Users | ForEach-Object { ConvertTo-ChannelForgeUserView -Record $_ }) }
    }

    $body = Read-ChannelForgeUsersApiBody -BodyStream $BodyStream -ContentLength $ContentLength
    if ($needsPassword) {
        $refusal = Confirm-ChannelForgeUsersApiAdmin -ConfigRoot $ConfigRoot -ActorId $ActorId -Body $body -Limiter $Limiter -SourceAddress $SourceAddress -Now $Now
        if ($null -ne $refusal) { return $refusal }
    }
    if ($null -eq $body) { return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'invalid-request' -Message 'The request was not understood. Nothing was changed.' }
    $actor = Get-ChannelForgeAuditPerson -ConfigRoot $ConfigRoot -UserId $ActorId
    switch ($verb) {
        'POST /' { return Add-ChannelForgeUserFromRequest -ConfigRoot $ConfigRoot -Body $body -Actor $actor -SourceAddress $SourceAddress }
        'PUT /id' { return Update-ChannelForgeUserFromRequest -ConfigRoot $ConfigRoot -TargetId $targetId -Body $body -Actor $actor -SourceAddress $SourceAddress }
        'DELETE /id' { return Remove-ChannelForgeUserFromRequest -ConfigRoot $ConfigRoot -TargetId $targetId -Actor $actor -SourceAddress $SourceAddress }
        'POST /id/reset' { return Reset-ChannelForgeUserFromRequest -ConfigRoot $ConfigRoot -TargetId $targetId -Body $body -Actor $actor -SourceAddress $SourceAddress }
    }
}
