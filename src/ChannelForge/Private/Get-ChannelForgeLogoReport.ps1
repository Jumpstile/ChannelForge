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
        [object]$PinRead = $null,

        # Get-ChannelForgeLogoLookupMap result (Status, Ignored). Optional.
        [hashtable]$LogoLookup = @{}
    )

    # Report only (issue #191): counts logo status per channel and lists
    # names for the non-public ones. Never changes a channel or its logo.
    $report = [ordered]@{
        Public         = 0
        Replaced       = 0
        Empty          = 0
        NotHttps       = 0
        PrivateAddress = 0
        DataUri        = 0
        TooLong        = 0
        BadCharacters  = 0
        Names          = [ordered]@{ Empty = @(); NotHttps = @(); PrivateAddress = @(); DataUri = @(); TooLong = @(); BadCharacters = @() }
        NamesNotShown  = [ordered]@{ Empty = 0; NotHttps = 0; PrivateAddress = 0; DataUri = 0; TooLong = 0; BadCharacters = 0 }
        Pinned         = 0
        PinsStatus     = if ($PinRead) { [string]$PinRead.Status } elseif ($LogoPin.Count -gt 0) { 'Ok' } else { 'Missing' }
        PinsIgnored    = @(if ($PinRead -and $PinRead.Status -eq 'Corrupt') { $PinRead.Problems })
        PinsUnused     = @()
        Warning        = $null
        LookedUp       = 0
        LookupStatus   = if ($LogoLookup.Status) { [string]$LogoLookup.Status } else { 'None' }
        LookupIgnored  = @($LogoLookup.Ignored | Where-Object { $null -ne $_ })
        LookupAmbiguous = @()
        LookupAmbiguousNotShown = 0
    }
    $ambiguousNames = [System.Collections.Generic.List[string]]::new()
    $all = @{ Empty = @(); NotHttps = @(); PrivateAddress = @(); DataUri = @(); TooLong = @(); BadCharacters = @() }
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($ch in @($Channel | Where-Object { $null -ne $_ })) {
        $status = Get-ChannelForgeLogoStatus -Url ([string]$ch.Logo)
        $report[$status]++
        if ($ch.PSObject.Properties['Replaced'] -and $ch.Replaced) { $report.Replaced++ }
        if ($ch.PSObject.Properties['Pinned'] -and $ch.Pinned) { $report.Pinned++ }
        if ($ch.PSObject.Properties['LookedUp'] -and $ch.LookedUp) { $report.LookedUp++ }
        if ($ch.PSObject.Properties['LookupAmbiguous'] -and $ch.LookupAmbiguous -and -not $ambiguousNames.Contains([string]$ch.DisplayName)) { $ambiguousNames.Add([string]$ch.DisplayName) }
        if ($ch.PSObject.Properties['TvgId']) { [void]$seenIds.Add([string]$ch.TvgId) }
        if ($status -ne 'Public') { $all[$status] += [string]$ch.DisplayName }
    }
    foreach ($status in $all.Keys) {
        $report.Names[$status] = @($all[$status] | Select-Object -First $MaxNames)
        $report.NamesNotShown[$status] = [Math]::Max(0, $all[$status].Count - $MaxNames)
    }
    $report.PinsUnused = @($LogoPin.Keys | Where-Object { -not $seenIds.Contains([string]$_) } | Sort-Object { [string]$_ } -CaseSensitive)
    $notPublic = $report.Empty + $report.NotHttps + $report.PrivateAddress + $report.DataUri + $report.TooLong + $report.BadCharacters
    if ($notPublic -gt 0) {
        $unsafe = @(foreach ($pair in @(@('DataUri', 'data link'), @('TooLong', 'too long'), @('BadCharacters', 'bad characters'))) { if ($report[$pair[0]] -gt 0) { ", $($pair[1]) $($report[$pair[0]])" } }) -join ''
        $report.Warning = "Logo check: $notPublic of $($report.Public + $notPublic) channels have no public https logo (empty $($report.Empty), not https $($report.NotHttps), private address $($report.PrivateAddress)$unsafe)."
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
    $report.LookupAmbiguous = @($ambiguousNames | Select-Object -First $MaxNames)
    $report.LookupAmbiguousNotShown = [Math]::Max(0, $ambiguousNames.Count - $MaxNames)
    $lookupText = @()
    if ($report.LookedUp -gt 0) { $lookupText += "$($report.LookedUp) $(if ($report.LookedUp -eq 1) { 'channel' } else { 'channels' }) got a looked-up logo" }
    if ($ambiguousNames.Count -gt 0) {
        $more = if ($report.LookupAmbiguousNotShown -gt 0) { " +$($report.LookupAmbiguousNotShown) more" } else { '' }
        $lookupText += "$($ambiguousNames.Count) ambiguous ($($report.LookupAmbiguous -join ', ')$more)"
    }
    if ($report.LookupStatus -eq 'Corrupt') { $lookupText += 'file unreadable, none applied' }
    if ($report.LookupIgnored.Count -gt 0) { $lookupText += "$($report.LookupIgnored.Count) $(if ($report.LookupIgnored.Count -eq 1) { 'entry' } else { 'entries' }) ignored" }
    if ($lookupText.Count -gt 0) {
        $report.Warning = ("$($report.Warning) Logo lookup: $($lookupText -join ', ').").Trim()
    }
    return [pscustomobject]$report
}
