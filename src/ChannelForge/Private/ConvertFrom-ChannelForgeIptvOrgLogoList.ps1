function ConvertFrom-ChannelForgeIptvOrgLogoList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    # One job: turn the downloaded list into flat entries (Id, Name, Url).
    # ASSUMED shape (UNVERIFIED, check against a real dry run): a JSON array of
    # objects. Each object has "channel" (the channel ID, for example
    # "Example.us") and "url" (the logo link). An optional "name" (the channel
    # name) feeds ByName. Any other property is ignored. Objects without a
    # channel or url are dropped and counted in the Malformed property.
    try {
        $parsed = $Text | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
    }
    catch {
        throw 'The logo list is not valid JSON.'
    }
    if ($parsed -isnot [System.Array]) {
        throw 'The logo list is not a JSON array. The parser assumes an array of objects with "channel" and "url".'
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $malformed = 0
    foreach ($item in $parsed) {
        $names = if ($item -is [psobject]) { @($item.PSObject.Properties.Name) } else { @() }
        $id = if ($names -contains 'channel') { $item.channel } else { $null }
        $url = if ($names -contains 'url') { $item.url } else { $null }
        if ($id -isnot [string] -or $url -isnot [string] -or [string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($url)) {
            $malformed++
            continue
        }
        $name = if ($names -contains 'name' -and $item.name -is [string]) { $item.name } else { '' }
        $entries.Add([pscustomobject][ordered]@{ Id = $id; Name = $name; Url = $url.Trim() })
    }
    return [pscustomobject][ordered]@{ Entries = $entries.ToArray(); Malformed = $malformed }
}
