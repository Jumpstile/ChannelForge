function Import-ChannelForgeScheduleEvidence {
    # Adds user-supplied schedule facts to the schedule evidence file (state\schedule-evidence.json). The
    # user gives a CSV with the columns sport, home, away, date (yyyy-MM-dd) and optional startUtc. Facts
    # only; no network. A row that is incomplete or has a bad date or time is rejected with a plain
    # message and never written. A game already saved (same sport, teams and date) is replaced by the new
    # row. Saved records the importer did not touch are kept as they are. A damaged evidence file stops
    # the import and is never overwritten. Returns Added, Updated and Rejected (strings).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$EvidencePath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "The schedule file '$SourcePath' was not found." }
    $existing = @()
    if (Test-Path -LiteralPath $EvidencePath -PathType Leaf) {
        try { $existing = @((Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json -DateKind String -ErrorAction Stop).records) }
        catch { throw "The schedule evidence file '$EvidencePath' is damaged. Fix or delete it, then import again." }
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $seen = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $invariant)
    $rejected = [System.Collections.Generic.List[string]]::new()
    $fresh = [ordered]@{}
    $row = 1
    foreach ($line in @(Import-Csv -LiteralPath $SourcePath)) {
        $row++
        $sport = ([string]$line.sport).Trim(); $homeTeam = ([string]$line.home).Trim(); $away = ([string]$line.away).Trim()
        $day = [datetime]::MinValue
        if (-not ($sport -and $homeTeam -and $away)) { [void]$rejected.Add("Row ${row}: sport, home and away are all needed."); continue }
        if (-not [datetime]::TryParseExact(([string]$line.date).Trim(), 'yyyy-MM-dd', $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$day)) { [void]$rejected.Add("Row ${row}: the date must look like 2026-11-15."); continue }
        $start = $null
        $startText = ([string]$line.startUtc).Trim()
        if ($startText) {
            $parsed = [datetimeoffset]::MinValue
            if (-not [datetimeoffset]::TryParse($startText, $invariant, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { [void]$rejected.Add("Row ${row}: the start time is not a time."); continue }
            $start = $parsed.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $invariant)
        }
        $dayText = $day.ToString('yyyy-MM-dd', $invariant)
        $idBytes = [System.Text.Encoding]::UTF8.GetBytes(("$sport|$homeTeam|$away|$dayText").ToLowerInvariant())
        $id = 'user-' + ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($idBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 16))
        $fresh[$id] = [ordered]@{ id = $id; sport = $sport; home = $homeTeam; away = $away; date = $dayText; startUtc = $start; source = 'user-file'; seen = $seen }
    }
    if ($fresh.Count -eq 0) { return [pscustomobject]@{ Added = 0; Updated = 0; Rejected = @($rejected.ToArray()) } }

    $kept = @($existing | Where-Object { $_ -and -not $fresh.Contains([string]$_.id) })
    $updated = @($existing | Where-Object { $_ }).Count - $kept.Count
    $records = @($kept) + @($fresh.Values)
    $parent = Split-Path -Parent ([System.IO.Path]::GetFullPath($EvidencePath))
    [void](New-Item -ItemType Directory -Path $parent -Force)
    $temporary = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($EvidencePath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporary, (@{ records = $records } | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($temporary, $EvidencePath, $true)
    }
    finally {
        if ([System.IO.File]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    [pscustomobject]@{ Added = $fresh.Count - $updated; Updated = $updated; Rejected = @($rejected.ToArray()) }
}
