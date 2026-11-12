function Read-ChannelForgeChannelDecisions {
    # Returns every record in channel-decisions.json (none when the file is absent).
    # A damaged file stops the run; it is never ignored and never replaced by defaults.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $fix = 'Fix or delete the file, then run again. Nothing was published.'
    try {
        $items = @([System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw "The channel decisions file could not be read (it is not valid JSON). $fix"
    }

    $choices = @('KeepWithoutGuide', 'OwnPlaceholder', 'BindTrueMatch', 'ShareOnPurpose')
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $items) {
        $names = if ($null -eq $item) { @() } else { @($item.PSObject.Properties.Name) }
        $key = if ($names -contains 'key') { [string]$item.key } else { '' }
        $choice = if ($names -contains 'choice') { [string]$item.choice } else { '' }
        $guideId = if ($names -contains 'guideId' -and $null -ne $item.guideId) { [string]$item.guideId } else { $null }
        if ($key -cnotmatch '^[0-9a-f]{64}$' -or $choices -cnotcontains $choice) {
            throw "The channel decisions file has a record with a missing or unknown key or choice. $fix"
        }
        if (-not $seen.Add($key)) { throw "The channel decisions file has two records for one channel. $fix" }
        if ($choice -in @('BindTrueMatch', 'ShareOnPurpose') -and [string]::IsNullOrWhiteSpace($guideId)) {
            throw "The channel decisions file has a $choice record with no guideId. $fix"
        }
        if ($null -ne $guideId -and $guideId -match '["\x00-\x1f]') { throw "The channel decisions file has a guideId with a quote or control character. $fix" }
        [void]$records.Add([pscustomobject][ordered]@{
                key       = $key
                name      = if ($names -contains 'name') { [string]$item.name } else { '' }
                choice    = $choice
                guideId   = $guideId
                decidedAt = if ($names -contains 'decidedAt') { [string]$item.decidedAt } else { '' }
            })
    }
    return @($records.ToArray())
}
