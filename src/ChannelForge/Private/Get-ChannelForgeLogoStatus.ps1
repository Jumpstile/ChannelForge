function Get-ChannelForgeLogoStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url
    )

    # Classifies a channel logo URL as Empty, DataUri, TooLong, BadCharacters,
    # NotHttps, PrivateAddress or Public (issues #191, #41). String check only:
    # no DNS lookup, no network. Literal-IP ranges come from
    # Test-ChannelForgeSafeHostAddress. Only Public is ever published.
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return 'Empty'
    }

    $Url = $Url.Trim()
    if ($Url -imatch '^data:') {
        return 'DataUri'
    }
    if ($Url.Length -gt 2048) {
        return 'TooLong'
    }
    if ($Url -match '[\x00-\x1F\x7F]') {
        return 'BadCharacters'
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsedUri) -or
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
