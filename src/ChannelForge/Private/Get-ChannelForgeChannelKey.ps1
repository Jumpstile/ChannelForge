function Get-ChannelForgeChannelKey {
    # The one place a channel's decision key is made: SHA-256 (lowercase hex) of the
    # stream URL, trimmed, with the scheme and host lowercased. Name and guide ID are
    # not part of the key, so renaming or regrouping a channel keeps its decision.
    # Replace the body when the Identity layer assigns keys to imported playlists.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Url)

    $text = $Url.Trim()
    if ([string]::IsNullOrEmpty($text)) { throw 'A channel has no stream address, so it cannot get a decision key.' }
    $match = [regex]::Match($text, '^([A-Za-z][A-Za-z0-9+.\-]*://)([^/?#]*)(.*)$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) {
        $authority = $match.Groups[2].Value
        $at = $authority.LastIndexOf('@')
        $hostPart = $authority.Substring($at + 1).ToLowerInvariant()
        $text = $match.Groups[1].Value.ToLowerInvariant() + $authority.Substring(0, $at + 1) + $hostPart + $match.Groups[3].Value
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) }
    finally { $sha.Dispose() }
    return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}
