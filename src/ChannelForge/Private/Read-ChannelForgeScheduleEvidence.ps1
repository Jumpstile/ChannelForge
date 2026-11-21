function Read-ChannelForgeScheduleEvidence {
    # Schedule evidence: plain facts saved in a JSON file, { "records": [ { id, kind, name, sport, home, away, date,
    # startUtc (or null), source, seen } ] }. Facts only; no network. A missing file is no evidence. Records
    # are used whatever their source is, so a removed source's saved copy still counts. A record whose date
    # is not yyyy-MM-dd can never match a day, so it is skipped. Records can be added with
    # Import-ChannelForgeScheduleEvidence. Returns objects.
    # kind is game | session | race | card | episode | special; old input without kind is a game. A game needs
    # sport, home, away and date (name defaults to "away at home"); any other kind needs name and date.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $kinds = @('game', 'session', 'race', 'card', 'episode', 'special')
    $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($record in @($data.records)) {
        $kind = if ($record.kind) { ([string]$record.kind).ToLowerInvariant() } else { 'game' }
        if ($kind -notin $kinds -or -not $record.date) { continue }
        if ($kind -eq 'game') {
            if (-not ($record.sport -and $record.home -and $record.away)) { continue }
        } elseif (-not $record.name) { continue }
        $day = if ($record.date -is [datetime]) { $record.date.ToString('yyyy-MM-dd') } else { [string]$record.date }
        if ($day -cnotmatch '^\d{4}-\d{2}-\d{2}$') { continue }
        $name = if ($record.name) { [string]$record.name } else { "$($record.away) at $($record.home)" }
        $text = { param($Value) if ($Value -is [datetime]) { $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture) } elseif ([string]::IsNullOrWhiteSpace([string]$Value)) { $null } else { [string]$Value } }
        [pscustomobject]@{
            Id = [string]$record.id; Kind = $kind; Name = $name; Sport = [string]$record.sport; Home = [string]$record.home; Away = [string]$record.away
            Date = $day; StartUtc = $record.startUtc; Source = [string]$record.source; Seen = $record.seen
            Time = (& $text $record.time); Venue = (& $text $record.venue); City = (& $text $record.city)
            License = (& $text $record.license); Attribution = (& $text $record.attribution); FetchedAt = (& $text $record.fetchedAt); Revision = (& $text $record.revision)
        }
    }
}
