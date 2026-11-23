function Get-ChannelForgeRedactedSourceHost {
    # Shows scheme, host and port only. Provider tokens often sit in the path, so the path, query and credentials are dropped too.
    param([Parameter(Mandatory)][string]$Url)
    $uri = $null
    if (-not [uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return '[unreadable address]' }
    return '{0}://{1}/...' -f $uri.Scheme, $uri.Authority.Substring($uri.Authority.LastIndexOf('@') + 1)
}

function Get-ChannelForgeSourceReachabilityFinding {
    # One finding for one configured source. Remote: bounded probe through the ADR-0014 transport; local: exists and readable.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [string]$Url,
        [string]$LocalPath,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [int]$ProbeBytes = 4096,
        [ValidatePattern('^[0-9a-f]{32}$')][string]$CredentialRef,
        [string]$DisplayHost
    )
    $check = "$Kind source '$Name' reachable"
    $expected = 'The source answers with a usable response.'
    if (-not $CredentialRef -and [string]::IsNullOrWhiteSpace($Url)) {
        $shown = Get-ChannelForgePreflightDisplayRoot -Path $LocalPath -RepositoryRoot $RepositoryRoot
        $notTested = 'Whether the file content is valid.'
        $problem = $null
        try {
            Assert-ChannelForgeReadPath -Path $LocalPath -AllowedRoot $RepositoryRoot
            if (-not [IO.File]::Exists($LocalPath)) { $problem = 'The file does not exist.' }
            else { $stream = [IO.File]::OpenRead($LocalPath); $stream.Dispose() }
        }
        catch { $problem = 'The file is outside the project or cannot be read.' }
        if ($problem) {
            return New-ChannelForgePreflightFinding -Check $check -Root $shown -Status Fail -Observed $problem -Expected 'The local file exists and can be read.' -NotTested $notTested -NextStep 'Fix the local file path in your source settings, or restore the file.'
        }
        return New-ChannelForgePreflightFinding -Check $check -Root $shown -Status Pass -Observed 'The local file exists and can be read.' -Expected 'The local file exists and can be read.' -NotTested $notTested
    }

    $secretLink = $null
    if ($CredentialRef) {
        $shown = "$DisplayHost/..."
        $saved = Read-ChannelForgeSourceSecret -RefId $CredentialRef
        if (-not $saved.Success) {
            return New-ChannelForgePreflightFinding -Check $check -Root $shown -Status Fail -Observed "The saved login for $DisplayHost is missing, unreadable or was rejected ($($saved.Category))." -Expected $expected -NotTested 'Whether the provider is reachable.' -NextStep 'Run the enroll command again for this source.'
        }
        $secretLink = [System.Net.NetworkCredential]::new('', $saved.Secret).Password
        $Url = $secretLink
    }
    else { $shown = Get-ChannelForgeRedactedSourceHost -Url $Url }
    $notTested = 'Full download, content validity and login rights beyond the first response.'
    $payload = $null
    try {
        $payload = if ($Kind -eq 'M3U') {
            Invoke-ChannelForgePinnedHttpM3UAcquisition -SourceId 'doctor-probe' -Url $Url -MaxRawResponseBytes 16MB
        }
        else {
            Invoke-ChannelForgePinnedHttpXmltvAcquisition -SourceId 'doctor-probe' -Url $Url -MaxRawResponseBytes 16MB
        }
        $buffer = [byte[]]::new($ProbeBytes)
        $read = $payload.ResponseStream.Read($buffer, 0, $buffer.Length)
        if ($read -gt 0) {
            return New-ChannelForgePreflightFinding -Check $check -Root $shown -Status Pass -Observed "The source answered and the first $read bytes were readable." -Expected $expected -NotTested $notTested
        }
        return New-ChannelForgePreflightFinding -Check $check -Root $shown -Status Fail -Observed 'The source answered but sent no data.' -Expected $expected -NotTested $notTested -NextStep 'Check the source address and your provider account, then run the Doctor again.'
    }
    catch {
        $category = [string]$_.Exception.Data['ChannelForgeFailureCategory']
        if ($category -in 'HelperInitializationFailure', 'ContractMismatch') {
            return New-ChannelForgePreflightFinding -Check $check -Root $shown -Status Unknown -Observed 'The secure download helper could not start, so the source was not tested.' -Expected $expected -NotTested $notTested -NextStep 'Run the Doctor again. If it repeats, see the troubleshooting guide.'
        }
        if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Unreadable' }
        $observed = Remove-ChannelForgeSecretFromText -Text "The source could not be reached ($category)." -Secret $secretLink
        return New-ChannelForgePreflightFinding -Check $check -Root $shown -Status Fail -Observed $observed -Expected $expected -NotTested $notTested -NextStep 'Check the source address, your internet connection and your provider account, then run the Doctor again.'
    }
    finally {
        $secretLink = $null
        if ($null -ne $payload) { try { $payload.Dispose() } catch { $null = $_ } }
    }
}

function Get-ChannelForgeSourceReachabilityFindings {
    # Reads the configured sources the same way the refresh script does and returns one finding per enabled source.
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ProviderConfigPath,
        [Parameter(Mandatory)][string]$EpgConfigPath
    )
    $items = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($s in @(Read-ChannelForgeProvider -Path $ProviderConfigPath | Where-Object Enabled)) {
            $local = if ($s.LocalPlaylist) { Join-Path $RepositoryRoot $s.LocalPlaylist } else { '' }
            $items.Add(@{ Name = [string]$s.Name; Kind = 'M3U'; Url = $(if ($local) { '' } else { [string]$s.Url }); LocalPath = $local })
        }
        foreach ($s in @(Read-ChannelForgeEpgSource -Path $EpgConfigPath | Where-Object Enabled)) {
            $items.Add(@{ Name = [string]$s.Name; Kind = 'XMLTV'; Url = [string]$s.Url; LocalPath = [string]$s.Path })
        }
    }
    catch {
        return @(New-ChannelForgePreflightFinding -Check 'source settings readable' -Root '[source settings]' -Status Unknown -Observed 'The source settings could not be read, so no source was tested.' -Expected 'The provider and guide settings load.' -NextStep 'Fix the provider and guide settings files, then run the Doctor again.')
    }
    $recordFinding = $null
    try {
        $record = Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $RepositoryRoot
        foreach ($s in @($record.Playlists) + @($record.Guides)) {
            if ($s.Enabled -and $null -ne $s.PSObject.Properties['CredentialRef']) {
                $items.Add(@{ Name = [string]$s.Label; Kind = [string]$s.Kind; CredentialRef = [string]$s.CredentialRef; DisplayHost = [string]$s.DisplayHost })
            }
        }
    }
    catch {
        if ("$($_.Exception.Message)" -notlike 'SOURCE_ENROLLMENT_UNAVAILABLE*') {
            $recordFinding = New-ChannelForgePreflightFinding -Check 'saved login sources readable' -Root '[source settings]' -Status Unknown -Observed 'The saved source list could not be read, so saved-login sources were not tested.' -Expected 'The saved source list loads.' -NextStep 'Run the source enrollment status check, then run the Doctor again.'
        }
    }
    if ($items.Count -eq 0 -and -not $recordFinding) {
        return @(New-ChannelForgePreflightFinding -Check 'sources configured' -Root '[source settings]' -Status Unknown -Observed 'No enabled source was found, so nothing was tested.' -Expected 'At least one enabled source.' -NextStep 'Add or enable a source, then run the Doctor again.')
    }
    if ($recordFinding) { $recordFinding }
    foreach ($i in $items) { Get-ChannelForgeSourceReachabilityFinding @i -RepositoryRoot $RepositoryRoot }
}
