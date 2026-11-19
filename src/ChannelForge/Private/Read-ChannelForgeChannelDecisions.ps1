function Read-ChannelForgeChannelDecisions {
    # Returns the records of one section of channel-decisions.json (none when the file is absent).
    # GuideChoices (the default) is the stream-keyed guide choices. ChannelNumbers is the user's
    # saved channel numbers, which exist only in a v2 file.
    # The file is either v1 (a bare array of guide choices) or v2 (an object with schemaVersion
    # 'channel-decisions/v2'). A damaged file or an unknown version stops the run; it is never
    # ignored and never replaced by defaults.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('GuideChoices', 'ChannelNumbers')][string]$Section = 'GuideChoices'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $fix = 'Fix or delete the file, then run again. Nothing was published.'
    try {
        $items = @([System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw "The channel decisions file could not be read (it is not valid JSON). $fix"
    }

    $numbers = @()
    if ($items.Count -eq 1 -and $null -ne $items[0] -and $items[0] -is [pscustomobject] -and @($items[0].PSObject.Properties.Name) -contains 'schemaVersion') {
        $document = $items[0]
        if ([string]$document.schemaVersion -cne 'channel-decisions/v2') {
            throw "The channel decisions file has an unknown version '$([string]$document.schemaVersion)'. This build reads channel-decisions/v2 and the older plain list. $fix"
        }
        $names = @($document.PSObject.Properties.Name)
        $items = if ($names -contains 'guideChoices') { @($document.guideChoices) } else { @() }
        $numbers = if ($names -contains 'channelNumbers') { @($document.channelNumbers) } else { @() }
    }
    if ($Section -eq 'ChannelNumbers') { return @(ConvertTo-ChannelForgeChannelNumberRecord -Item $numbers) }

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
