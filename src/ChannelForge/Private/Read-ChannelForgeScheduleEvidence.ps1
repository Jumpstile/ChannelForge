function Read-ChannelForgeScheduleEvidence {
    # Schedule evidence: plain facts saved in a JSON file, { "records": [ { id, sport, home, away, date,
    # startUtc (or null), source, seen } ] }. Facts only; no network. A missing file is no evidence. Records
    # are used whatever their source is, so a removed source's saved copy still counts. A record whose date
    # is not yyyy-MM-dd can never match a day, so it is skipped. Records can be added with
    # Import-ChannelForgeScheduleEvidence. Returns objects.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($record in @($data.records)) {
        if (-not ($record.sport -and $record.home -and $record.away -and $record.date)) { continue }
        $day = if ($record.date -is [datetime]) { $record.date.ToString('yyyy-MM-dd') } else { [string]$record.date }
        if ($day -cnotmatch '^\d{4}-\d{2}-\d{2}$') { continue }
        [pscustomobject]@{
            Id = [string]$record.id; Sport = [string]$record.sport; Home = [string]$record.home; Away = [string]$record.away
            Date = $day; StartUtc = $record.startUtc; Source = [string]$record.source; Seen = $record.seen
        }
    }
}
