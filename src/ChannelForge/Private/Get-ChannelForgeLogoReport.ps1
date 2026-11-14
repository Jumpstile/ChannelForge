function Get-ChannelForgeLogoReport {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Channel = @(),

        [int]$MaxNames = 20,

        # TvgId -> link map the build used, and the Read-ChannelForgeLogoPin
        # result it came from (gives Status and Problems). Both optional.
        [hashtable]$LogoPin = @{},

        [AllowNull()]
        [object]$PinRead = $null
    )

    # Report only (issue #191): counts logo status per channel and lists
    # names for the non-public ones. Never changes a channel or its logo.
    $report = [ordered]@{
        Public         = 0
        Replaced       = 0
        Empty          = 0
        NotHttps       = 0
        PrivateAddress = 0
        Names          = [ordered]@{ Empty = @(); NotHttps = @(); PrivateAddress = @() }
        NamesNotShown  = [ordered]@{ Empty = 0; NotHttps = 0; PrivateAddress = 0 }
        Pinned         = 0
        PinsStatus     = if ($PinRead) { [string]$PinRead.Status } elseif ($LogoPin.Count -gt 0) { 'Ok' } else { 'Missing' }
        PinsIgnored    = @(if ($PinRead -and $PinRead.Status -eq 'Corrupt') { $PinRead.Problems })
        PinsUnused     = @()
        Warning        = $null
    }
    $all = @{ Empty = @(); NotHttps = @(); PrivateAddress = @() }
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($ch in @($Channel | Where-Object { $null -ne $_ })) {
        $status = Get-ChannelForgeLogoStatus -Url ([string]$ch.Logo)
        $report[$status]++
        if ($ch.PSObject.Properties['Replaced'] -and $ch.Replaced) { $report.Replaced++ }
        if ($ch.PSObject.Properties['Pinned'] -and $ch.Pinned) { $report.Pinned++ }
        if ($ch.PSObject.Properties['TvgId']) { [void]$seenIds.Add([string]$ch.TvgId) }
        if ($status -ne 'Public') { $all[$status] += [string]$ch.DisplayName }
    }
    foreach ($status in $all.Keys) {
        $report.Names[$status] = @($all[$status] | Select-Object -First $MaxNames)
        $report.NamesNotShown[$status] = [Math]::Max(0, $all[$status].Count - $MaxNames)
    }
    $report.PinsUnused = @($LogoPin.Keys | Where-Object { -not $seenIds.Contains([string]$_) } | Sort-Object { [string]$_ } -CaseSensitive)
    $notPublic = $report.Empty + $report.NotHttps + $report.PrivateAddress
    if ($notPublic -gt 0) {
        $report.Warning = "Logo check: $notPublic of $($report.Public + $notPublic) channels have no public https logo (empty $($report.Empty), not https $($report.NotHttps), private address $($report.PrivateAddress))."
        foreach ($status in $all.Keys | Sort-Object) {
            if ($all[$status].Count -eq 0) { continue }
            $more = if ($report.NamesNotShown[$status] -gt 0) { " +$($report.NamesNotShown[$status]) more" } else { '' }
            $report.Warning += " ${status}: $($report.Names[$status] -join ', ')$more."
        }
        $report.Warning += ' Pin one with Set-ChannelForgeLogoPin.'
    }
    if ($report.Replaced -gt 0) {
        $report.Warning = ("Logo default: $($report.Replaced) channels use their group default logo. " + $report.Warning).Trim()
    }
    $pinText = @()
    if ($report.Pinned -gt 0) { $pinText += "$($report.Pinned) applied" }
    if ($report.PinsUnused.Count -gt 0) { $pinText += "$($report.PinsUnused.Count) unused ($($report.PinsUnused -join ', '))" }
    if ($report.PinsStatus -eq 'Corrupt') { $pinText += "file unreadable, none applied ($($report.PinsIgnored -join '; '))" }
    if ($pinText.Count -gt 0) {
        $report.Warning = ("$($report.Warning) Logo pins: $($pinText -join ', ').").Trim()
    }
    return [pscustomobject]$report
}
