function ConvertTo-ChannelForgeChannelNumberRecord {
    # Validates the channelNumbers section of channel-decisions.json and returns clean records.
    # A number must be a whole number from 1 to 9999. Two records for one channel stop the run.
    # Two records with the same number are allowed here: that is a review item, not a damaged file.
    [CmdletBinding()]
    param([AllowEmptyCollection()][AllowNull()][object[]]$Item = @())

    $fix = 'Fix or delete the file, then run again. Nothing was published.'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Item)) {
        $names = if ($null -eq $entry) { @() } else { @($entry.PSObject.Properties.Name) }
        $key = if ($names -contains 'channelKey') { [string]$entry.channelKey } else { '' }
        if ([string]::IsNullOrWhiteSpace($key)) { throw "The channel decisions file has a channel number record with no channelKey. $fix" }
        $number = if ($names -contains 'number') { $entry.number } else { $null }
        if (-not (Test-ChannelForgeChannelNumberValue -Value $number)) {
            throw "The channel decisions file has a channel number for '$key' that is not a whole number from 1 to 9999. $fix"
        }
        if (-not $seen.Add($key)) { throw "The channel decisions file has two channel number records for '$key'. $fix" }
        [void]$records.Add([pscustomobject][ordered]@{
                channelKey = $key
                name       = if ($names -contains 'name') { [string]$entry.name } else { '' }
                number     = [int]$number
                decidedAt  = if ($names -contains 'decidedAt') { [string]$entry.decidedAt } else { '' }
            })
    }
    return @($records.ToArray())
}
