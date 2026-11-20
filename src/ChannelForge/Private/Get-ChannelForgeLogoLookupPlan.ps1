function Get-ChannelForgeLogoLookupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry,
        [AllowEmptyCollection()][string[]]$AllowedHost = @()
    )

    # One job: from flat entries (Id, Name, Url) build the ById and ByName maps.
    # No network, no file access. Rules (design note, section 2):
    #  - a link must be a public https link with no user info (same check as pins);
    #  - an ID or a name with several different links is skipped and listed;
    #  - only hosts on the allow-list are kept; every usable host is reported.
    $links = @{ Id = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new([System.StringComparer]::Ordinal)
                Name = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[string]]]::new([System.StringComparer]::Ordinal) }
    $hostsSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $refused = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
    $allowed = [System.Collections.Generic.HashSet[string]]::new([string[]]@($AllowedHost), [System.StringComparer]::OrdinalIgnoreCase)

    $addLink = {
        param($Kind, $Key, $Link)
        if (-not $links[$Kind].ContainsKey($Key)) { $links[$Kind][$Key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal) }
        [void]$links[$Kind][$Key].Add($Link)
    }
    $refuse = { param($Reason) $refused[$Reason] = 1 + $(if ($refused.ContainsKey($Reason)) { $refused[$Reason] } else { 0 }) }

    foreach ($item in $Entry) {
        if ($item.Id.Length -gt 256 -or $item.Id -match '[\x00-\x1f\x7f]') { & $refuse 'channel ID is too long or has control characters'; continue }
        $problem = Get-ChannelForgeLogoPinLinkProblem -Logo $item.Url
        if ($problem) { & $refuse "link: $problem"; continue }
        $hostName = [System.Uri]::new($item.Url).DnsSafeHost
        $hostsSeen[$hostName] = 1 + $(if ($hostsSeen.ContainsKey($hostName)) { $hostsSeen[$hostName] } else { 0 })
        & $addLink 'Id' $item.Id $item.Url
        if (-not [string]::IsNullOrWhiteSpace($item.Name) -and $item.Name.Length -le 256 -and $item.Name -notmatch '[\x00-\x1f\x7f]') {
            $key = (Normalize-ChannelForgeName -Name $item.Name).ToLowerInvariant()
            if ($key.Length -gt 0) { & $addLink 'Name' $key $item.Url }
        }
    }

    $skipped = @{ Id = [System.Collections.Generic.List[string]]::new(); Name = [System.Collections.Generic.List[string]]::new() }
    $maps = @{}
    foreach ($kind in 'Id', 'Name') {
        $keys = [string[]]@($links[$kind].Keys)
        [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
        $maps[$kind] = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
        foreach ($key in $keys) {
            $set = $links[$kind][$key]
            if ($set.Count -ne 1) { $skipped[$kind].Add($key); continue }
            $link = @($set)[0]
            if (-not $allowed.Contains([System.Uri]::new($link).DnsSafeHost)) { & $refuse 'ID or name entries whose host is not on the allow-list'; continue }
            $maps[$kind][$key] = $link
        }
    }

    $hostKeys = [string[]]@($hostsSeen.Keys)
    [System.Array]::Sort($hostKeys, [System.StringComparer]::OrdinalIgnoreCase)
    $hostReport = [ordered]@{}
    foreach ($hostKey in $hostKeys) { $hostReport[$hostKey] = $hostsSeen[$hostKey] }

    return [pscustomobject][ordered]@{
        ById           = $maps['Id']
        ByName         = $maps['Name']
        HostsSeen      = $hostReport
        Refused        = $refused
        SkippedIds     = $skipped['Id'].ToArray()
        AmbiguousNames = $skipped['Name'].ToArray()
    }
}
