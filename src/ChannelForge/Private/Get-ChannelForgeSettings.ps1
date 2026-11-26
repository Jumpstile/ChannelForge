function Get-ChannelForgeAppearanceChoices {
    return @('light', 'dark', 'system')
}

function Get-ChannelForgeSettingsFolder {
    <#
    .SYNOPSIS
        The folder that holds settings.json: the server's config folder, or state\config under the install when no config folder was given.
    #>
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [string]$ConfigRoot = ''
    )
    if ([string]::IsNullOrWhiteSpace($ConfigRoot)) { return (Join-Path $RepositoryRoot 'state\config') }
    return $ConfigRoot
}

function Read-ChannelForgeSettings {
    <#
    .SYNOPSIS
        Reads settings.json. Never throws. Status is 'Missing', 'Ok' or 'Corrupt'; Appearance is the saved value, or 'system' when there is none.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Folder)

    $path = Join-Path $Folder 'settings.json'
    $result = [pscustomobject]@{ Status = 'Missing'; Appearance = 'system'; Path = $path }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $result }
    try {
        if (([System.IO.FileInfo]$path).Length -gt 4096) { throw 'too large' }
        $record = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -ErrorAction Stop
        $names = @($record.PSObject.Properties.Name | Sort-Object) -join ','
        if ($names -cne 'appearance,schema' -or [int]$record.schema -ne 1 -or [string]$record.appearance -cnotin (Get-ChannelForgeAppearanceChoices)) { throw 'not a valid settings file' }
        $result.Status = 'Ok'
        $result.Appearance = [string]$record.appearance
    }
    catch { $result.Status = 'Corrupt' }
    return $result
}

function Save-ChannelForgeSettings {
    <#
    .SYNOPSIS
        Saves settings.json with the engine's temp-file-then-replace writer.
    .DESCRIPTION
        An unreadable settings.json is renamed to settings.json.bad-<time> first, never deleted or overwritten.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Appearance
    )

    if ($Appearance -cnotin (Get-ChannelForgeAppearanceChoices)) { throw [System.ArgumentException]::new('The appearance value is not supported.') }
    $current = Read-ChannelForgeSettings -Folder $Folder
    if ($current.Status -eq 'Corrupt') {
        [System.IO.File]::Move($current.Path, ($current.Path + '.bad-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')))
    }
    Write-ChannelForgeSourceEnrollmentAtomicJson -Path (Join-Path $Folder 'settings.json') -AllowedRoot $Folder -Value ([ordered]@{ schema = 1; appearance = $Appearance })
}

function Get-ChannelForgeWebSettingsResponse {
    <#
    .SYNOPSIS
        Handles GET and PUT /api/settings. Known field: appearance (light, dark or system). Any other field gets invalid-settings.
    #>
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [byte[]]$BodyBytes = $null,
        [string]$ContentType = '',
        [long]$ContentLength = -1
    )

    $fail = { param([int]$Status, [string]$Code, [string]$Message) New-ChannelForgeWebProposalErrorResponse -StatusCode $Status -ErrorCode $Code -Message $Message -Headers $Headers }
    $methodName = $Method.ToUpperInvariant()
    if ($methodName -notin @('GET', 'HEAD', 'PUT')) {
        $allowHeaders = [ordered]@{ Allow = 'GET, HEAD, PUT' }
        foreach ($header in $Headers.GetEnumerator()) { $allowHeaders[$header.Key] = $header.Value }
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 405 -ErrorCode 'method-not-allowed' -Message 'Only GET and PUT requests are supported for settings.' -Headers $allowHeaders
    }

    if ($methodName -eq 'PUT') {
        if (([string]$ContentType -split ';')[0].Trim() -ine 'application/json') { return & $fail 415 'unsupported-media-type' 'Settings must be sent as JSON.' }
        if ($null -eq $BodyBytes -or $BodyBytes.Length -eq 0) { return & $fail 400 'missing-request-body' 'A settings request is required.' }
        if ($BodyBytes.Length -gt 1024 -or $ContentLength -gt 1024) { return & $fail 413 'request-too-large' 'The settings request is too large.' }
        if ($ContentLength -ge 0 -and $ContentLength -ne $BodyBytes.Length) { return & $fail 400 'request-length-mismatch' 'The settings request length does not match its body.' }
        $invalid = { & $fail 400 'invalid-settings' 'The settings request is not valid. Only appearance (light, dark or system) can be set.' }
        try { $request = [System.Text.UTF8Encoding]::new($false, $true).GetString($BodyBytes) | ConvertFrom-Json -ErrorAction Stop } catch { return & $invalid }
        if ($request -isnot [pscustomobject] -or (@($request.PSObject.Properties.Name) -join ',') -cne 'appearance') { return & $invalid }
        if ($request.appearance -isnot [string] -or $request.appearance -cnotin (Get-ChannelForgeAppearanceChoices)) { return & $invalid }
        try { Save-ChannelForgeSettings -Folder $Folder -Appearance $request.appearance }
        catch { return & $fail 500 'settings-not-saved' 'ChannelForge could not save the setting.' }
    }

    $settings = Read-ChannelForgeSettings -Folder $Folder
    $body = [ordered]@{ appearance = $settings.Appearance; saved = ($settings.Status -eq 'Ok') }
    if ($settings.Status -eq 'Corrupt') { $body['problem'] = 'ChannelForge could not read its saved settings, so it is using the defaults. The unreadable file is kept and is not deleted.' }
    return New-ChannelForgeWebResponse -StatusCode 200 -ContentType 'application/json; charset=utf-8' -Body ($body | ConvertTo-Json -Compress) -Headers $Headers
}
