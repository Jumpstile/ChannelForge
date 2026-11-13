function Get-ChannelForgeLogoReport {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Channel = @(),

        [int]$MaxNames = 20
    )

    # Report only (issue #191): counts logo status per channel and lists
    # names for the non-public ones. Never changes a channel or its logo.
    $report = [ordered]@{
        Public         = 0
        Empty          = 0
        NotHttps       = 0
        PrivateAddress = 0
        Names          = [ordered]@{ Empty = @(); NotHttps = @(); PrivateAddress = @() }
        NamesNotShown  = [ordered]@{ Empty = 0; NotHttps = 0; PrivateAddress = 0 }
        Warning        = $null
    }
    $all = @{ Empty = @(); NotHttps = @(); PrivateAddress = @() }
    foreach ($ch in @($Channel | Where-Object { $null -ne $_ })) {
        $status = Get-ChannelForgeLogoStatus -Url ([string]$ch.Logo)
        $report[$status]++
        if ($status -ne 'Public') { $all[$status] += [string]$ch.DisplayName }
    }
    foreach ($status in $all.Keys) {
        $report.Names[$status] = @($all[$status] | Select-Object -First $MaxNames)
        $report.NamesNotShown[$status] = [Math]::Max(0, $all[$status].Count - $MaxNames)
    }
    $notPublic = $report.Empty + $report.NotHttps + $report.PrivateAddress
    if ($notPublic -gt 0) {
        $report.Warning = "Logo check: $notPublic of $($report.Public + $notPublic) channels have no public https logo (empty $($report.Empty), not https $($report.NotHttps), private address $($report.PrivateAddress))."
        foreach ($status in $all.Keys | Sort-Object) {
            if ($all[$status].Count -eq 0) { continue }
            $more = if ($report.NamesNotShown[$status] -gt 0) { " +$($report.NamesNotShown[$status]) more" } else { '' }
            $report.Warning += " ${status}: $($report.Names[$status] -join ', ')$more."
        }
    }
    return [pscustomobject]$report
}
