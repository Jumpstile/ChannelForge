function Get-ChannelForgeLogoPinLinkProblem {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Logo
    )

    # One job: return a plain reason (never the link itself) when a pin link
    # is not allowed, or $null when it is fine. String check only, no network.
    $status = Get-ChannelForgeLogoStatus -Url ([string]$Logo)
    if ($status -ne 'Public') {
        return "the link is not a public https link ($status)"
    }
    if ($Logo -match '[\x00-\x20"\x7f]') {
        return 'the link has spaces, quotes or control characters'
    }
    $parsedUri = [System.Uri]::new($Logo)
    if (-not [string]::IsNullOrEmpty($parsedUri.UserInfo)) {
        return 'the link has a user name or password in it'
    }
    return $null
}
