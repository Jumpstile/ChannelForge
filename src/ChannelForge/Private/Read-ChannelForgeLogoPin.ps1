function Get-ChannelForgeLogoPinEntryProblem {
    [CmdletBinding()]
    param([AllowNull()]$Entry)

    # One job: plain reason a stored pin entry is bad, or $null. Never echoes the link.
    if ($null -eq $Entry -or $Entry -isnot [pscustomobject]) { return 'an entry is not an object' }
    $tvgId = $Entry.TvgId
    if ($tvgId -isnot [string] -or $tvgId.Length -lt 1 -or $tvgId.Length -gt 256 -or $tvgId -match '[\x00-\x1f\x7f]') {
        return 'an entry has a bad TvgId'
    }
    $problem = Get-ChannelForgeLogoPinLinkProblem -Logo $(if ($Entry.Logo -is [string]) { $Entry.Logo } else { '' })
    if ($problem) { return "entry '$tvgId': $problem" }
    if ($Entry.Source -isnot [string] -or $Entry.Source -cne 'user') { return "entry '$tvgId': Source must be user" }
    if ($Entry.PinnedAtUtc -isnot [string] -and $Entry.PinnedAtUtc -isnot [datetime]) { return "entry '$tvgId': PinnedAtUtc is missing" }
    if ($null -ne $Entry.Note -and ($Entry.Note -isnot [string] -or $Entry.Note.Length -gt 200)) { return "entry '$tvgId': Note is not text up to 200 characters" }
    return $null
}

function Read-ChannelForgeLogoPin {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    # Reads state\logo-pins.json (logo-identity/v1). Never writes, never throws
    # for a bad file. Status is Missing, Ok or Corrupt.
    $path = Join-Path (Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot).StateRoot 'logo-pins.json'
    $result = { param($status, $pins, $problems) [pscustomobject][ordered]@{ Status = $status; Pins = @($pins); Problems = @($problems); Path = $path } }

    if (-not [System.IO.File]::Exists($path)) { return & $result 'Missing' @() @() }

    try {
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($path))
        $document = $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return & $result 'Corrupt' @() @('the file is not valid JSON text')
    }
    if ($document -isnot [pscustomobject] -or $document.Version -isnot [string] -or $document.Version -cne 'logo-identity/v1') {
        return & $result 'Corrupt' @() @('the file Version is missing or not logo-identity/v1')
    }

    $pins = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @($document.Pins)) {
        $problem = Get-ChannelForgeLogoPinEntryProblem -Entry $entry
        if (-not $problem -and -not $seen.Add([string]$entry.TvgId)) { $problem = "entry '$($entry.TvgId)' appears more than once" }
        if ($problem) { return & $result 'Corrupt' @() @($problem) }
        $stamp = if ($entry.PinnedAtUtc -is [datetime]) { $entry.PinnedAtUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $entry.PinnedAtUtc }
        $pins.Add([pscustomobject][ordered]@{ TvgId = $entry.TvgId; Logo = $entry.Logo; Source = 'user'; PinnedAtUtc = $stamp; Note = [string]$entry.Note })
    }
    return & $result 'Ok' $pins @()
}
