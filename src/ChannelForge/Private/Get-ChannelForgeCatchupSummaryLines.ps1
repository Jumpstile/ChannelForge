function Get-ChannelForgeCatchupSummaryLines {
    <#
    .SYNOPSIS
    Turns catch-up report rows into the few lines shown in the build summary. Report only.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Row = @(),
        [int]$RemoteSourceCount = 0
    )

    $declared = @($Row | Where-Object { $_.Shape -ne 'none' })
    $lines = @('', '## Catch-up')
    $lines += "Catch-up (report only, nothing is written to the playlist): $($declared.Count) of $($Row.Count) streams say they support it."
    if ($declared.Count -gt 0) {
        $shapes = @('path-template', 'query-template', 'declared-only' | ForEach-Object {
                $shape = $_
                $count = @($declared | Where-Object { $_.Shape -ceq $shape }).Count
                if ($count -gt 0) { "$shape $count" }
            })
        $lines += "Kinds: $($shapes -join ', ')."
        $days = @($declared | Where-Object { $null -ne $_.DeclaredDays } | ForEach-Object { [int]$_.DeclaredDays })
        if ($days.Count -gt 0) { $lines += "Most archive days a stream declares: $(($days | Measure-Object -Maximum).Maximum)." }
        $lines += 'These are claims from the provider playlist. Old programs in a guide do not prove that catch-up plays.'
    }
    if ($RemoteSourceCount -gt 0) {
        $lines += "Not checked: $RemoteSourceCount remote playlist source(s). Only local playlist files are read for catch-up."
    }
    return $lines
}
