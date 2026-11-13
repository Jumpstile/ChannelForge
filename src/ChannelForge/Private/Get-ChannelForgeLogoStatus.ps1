function Get-ChannelForgeLogoStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url
    )

    # Classifies a channel logo URL as Empty, NotHttps, PrivateAddress or
    # Public (issue #191). String check only: no DNS lookup, no network.
    # Literal-IP ranges come from Test-ChannelForgeSafeHostAddress.
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return 'Empty'
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Url.Trim(), [System.UriKind]::Absolute, [ref]$parsedUri) -or
        $parsedUri.Scheme -ne 'https' -or
        [string]::IsNullOrWhiteSpace($parsedUri.DnsSafeHost)) {
        return 'NotHttps'
    }

    $hostName = $parsedUri.DnsSafeHost
    $isLocalName = ($hostName -ieq 'localhost') -or
        ($hostName -imatch '\.(local|lan)$') -or
        (($hostName -notmatch '[.:]'))

    if ($isLocalName -or -not (Test-ChannelForgeSafeHostAddress -HostName $hostName)) {
        return 'PrivateAddress'
    }

    return 'Public'
}
