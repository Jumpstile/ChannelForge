function Read-ChannelForgeEventChannelOverrides {
    # Returns every record in event-channels.json (none when the file is absent). event-channel/v2.
    # A damaged file makes this throw; it is never ignored here, repaired or replaced.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $fix = 'Fix or delete the file. Nothing was written.'
    try {
        $document = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -DateKind String -ErrorAction Stop
    }
    catch {
        throw "The event channel overrides file could not be read (it is not valid JSON). $fix"
    }
    if ($null -eq $document -or $document -isnot [pscustomobject] -or [string]$document.version -cne 'event-channel/v2') {
        throw "The event channel overrides file has a missing or unsupported version (expected event-channel/v2). $fix"
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($document.overrides)) {
        $names = if ($null -eq $item) { @() } else { @($item.PSObject.Properties.Name) }
        $key = if ($names -contains 'key') { [string]$item.key } else { '' }
        $decision = if ($names -contains 'decision') { [string]$item.decision } else { '' }
        if ($key -cnotmatch '^[0-9a-f]{64}$') { throw "The event channel overrides file has a record with a missing or bad key. $fix" }
        if ($decision -cnotin 'forceOn', 'forceOff') { throw "The event channel overrides file has a record with a missing or unknown decision. $fix" }
        if (-not $seen.Add($key)) { throw "The event channel overrides file has two records for one channel. $fix" }
        [void]$records.Add([pscustomobject][ordered]@{
                key       = $key
                name      = if ($names -contains 'name') { [string]$item.name } else { '' }
                decision  = $decision
                decidedAt = if ($names -contains 'decidedAt') { [string]$item.decidedAt } else { '' }
            })
    }
    return @($records.ToArray())
}
