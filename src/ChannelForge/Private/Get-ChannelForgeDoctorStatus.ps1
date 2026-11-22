function Get-ChannelForgeDoctorStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $notRun = [ordered]@{ Overall = 'NotRun'; Pass = 0; Warn = 0; Fail = 0; Unknown = 0; Summary = 'Doctor has not run yet'; CheckedUtc = $null }
    $path = Join-Path (Join-Path $RepositoryRoot 'state') 'doctor-result.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $notRun }
    try {
        $saved = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $counts = foreach ($name in 'Pass', 'Warn', 'Fail', 'Unknown') { [int]$saved.$name }
        if ([string]$saved.Overall -notin @('Pass', 'Warn', 'Fail', 'Unknown') -or @($counts | Where-Object { $_ -lt 0 }).Count -gt 0) { throw 'invalid' }
        return [ordered]@{
            Overall    = [string]$saved.Overall
            Pass       = $counts[0]
            Warn       = $counts[1]
            Fail       = $counts[2]
            Unknown    = $counts[3]
            Summary    = ('{0}: {1} passed, {2} warnings, {3} failed, {4} unknown' -f ([string]$saved.Overall).ToUpperInvariant(), $counts[0], $counts[1], $counts[2], $counts[3])
            CheckedUtc = [string]$saved.CheckedUtc
        }
    }
    catch {
        $notRun.Overall = 'Unknown'
        $notRun.Summary = 'The saved Doctor result could not be read; run Doctor again'
        return $notRun
    }
}
