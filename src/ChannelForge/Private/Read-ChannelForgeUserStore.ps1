function Test-ChannelForgeExactKeys {
    # True only for a parsed JSON object that has exactly these property names, no more and no fewer.
    param([AllowNull()]$Object, [Parameter(Mandatory)][string[]]$Keys)
    if ($Object -isnot [pscustomobject]) { return $false }
    $names = @($Object.PSObject.Properties.Name)
    return $names.Count -eq $Keys.Count -and @($names | Where-Object { $_ -cnotin $Keys }).Count -eq 0
}

function Test-ChannelForgePasswordRecordShape {
    # Same limits Test-ChannelForgeAdminPassword applies when it checks a password.
    param([AllowNull()]$Record)
    if (-not (Test-ChannelForgeExactKeys -Object $Record -Keys @('Schema', 'Algorithm', 'Iterations', 'Salt', 'Hash'))) { return $false }
    foreach ($number in $Record.Schema, $Record.Iterations) { if ($number -isnot [int] -and $number -isnot [long]) { return $false } }
    if ($Record.Schema -ne 1 -or $Record.Algorithm -isnot [string] -or $Record.Algorithm -cne 'PBKDF2-SHA256') { return $false }
    if ($Record.Iterations -lt 1 -or $Record.Iterations -gt 10000000) { return $false }
    foreach ($field in @(@('Salt', 8), @('Hash', 16))) {
        $text = $Record.($field[0])
        if ($text -isnot [string]) { return $false }
        try { $bytes = [System.Convert]::FromBase64String($text) } catch { return $false }
        if ($bytes.Length -lt $field[1]) { return $false }
    }
    return $true
}

function Test-ChannelForgeUserStoreDocument {
    <#
    .SYNOPSIS
        True only when a parsed users.json is exactly the schema-1 shape. Any unknown or missing field is false.
    #>
    param([AllowNull()]$Document)
    try {
        if (-not (Test-ChannelForgeExactKeys -Object $Document -Keys @('Schema', 'Users'))) { return $false }
        if (($Document.Schema -isnot [int] -and $Document.Schema -isnot [long]) -or $Document.Schema -ne 1) { return $false }
        if ($Document.Users -isnot [System.Array] -or $Document.Users.Count -lt 1) { return $false }
        $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($user in $Document.Users) {
            $keys = @('Id', 'Name', 'Role', 'Password', 'MustChange', 'Disabled', 'CreatedUtc')
            # PasswordChangedUtc is optional so a schema-1 file written before it existed still reads.
            if ($null -ne $user.PSObject.Properties['PasswordChangedUtc']) { $keys += 'PasswordChangedUtc' }
            if (-not (Test-ChannelForgeExactKeys -Object $user -Keys $keys)) { return $false }
            if ($user.Id -isnot [string] -or $user.Id -cnotmatch '^[0-9a-f]{32}\z' -or -not $ids.Add($user.Id)) { return $false }
            if ($user.Name -isnot [string] -or $user.Name -cnotmatch '^[A-Za-z0-9._-]{3,32}\z' -or -not $names.Add($user.Name)) { return $false }
            if ($user.Role -isnot [string] -or $user.Role -cnotin @('admin', 'editor', 'viewer')) { return $false }
            if ($user.MustChange -isnot [bool] -or $user.Disabled -isnot [bool]) { return $false }
            foreach ($stamp in $keys[6..($keys.Count - 1)]) {
                if ($user.$stamp -isnot [string] -or $user.$stamp -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z') { return $false }
            }
            if (-not (Test-ChannelForgePasswordRecordShape -Record $user.Password)) { return $false }
        }
        return $true
    }
    catch { return $false }
}

function Read-ChannelForgeUserStoreFile {
    <#
    .SYNOPSIS
        Reads one users.json strictly. Never throws and never touches the file. Returns Status ('Ok' or 'Corrupt') and Users.
    .DESCRIPTION
        A path that leaves the config folder, a reparse point, a folder, a file over 64 KiB, bad UTF-8,
        bad JSON or any field that is not allowed all give Corrupt.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ConfigRoot)
    try {
        Assert-ChannelForgeSourceEnrollmentPath -Path $Path -AllowedRoot $ConfigRoot | Out-Null
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 65536) {
            return [pscustomobject]@{ Status = 'Corrupt'; Users = @() }
        }
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($Path))
        $document = $text | ConvertFrom-Json -DateKind String -ErrorAction Stop
        if (Test-ChannelForgeUserStoreDocument -Document $document) {
            # A record from before PasswordChangedUtc existed reads as changed when it was created.
            foreach ($user in $document.Users) {
                if ($null -eq $user.PSObject.Properties['PasswordChangedUtc']) { $user | Add-Member -NotePropertyName PasswordChangedUtc -NotePropertyValue $user.CreatedUtc }
            }
            return [pscustomobject]@{ Status = 'Ok'; Users = @($document.Users) }
        }
    }
    catch { $null = $_ }
    return [pscustomobject]@{ Status = 'Corrupt'; Users = @() }
}

function Read-ChannelForgeUserStore {
    <#
    .SYNOPSIS
        The one way to read who can sign in. Never throws. Returns Status ('Missing', 'Ok' or 'Corrupt') and Users.
    .DESCRIPTION
        users.json wins. If it is missing and a good admin-password.json exists, it is upgraded first
        (see Invoke-ChannelForgeUserStoreUpgrade). A damaged file of either kind gives Corrupt and is never touched.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot)
    $path = Join-Path $ConfigRoot 'users.json'
    if ([System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path)) {
        return Read-ChannelForgeUserStoreFile -Path $path -ConfigRoot $ConfigRoot
    }
    $legacy = Read-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot
    if ($legacy.Status -eq 'Ok') { return Invoke-ChannelForgeUserStoreUpgrade -ConfigRoot $ConfigRoot -PasswordRecord $legacy.Record }
    return [pscustomobject]@{ Status = $legacy.Status; Users = @() }
}

function Get-ChannelForgeSignInUser {
    <#
    .SYNOPSIS
        The user who signs in with the password alone (slice 1: the one admin), or $null. Sign-in by name comes later.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot)
    $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
    if ($store.Status -ne 'Ok') { return $null }
    return @($store.Users | Where-Object { $_.Role -ceq 'admin' -and -not $_.Disabled })[0]
}

function Find-ChannelForgeSignInUser {
    <#
    .SYNOPSIS
        The enabled user for a sign-in name (case-insensitive), or $null. With no name, the one enabled user when there is exactly one.
    #>
    param([Parameter(Mandatory)][string]$ConfigRoot, [AllowNull()][AllowEmptyString()][string]$Name)
    $store = Read-ChannelForgeUserStore -ConfigRoot $ConfigRoot
    if ($store.Status -ne 'Ok') { return $null }
    $enabled = @($store.Users | Where-Object { -not $_.Disabled })
    if ([string]::IsNullOrWhiteSpace($Name)) { return $(if ($enabled.Count -eq 1) { $enabled[0] } else { $null }) }
    return @($enabled | Where-Object { $_.Name -ieq $Name.Trim() })[0]
}

function Get-ChannelForgeDummyPasswordRecord {
    # A throwaway record nobody can match, so an unknown name still costs one real password check. Built once per iteration count.
    param([int]$Iterations = 600000)
    if ($null -eq $script:ChannelForgeDummyRecords) { $script:ChannelForgeDummyRecords = @{} }
    if (-not $script:ChannelForgeDummyRecords.ContainsKey($Iterations)) {
        $unused = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
        $script:ChannelForgeDummyRecords[$Iterations] = New-ChannelForgeAdminPasswordRecord -Password $unused -Iterations $Iterations
    }
    return $script:ChannelForgeDummyRecords[$Iterations]
}
