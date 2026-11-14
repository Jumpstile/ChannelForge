function Get-ChannelForgeGuideWindow {
    # Earliest start and latest stop (UTC) of the programs in an XMLTV text.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $stamp = [regex]::Matches($Text, '<programme start="(\d{14}) \+0000" stop="(\d{14}) \+0000"')
    if ($stamp.Count -eq 0) { throw 'The guide has no programs, so a name-only guide cannot be built for it.' }
    $first = ($stamp | ForEach-Object { $_.Groups[1].Value } | Sort-Object | Select-Object -First 1)
    $last = ($stamp | ForEach-Object { $_.Groups[2].Value } | Sort-Object | Select-Object -Last 1)
    $format = 'yyyyMMddHHmmss'
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    [pscustomobject]@{
        Start = [datetime]::SpecifyKind([datetime]::ParseExact($first, $format, $culture), [System.DateTimeKind]::Utc)
        End   = [datetime]::SpecifyKind([datetime]::ParseExact($last, $format, $culture), [System.DateTimeKind]::Utc)
    }
}
