function Invoke-ChannelForgeChangePassword {
    <#
    .SYNOPSIS
        Changes the admin password for a signed-in browser, then ends every other session.
    .DESCRIPTION
        A wrong current password gets the same plain refusal as sign-in and counts as a wrong try in the limiter.
        A bad new password keeps the old one. Nothing secret is echoed or logged.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Store,
        [AllowNull()][AllowEmptyString()][string]$Token,
        [System.IO.Stream]$BodyStream = $null,
        [long]$ContentLength = -1,
        [Parameter(Mandatory)][string]$ConfigRoot,
        [hashtable]$Limiter = $null,
        [string]$SourceAddress = '',
        [datetime]$Now = [datetime]::UtcNow,
        [Parameter(Mandatory)][string]$UserId
    )
    $waitResponse = Get-ChannelForgeSignInWaitResponse -Limiter $Limiter -Address $SourceAddress -Now $Now
    if ($null -ne $waitResponse) { return $waitResponse }
    $current = $null
    $new = $null
    try {
        $bytes = Read-ChannelForgeWebRequestBody -Stream $BodyStream -ContentLength $ContentLength -MaxBytes 4096
        $body = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
        $current = [string]$body.currentPassword
        $new = [string]$body.newPassword
    }
    catch { $current = $null }

    $user = Get-ChannelForgeWebSessionUser -ConfigRoot $ConfigRoot -UserId $UserId
    if (-not (Test-ChannelForgeAdminPassword -Password $current -Record $user.Password)) {
        if ($null -ne $Limiter) { Register-ChannelForgeSignInFailure -Limiter $Limiter -Address $SourceAddress -Now $Now }
        Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'change-password' -Result refused -Actor $user -Reason 'wrong current password' -RemoteAddress $SourceAddress -Now $Now
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 401 -Body @{ Error = 'sign-in-failed'; Message = 'That password did not work.' }
    }
    if ($null -ne $Limiter) { Clear-ChannelForgeSignInFailure -Limiter $Limiter -Address $SourceAddress }
    $rule = Test-ChannelForgeAdminPasswordRule -Password $new
    if (-not $rule.Ok) {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 400 -Body @{ Error = 'password-rule'; Message = $rule.Reason }
    }
    $saved = Set-ChannelForgeUserPassword -ConfigRoot $ConfigRoot -TargetId $user.Id -PasswordRecord (New-ChannelForgeAdminPasswordRecord -Password $new)
    if (-not $saved.Success) {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 500 -Body @{ Error = 'password-not-saved'; Message = 'The password could not be saved. Check that ChannelForge can write to its settings folder. Your old password still works.' }
    }
    $fresh = Get-ChannelForgeWebSessionUser -ConfigRoot $ConfigRoot -UserId $UserId
    $session = Get-ChannelForgeWebSession -Store $Store -Token $Token -Now $Now
    if ($null -ne $fresh -and $null -ne $session) { Update-ChannelForgeWebSessionPasswordStamp -Session $session -User $fresh -Now $Now }
    Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'change-password' -Actor $user -Target $user -RemoteAddress $SourceAddress -Now $Now
    return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ Changed = $true }
}
