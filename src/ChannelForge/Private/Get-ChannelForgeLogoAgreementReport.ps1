function Get-ChannelForgeLogoAgreementReport {
    [CmdletBinding()]
    param(
        # Playlist channels (TvgId, DisplayName, Logo = the published tvg-logo).
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Channel = @(),

        # XMLTV channel id -> icon link, for example Get-ChannelForgeGuideIconMap.
        [hashtable]$IconByChannelId = @{},

        [int]$MaxNames = 20
    )

    # Report only (issue #41): for each playlist channel, does the playlist
    # tvg-logo agree with the guide icon for the exact same channel id?
    # Links are compared but never printed; only counts and channel names.
    $report = [ordered]@{
        Agree        = 0
        Differ       = 0
        PlaylistOnly = 0
        GuideOnly    = 0
        Neither      = 0
        NoId         = 0
        DifferNames  = @()
        DifferNotShown = 0
        Warning      = $null
    }
    $differ = [System.Collections.Generic.List[string]]::new()
    $icons = [hashtable]::new([System.StringComparer]::Ordinal)
    foreach ($key in $IconByChannelId.Keys) { $icons[[string]$key] = $IconByChannelId[$key] }
    foreach ($ch in @($Channel | Where-Object { $null -ne $_ })) {
        $id = [string]$ch.TvgId
        if ($id.Length -eq 0) { $report.NoId++; continue }
        $logo = ([string]$ch.Logo).Trim()
        $icon = if ($icons.ContainsKey($id)) { ([string]$icons[$id]).Trim() } else { '' }
        if ($logo.Length -gt 0 -and $icon.Length -gt 0) {
            if ($logo -ceq $icon) { $report.Agree++ }
            else { $report.Differ++; $differ.Add([string]$ch.DisplayName) }
        }
        elseif ($logo.Length -gt 0) { $report.PlaylistOnly++ }
        elseif ($icon.Length -gt 0) { $report.GuideOnly++ }
        else { $report.Neither++ }
    }
    $report.DifferNames = @($differ | Select-Object -First $MaxNames)
    $report.DifferNotShown = [Math]::Max(0, $differ.Count - $MaxNames)
    $problems = $report.Differ + $report.PlaylistOnly + $report.GuideOnly
    if ($problems -gt 0) {
        $report.Warning = "Logo agreement: $($report.Agree) match, $($report.Differ) differ, $($report.PlaylistOnly) only in the playlist, $($report.GuideOnly) only in the guide."
        if ($differ.Count -gt 0) {
            $more = if ($report.DifferNotShown -gt 0) { " +$($report.DifferNotShown) more" } else { '' }
            $report.Warning += " Differ: $($report.DifferNames -join ', ')$more."
        }
    }
    return [pscustomobject]$report
}
