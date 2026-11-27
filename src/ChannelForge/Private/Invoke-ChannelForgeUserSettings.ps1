function Read-ChannelForgeUserSettings {
    <#
    .SYNOPSIS
        Reads user-settings.json. Never throws. Status is 'Missing', 'Ok' or 'Corrupt'; Entries holds one { Id; Appearance } per user with a saved value.
    .DESCRIPTION
        Schema 1: { Schema, Users: [ { Id, Settings: { appearance } } ] }. An unreadable file gives the defaults (no entries).
        A leftover entry for a user who no longer exists is harmless: nobody asks for it.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot)
    $path = Join-Path $ConfigRoot 'user-settings.json'
    $result = [pscustomobject]@{ Status = 'Missing'; Entries = @(); Path = $path }
    if (-not [System.IO.File]::Exists($path)) { return $result }
    try {
        if (([System.IO.FileInfo]$path).Length -gt 65536) { throw 'too large' }
        $document = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-ChannelForgeExactKeys -Object $document -Keys @('Schema', 'Users')) -or $document.Schema -isnot [long] -or $document.Schema -ne 1 -or $document.Users -isnot [System.Array]) { throw 'not valid' }
        $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $entries = foreach ($entry in $document.Users) {
            if (-not (Test-ChannelForgeExactKeys -Object $entry -Keys @('Id', 'Settings')) -or $entry.Id -isnot [string] -or $entry.Id -cnotmatch '^[0-9a-f]{32}\z' -or -not $ids.Add($entry.Id)) { throw 'not valid' }
            if (-not (Test-ChannelForgeExactKeys -Object $entry.Settings -Keys @('appearance')) -or $entry.Settings.appearance -isnot [string] -or $entry.Settings.appearance -cnotin (Get-ChannelForgeAppearanceChoices)) { throw 'not valid' }
            [pscustomobject]@{ Id = $entry.Id; Appearance = $entry.Settings.appearance }
        }
        $result.Entries = @($entries)
        $result.Status = 'Ok'
    }
    catch { $result.Status = 'Corrupt'; $result.Entries = @() }
    return $result
}

function Get-ChannelForgeUserAppearance {
    # This user's saved appearance, or $null when there is none (or the file is unreadable).
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)][string]$UserId)
    return @((Read-ChannelForgeUserSettings -ConfigRoot $ConfigRoot).Entries | Where-Object { $_.Id -ceq $UserId })[0].Appearance
}

function Write-ChannelForgeUserSettingsEntries {
    # Saves the entries with the durable writer. An unreadable file is renamed aside first, never deleted. Returns $true when saved.
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)]$Current, [object[]]$Entries)
    try {
        if ($Current.Status -eq 'Corrupt') {
            [System.IO.File]::Move($Current.Path, ($Current.Path + '.bad-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')))
        }
        $users = @($Entries | ForEach-Object { [ordered]@{ Id = $_.Id; Settings = [ordered]@{ appearance = $_.Appearance } } })
        Write-ChannelForgeSourceEnrollmentAtomicJson -Path $Current.Path -AllowedRoot $ConfigRoot -Value ([ordered]@{ Schema = 1; Users = $users })
        return $true
    }
    catch { return $false }
}

function Set-ChannelForgeUserAppearance {
    # Saves one user's appearance under the users lock. Returns $true when saved.
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)][string]$UserId, [Parameter(Mandatory)][string]$Appearance)
    return Invoke-ChannelForgeUserStoreLocked -ConfigRoot $ConfigRoot -Action {
        $current = Read-ChannelForgeUserSettings -ConfigRoot $ConfigRoot
        $others = @($current.Entries | Where-Object { $_.Id -cne $UserId })
        Write-ChannelForgeUserSettingsEntries -ConfigRoot $ConfigRoot -Current $current -Entries @($others + [pscustomobject]@{ Id = $UserId; Appearance = $Appearance })
    }
}

function Remove-ChannelForgeUserSettingsEntry {
    # Drops a deleted user's entry. Call it inside the locked delete. Nothing to drop, or an unreadable file, changes nothing.
    param([Parameter(Mandatory)][string]$ConfigRoot, [Parameter(Mandatory)][string]$UserId)
    $current = Read-ChannelForgeUserSettings -ConfigRoot $ConfigRoot
    if (@($current.Entries | Where-Object { $_.Id -ceq $UserId }).Count -eq 0) { return }
    $null = Write-ChannelForgeUserSettingsEntries -ConfigRoot $ConfigRoot -Current $current -Entries @($current.Entries | Where-Object { $_.Id -cne $UserId })
}

function Invoke-ChannelForgeMySettingsApi {
    <#
    .SYNOPSIS
        GET and PUT /api/settings/me for the signed-in user. The user is the session's user; no id is ever read from the request.
    .DESCRIPTION
        Known setting: appearance (light, dark or system). Any other name is a 400. GET returns the user's saved value (or null)
        and the effective one: the user's value, else the server-wide value, else system.
    #>
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$ActorId,
        [System.IO.Stream]$BodyStream = $null,
        [long]$ContentLength = -1,
        [Parameter(Mandatory)][string]$ConfigRoot,
        [string]$SourceAddress = '',
        [datetime]$Now = [datetime]::UtcNow
    )
    if ($Method -notin @('GET', 'HEAD', 'PUT')) {
        return New-ChannelForgeWebSignInJsonResponse -StatusCode 405 -Body @{ Error = 'method-not-allowed'; Message = 'That method is not supported here.' } -ExtraHeaders @{ Allow = 'GET, HEAD, PUT' }
    }
    if ($Method -eq 'PUT') {
        $body = Read-ChannelForgeUsersApiBody -BodyStream $BodyStream -ContentLength $ContentLength
        $choice = Get-ChannelForgeUsersApiText -Body $body -Field 'appearance'
        if ($null -eq $body -or (@($body.PSObject.Properties.Name) -join ',') -cne 'appearance' -or $null -eq $choice -or $choice -cnotin (Get-ChannelForgeAppearanceChoices)) {
            return New-ChannelForgeUsersApiError -StatusCode 400 -Code 'invalid-settings' -Message 'The settings request is not valid. Only appearance (light, dark or system) can be set.'
        }
        if (-not (Set-ChannelForgeUserAppearance -ConfigRoot $ConfigRoot -UserId $ActorId -Appearance $choice)) {
            return New-ChannelForgeUsersApiError -StatusCode 500 -Code 'settings-not-saved' -Message 'ChannelForge could not save the setting.'
        }
        Write-ChannelForgeAuditEvent -ConfigRoot $ConfigRoot -EventName 'settings-changed' -Actor (Get-ChannelForgeAuditPerson -ConfigRoot $ConfigRoot -UserId $ActorId) -Reason "appearance $choice" -RemoteAddress $SourceAddress -Now $Now
    }
    $mine = Get-ChannelForgeUserAppearance -ConfigRoot $ConfigRoot -UserId $ActorId
    $effective = if ($null -ne $mine) { $mine } else { (Read-ChannelForgeSettings -Folder $ConfigRoot).Appearance }
    return New-ChannelForgeWebSignInJsonResponse -StatusCode 200 -Body @{ appearance = $mine; effective = $effective }
}
