function Update-ChannelForgeLogoLookup {
    <#
    .SYNOPSIS
    Refreshes data\logo-lookup.json (logo-lookup/v1) from the iptv-org logo list.
    .DESCRIPTION
    Owner-run only. No build, test or candidate run calls it. This is the only
    place in the logo lookup feature that uses the network.

    Keeps one link per channel ID. An ID with several links is skipped and
    listed. A name goes into ByName only when it maps to exactly one link.
    Links must be public https with no user info, and their host must be on the
    allow-list (-AllowedHost). The list starts empty: run with -WhatIf first,
    read the hosts it saw, then approve hosts by passing them in -AllowedHost.

    Refuses (the old file stays) when the list has no usable links, when the new
    file would have fewer than half of the old channel IDs, or when the old file
    cannot be read. -WhatIf writes nothing. The write is atomic (temp file, then
    move). Nothing else is ever deleted or changed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$AllowedHost = @(),
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $dataRoot = Join-Path ([System.IO.Path]::GetFullPath($RepositoryRoot)) 'data'
    $path = Join-Path $dataRoot 'logo-lookup.json'
    $old = Read-ChannelForgeLogoLookupFile -Path $path

    $list = ConvertFrom-ChannelForgeIptvOrgLogoList -Text (Get-ChannelForgeLogoListDownload)
    $plan = Get-ChannelForgeLogoLookupPlan -Entry $list.Entries -AllowedHost $AllowedHost

    $say = { param($Text) Write-Information $Text -InformationAction Continue }
    $show = { param($Items) ((@($Items) | Select-Object -First 20) -join ', ') + $(if (@($Items).Count -gt 20) { ', ...' } else { '' }) }
    & $say ("Hosts seen: " + $(if ($plan.HostsSeen.Count -eq 0) { 'none' } else { (@($plan.HostsSeen.Keys | ForEach-Object { "$_ ($($plan.HostsSeen[$_]))" }) -join ', ') }))
    & $say "Allowed hosts: $(if (@($AllowedHost).Count -eq 0) { 'none' } else { @($AllowedHost) -join ', ' })"
    if ($list.Malformed -gt 0) { & $say "Dropped $($list.Malformed) list entries without a channel and url." }
    foreach ($reason in $plan.Refused.Keys) { & $say "Refused $($plan.Refused[$reason]): $reason." }
    if ($plan.SkippedIds.Count -gt 0) { & $say "Skipped $($plan.SkippedIds.Count) channel IDs with several links: $(& $show $plan.SkippedIds)" }
    if ($plan.AmbiguousNames.Count -gt 0) { & $say "Left out $($plan.AmbiguousNames.Count) ambiguous names: $(& $show $plan.AmbiguousNames)" }

    if ($plan.ById.Count -eq 0) {
        throw 'Refused: the list has no usable links (see the hosts and reasons above; approve hosts with -AllowedHost). The old file was left as it was.'
    }
    if ($null -ne $old -and $old.ById.Count -gt 0 -and ($plan.ById.Count * 2) -lt $old.ById.Count) {
        throw "Refused: the new list has $($plan.ById.Count) channel IDs and the old file has $($old.ById.Count). That is a drop of more than half. The old file was left as it was."
    }

    $byId = Compare-ChannelForgeLogoLookupMap -Old ($null -ne $old ? $old.ById : $null) -New $plan.ById
    $byName = Compare-ChannelForgeLogoLookupMap -Old ($null -ne $old ? $old.ByName : $null) -New $plan.ByName
    & $say "ById: $($byId.Added) added, $($byId.Changed) changed, $($byId.Removed) removed ($($plan.ById.Count) total)."
    & $say "ByName: $($byName.Added) added, $($byName.Changed) changed, $($byName.Removed) removed ($($plan.ByName.Count) total)."

    $written = $false
    if ($PSCmdlet.ShouldProcess($path, 'Write the logo lookup file')) {
        $document = [ordered]@{
            Version      = 'logo-lookup/v1'
            Source       = 'iptv-org'
            RefreshedUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            ById         = $plan.ById
            ByName       = $plan.ByName
        }
        $text = ((ConvertTo-Json -InputObject $document -Depth 4) -replace "`r`n", "`n") + "`n"
        try {
            Write-ChannelForgeSourceEnrollmentAtomicBytes -Path $path -AllowedRoot $dataRoot -Bytes ([System.Text.UTF8Encoding]::new($false, $true).GetBytes($text))
        }
        catch {
            throw "Could not save the logo lookup file: $($_.Exception.Message) The old file was left as it was."
        }
        $written = $true
    }

    return [pscustomobject][ordered]@{
        Path           = $path
        Written        = $written
        ById           = $byId
        ByName         = $byName
        HostsSeen      = $plan.HostsSeen
        SkippedIds     = $plan.SkippedIds
        AmbiguousNames = $plan.AmbiguousNames
    }
}
