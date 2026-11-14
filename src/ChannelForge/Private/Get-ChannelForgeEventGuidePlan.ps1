function Get-ChannelForgeEventGuidePlan {
    # event-channel/v2, slice 3: the automatic apply rule. Only channels the detector rates high get an
    # event guide, built from their own provider guide programs. Everything else keeps its normal guide.
    # Entry: EntryId, Key, Name, GuideId (provider guide id, may be empty). ExcludedKey: channels with a
    # saved user choice, which wins. Returns Channel (for Add-ChannelForgePlaceholderGuide: Id, Name,
    # Blocks, plus Key and EntryIds), Applied and Fallback rows (Key, Name, Reason). Pure; no channel dropped.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$XmltvBytes,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entry,
        [AllowEmptyCollection()][string[]]$ExcludedKey = @()
    )

    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($XmltvBytes)
    $window = Get-ChannelForgeGuideWindow -Text $text
    $programmes = Read-ChannelForgeEventGuideProgramme -Text $text -GuideId @($Entry | ForEach-Object { [string]$_.GuideId } | Where-Object { $_ })
    $byKey = [ordered]@{}
    foreach ($item in $Entry) { if (-not $byKey.Contains([string]$item.Key)) { $byKey[[string]$item.Key] = [System.Collections.Generic.List[object]]::new() }; $byKey[[string]$item.Key].Add($item) }

    $detectorInput = foreach ($group in $byKey.Values) {
        $rows = if ($group[0].GuideId -and $programmes.ContainsKey([string]$group[0].GuideId)) { @($programmes[[string]$group[0].GuideId] | Where-Object Valid) } else { @() }
        [pscustomobject]@{
            Key = [string]$group[0].Key; DisplayName = [string]$group[0].Name; GroupTitle = ''; Category = $null
            Programmes = @($rows | ForEach-Object { [pscustomobject]@{ Title = $_.Title; Start = $_.Start; Stop = $(if ($null -ne $_.Stop) { $_.Stop } else { $_.Start }) } })
        }
    }
    $channels = [System.Collections.Generic.List[object]]::new()
    $applied = [System.Collections.Generic.List[object]]::new()
    $fallback = [System.Collections.Generic.List[object]]::new()
    foreach ($rated in @(Get-ChannelForgeEventChannelCandidate -Channel @($detectorInput) | Where-Object { $_.Confidence -ceq 'high' })) {
        $group = $byKey[$rated.Key]
        $reason = $null
        if ($ExcludedKey -contains $rated.Key) { $reason = 'you saved a guide choice for this channel' }
        else {
            $guideRows = @()
            if ($group[0].GuideId -and $programmes.ContainsKey([string]$group[0].GuideId)) { $guideRows = @($programmes[[string]$group[0].GuideId]) }
            $built = Get-ChannelForgeEventProgrammeBlocks -Programme $guideRows -ChannelName $rated.DisplayName -WindowStart $window.Start -WindowEnd $window.End
            $reason = $built.Reason
        }
        if ($reason) { [void]$fallback.Add([pscustomobject]@{ Key = $rated.Key; Name = $rated.DisplayName; Reason = "normal guide kept: $reason" }); continue }
        [void]$channels.Add([pscustomobject]@{ Id = 'ChannelForge-' + $rated.Key.Substring(0, 32); Name = $rated.DisplayName; Blocks = $built.Blocks; Key = $rated.Key; EntryIds = @($group | ForEach-Object { [string]$_.EntryId }) })
        [void]$applied.Add([pscustomobject]@{ Key = $rated.Key; Name = $rated.DisplayName; Reason = "event guide applied: $($rated.Reasons -join '; ')" })
    }
    [pscustomobject]@{ Channel = @($channels.ToArray()); Applied = @($applied.ToArray()); Fallback = @($fallback.ToArray()) }
}
