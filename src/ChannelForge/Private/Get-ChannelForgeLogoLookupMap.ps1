function Add-ChannelForgeLogoLookupEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Section,
        [AllowNull()][object]$Table,
        [Parameter(Mandatory)][hashtable]$Map
    )

    # One section (ById or ByName) of the lookup file into the map. A bad
    # entry is skipped and noted in Ignored; nothing here throws.
    foreach ($entry in @($Table.PSObject.Properties)) {
        $key = [string]$entry.Name
        $value = $entry.Value
        if ($Section -eq 'ByName' -and $value -is [array] -and $value.Count -gt 1) {
            [void]$Map.Ambiguous.Add($key)
            $Map.Ignored.Add("ByName '$key': more than one link")
        }
        elseif ($key.Length -eq 0 -or ($Section -eq 'ByName' -and $key -cne (ConvertTo-ChannelForgeLogoLookupNameKey -Name $key))) {
            $Map.Ignored.Add("${Section} '$key': bad key")
        }
        elseif ($value -isnot [string] -or (Get-ChannelForgeLogoStatus -Url $value) -ne 'Public') {
            $Map.Ignored.Add("${Section} '$key': not a public https link")
        }
        else {
            $Map[$Section][$key] = $value.Trim()
        }
    }
}

function Get-ChannelForgeLogoLookupMap {
    [CmdletBinding()]
    param([string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot))

    # logo-lookup/v1: one read per build of data\logo-lookup.json. Status is
    # None (no file), Ok or Corrupt. A missing file gives empty maps. A corrupt
    # file gives empty maps and a loud warning. A bad entry is ignored with a
    # warning. Never throws, never writes, no network.
    $map = @{
        Status    = 'None'
        ById      = [hashtable]::new([System.StringComparer]::Ordinal)
        ByName    = [hashtable]::new([System.StringComparer]::Ordinal)
        Ambiguous = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        Ignored   = [System.Collections.Generic.List[string]]::new()
    }
    $path = Join-Path (Join-Path $RepositoryRoot 'data') 'logo-lookup.json'
    if (-not [System.IO.File]::Exists($path)) { return $map }

    try {
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($path))
        $document = $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch { $document = $null }
    $valid = $document -is [pscustomobject] -and $document.Version -is [string] -and $document.Version -ceq 'logo-lookup/v1' -and
    $document.ById -is [pscustomobject] -and $document.ByName -is [pscustomobject]
    if (-not $valid) {
        $map.Status = 'Corrupt'
        Write-Warning 'Logo lookup unreadable: the file is not valid JSON, or its Version, ById or ByName is missing or wrong. No looked-up logo was applied.'
        return $map
    }

    $map.Status = 'Ok'
    Add-ChannelForgeLogoLookupEntry -Section 'ById' -Table $document.ById -Map $map
    Add-ChannelForgeLogoLookupEntry -Section 'ByName' -Table $document.ByName -Map $map
    if ($map.Ignored.Count -gt 0) {
        $shown = @($map.Ignored | Select-Object -First 5) -join '; '
        Write-Warning "Logo lookup: $($map.Ignored.Count) entries ignored ($shown)."
    }
    return $map
}
