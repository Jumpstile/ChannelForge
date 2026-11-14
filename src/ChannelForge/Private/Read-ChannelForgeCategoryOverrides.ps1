function Read-ChannelForgeCategoryOverrides {
    # Returns every record in category-overrides.json (none when the file is absent).
    # A damaged file stops the run; it is never ignored, repaired or replaced.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $fix = 'Fix or delete the file. Nothing was written.'
    try {
        $document = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -DateKind String -ErrorAction Stop
    }
    catch {
        throw "The category overrides file could not be read (it is not valid JSON). $fix"
    }
    if ($null -eq $document -or $document -isnot [pscustomobject] -or [string]$document.version -cne 'category-quality/v1') {
        throw "The category overrides file has a missing or unsupported version (expected category-quality/v1). $fix"
    }

    $allowed = @(Get-ChannelForgeOneGuideCategoryRegistry | Where-Object { $_.Group -ne 'temporal' } | ForEach-Object { $_.Key })
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($document.overrides)) {
        $names = if ($null -eq $item) { @() } else { @($item.PSObject.Properties.Name) }
        $key = if ($names -contains 'key') { [string]$item.key } else { '' }
        $category = if ($names -contains 'category') { [string]$item.category } else { '' }
        if ($key -cnotmatch '^[0-9a-f]{64}$') { throw "The category overrides file has a record with a missing or bad key. $fix" }
        if ($allowed -cnotcontains $category) { throw "The category overrides file has a record with a missing or unknown category. $fix" }
        if (-not $seen.Add($key)) { throw "The category overrides file has two records for one channel. $fix" }
        [void]$records.Add([pscustomobject][ordered]@{
                key       = $key
                name      = if ($names -contains 'name') { [string]$item.name } else { '' }
                category  = $category
                decidedAt = if ($names -contains 'decidedAt') { [string]$item.decidedAt } else { '' }
            })
    }
    return @($records.ToArray())
}
