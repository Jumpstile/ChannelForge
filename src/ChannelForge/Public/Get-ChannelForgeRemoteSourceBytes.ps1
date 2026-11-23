function Get-ChannelForgeRemoteSourceBytes {
    [CmdletBinding(DefaultParameterSetName = 'Public')]
    param(
        [Parameter(Mandatory)][ValidateSet('M3U', 'XMLTV')][string]$Kind,
        [Parameter(Mandatory, ParameterSetName = 'Public')][string]$Url,
        [Parameter(Mandatory, ParameterSetName = 'Credentialed')][ValidatePattern('^[0-9a-f]{32}$')][string]$CredentialRef,
        [Parameter(Mandatory, ParameterSetName = 'Credentialed')][string]$DisplayHost,
        [Parameter(Mandatory)][int]$MaxBytes
    )

    if ($PSCmdlet.ParameterSetName -ne 'Credentialed') {
        return Read-ChannelForgeGuidedSetupRemoteBytes -Kind $Kind -Url $Url -MaxBytes $MaxBytes
    }

    # The saved login is read and used in memory only, then dropped. Failures carry the host-only message.
    $loginMessage = "The saved login for $DisplayHost is missing, unreadable or was rejected. Run the enroll command again for this source."
    $fail = {
        $failure = [System.InvalidOperationException]::new($loginMessage)
        $failure.Data['ChannelForgeLoginFailure'] = $true
        throw $failure
    }
    $link = $null
    try {
        $secret = Read-ChannelForgeSourceSecret -RefId $CredentialRef
        if (-not $secret.Success) { & $fail }
        $link = [System.Net.NetworkCredential]::new('', $secret.Secret).Password
        return Read-ChannelForgeGuidedSetupRemoteBytes -Kind $Kind -Url $link -MaxBytes $MaxBytes
    }
    catch {
        if ($_.Exception.Data['ChannelForgeLoginFailure']) { throw }
        if ([int]$_.Exception.Data['ChannelForgeFailureStatusCode'] -in 401, 403) { & $fail }
        $category = [string]$_.Exception.Data['ChannelForgeFailureCategory']
        if ([string]::IsNullOrWhiteSpace($category)) { $category = 'AcquisitionFailure' }
        $generic = [System.InvalidOperationException]::new("Remote source request failed [$category].")
        $generic.Data['ChannelForgeFailureCategory'] = $category
        throw $generic
    }
    finally {
        $link = $null
        $secret = $null
    }
}
