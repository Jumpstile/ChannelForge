function Read-ChannelForgeLogoLookupFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    # One job: read the existing data\logo-lookup.json for the refresh command.
    # Missing file: returns $null. Unreadable file: throws, so the refresh never
    # overwrites a file it cannot understand. Never writes.
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    $maps = @{}
    try {
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($Path))
        $doc = $text | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($doc -isnot [System.Collections.IDictionary] -or $doc['Version'] -cne 'logo-lookup/v1') { throw 'wrong version' }
        foreach ($kind in 'ById', 'ByName') {
            $maps[$kind] = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
            if (-not $doc.Contains($kind)) { continue }
            if ($doc[$kind] -isnot [System.Collections.IDictionary]) { throw "$kind is not an object" }
            foreach ($key in $doc[$kind].Keys) {
                if ($doc[$kind][$key] -isnot [string]) { throw "$kind has a value that is not a link" }
                $maps[$kind][[string]$key] = $doc[$kind][$key]
            }
        }
    }
    catch {
        throw "The existing logo lookup file is unreadable ($($_.Exception.Message)). Nothing was changed. Fix or remove it, then run again."
    }
    return [pscustomobject][ordered]@{ ById = $maps['ById']; ByName = $maps['ByName'] }
}
