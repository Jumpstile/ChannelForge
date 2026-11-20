function Read-ChannelForgeScheduleAnswers {
    # Returns every saved schedule answer (none when the file is absent). A damaged file throws.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $fix = 'Fix or delete the file.'
    try {
        $document = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -DateKind String -ErrorAction Stop
    }
    catch {
        throw "The schedule answers file could not be read (it is not valid JSON). $fix"
    }
    if ($null -eq $document -or $document -isnot [pscustomobject] -or [string]$document.version -cne 'schedule-answer/v1') {
        throw "The schedule answers file has a missing or unsupported version (expected schedule-answer/v1). $fix"
    }
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($document.answers)) {
        $names = if ($null -eq $item) { @() } else { @($item.PSObject.Properties.Name) }
        $key = if ($names -contains 'key') { [string]$item.key } else { '' }
        $answer = if ($names -contains 'answer') { [string]$item.answer } else { '' }
        if ($key -cnotmatch '^[^|\r\n]{1,200}\|(NoEvidence|GuideMissing|Review)$') { throw "The schedule answers file has a record with a missing or bad key. $fix" }
        if (@('StillOn', 'Cancelled', 'NotSure') -cnotcontains $answer) { throw "The schedule answers file has a record with a missing or unknown answer. $fix" }
        [void]$records.Add([pscustomobject][ordered]@{
                key        = $key
                answer     = $answer
                answeredAt = if ($names -contains 'answeredAt') { [string]$item.answeredAt } else { '' }
            })
    }
    return @($records.ToArray())
}
