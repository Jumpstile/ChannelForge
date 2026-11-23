function Split-ChannelForgeSecretSourceLink {
    # Splits one pasted provider link into a host-only display value and the full link for the secret store.
    # Query and path are allowed here (the login lives there). Test-ChannelForgeSourceUrl is unchanged and still
    # rejects them for every other path. Failures carry a category and a fixed message only: never the link.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Link
    )

    $fail = {
        param([string]$Category, [string]$Message)
        [pscustomobject]@{ Succeeded = $false; FailureCategory = $Category; Message = $Message; DisplayHost = $null; SecretLink = $null }
    }

    $uri = $null
    if ([string]::IsNullOrWhiteSpace($Link) -or -not [uri]::TryCreate($Link, [UriKind]::Absolute, [ref]$uri)) {
        return & $fail 'LinkUnreadable' 'The link is not a complete web address.'
    }
    if ($uri.Scheme -ne 'https') {
        return & $fail 'SchemeRejected' 'Only https links are accepted.'
    }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
        return & $fail 'UserInfoNotSupported' 'Links with a user name and password before the host name (user:pass@host) are not supported yet. Use a link that carries the login in its path or query.'
    }
    if ([string]::IsNullOrWhiteSpace($uri.Host)) {
        return & $fail 'HostEmpty' 'The link has no host name.'
    }
    if ($uri.Port -ne 443) {
        return & $fail 'PortRejected' 'Only the standard https port (443) is accepted.'
    }
    if ($Link.Contains('#')) {
        return & $fail 'FragmentRejected' 'Links with a fragment (#) are not accepted.'
    }
    if ($uri.Host -ieq 'localhost' -or -not (Test-ChannelForgeSafeHostAddress -HostName $uri.Host)) {
        return & $fail 'HostRejected' 'The host is local or private and is not accepted.'
    }

    $displayHost = (Get-ChannelForgeRedactedSourceHost -Url $Link) -replace '/\.\.\.$', ''
    [pscustomobject]@{ Succeeded = $true; FailureCategory = $null; Message = $null; DisplayHost = $displayHost; SecretLink = $Link }
}
