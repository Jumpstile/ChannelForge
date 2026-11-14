function Get-ChannelForgeXguideScopedReport {
    <#
    .SYNOPSIS
    Runs the cross-guide report once per playlist, over only the guides bound to it (xguide-compare/v2).
    Without a scope it is exactly Get-ChannelForgeXguideReport.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Programme = @(),
        [Parameter(Mandatory)][datetime]$BuildTimeUtc,
        [string[]]$GuideSourceId = @(),
        [hashtable]$GuideScope,
        [int]$MaxPerKind = 5
    )

    if ($null -eq $GuideScope) {
        return Get-ChannelForgeXguideReport -Programme $Programme -BuildTimeUtc $BuildTimeUtc -GuideSourceId $GuideSourceId -MaxPerKind $MaxPerKind
    }

    $kindOrder = @('MissingChannel', 'StartShift', 'TitleDiffers', 'Unmatched', 'GuideBehind')
    $guides = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $counts = [ordered]@{}
    foreach ($k in $kindOrder) { $counts[$k] = 0 }
    $shared = 0; $agree = 0
    $found = [Collections.Generic.List[object]]::new()
    foreach ($label in @($GuideScope.Values | ForEach-Object { $_ } | Sort-Object -Unique -CaseSensitive)) {
        $ids = [string[]]@($GuideScope.Keys | Where-Object { $GuideScope[$_] -ccontains $label } | Sort-Object -CaseSensitive)
        $report = Get-ChannelForgeXguideReport -Programme @($Programme | Where-Object { [string]$_.SourceId -cin $ids }) -BuildTimeUtc $BuildTimeUtc -GuideSourceId $ids -MaxPerKind $MaxPerKind
        if ($report.SharedChannelCount -eq 0) { continue }
        foreach ($g in $report.Guides) { $guides[[string]$g.SourceId] = $g }
        foreach ($k in $kindOrder) { $counts[$k] += $report.Counts.$k }
        $shared += $report.SharedChannelCount; $agree += $report.AgreeCount
        foreach ($f in $report.Findings) { $f.Message = '{0} (playlist {1})' -f $f.Message, $label; $found.Add($f) }
    }

    $seen = @{}
    $kept = foreach ($f in @($found | Sort-Object { $kindOrder.IndexOf($_.Kind) }, ChannelId, Start, { $_.SourceIds -join '|' })) {
        $seen[$f.Kind] = 1 + [int]$seen[$f.Kind]
        if ($seen[$f.Kind] -le $MaxPerKind) { $f }
    }
    return [pscustomobject][ordered]@{
        Contract = 'xguide-compare/v2'
        Guides = @($guides.Keys | Sort-Object -CaseSensitive | ForEach-Object { $guides[$_] })
        SharedChannelCount = $shared
        AgreeCount = $agree
        Counts = [pscustomobject]$counts
        Findings = @($kept)
        Truncated = (@($counts.Values | Where-Object { $_ -gt $MaxPerKind }).Count -gt 0)
    }
}
