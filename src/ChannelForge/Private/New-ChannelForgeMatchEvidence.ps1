function Get-ChannelForgeMatchEvidenceOrder {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$CandidateManifest, [Parameter(Mandatory)][byte[]]$M3UBytes)

    # One job: the candidate entries in merged.m3u order. v8 and later candidates carry byte
    # offsets. A v7 candidate does not, so the accepted bytes are read back and each row is
    # matched to an entry by stream fingerprint (then name). Throws if any row cannot be matched.
    $entries = @($CandidateManifest.Entries)
    if (@($entries | Where-Object { $null -eq $_.EntryOutputSlice -or $null -eq $_.EntryOutputSlice.ByteOffset }).Count -eq 0) {
        return @($entries | Sort-Object { [uint64]$_.EntryOutputSlice.ByteOffset })
    }
    $reader = [System.IO.StringReader]::new([System.Text.Encoding]::UTF8.GetString($M3UBytes))
    try { $rows = @(Read-ChannelForgeM3UReader -Reader $reader) } finally { $reader.Dispose() }
    $pool = @{}
    foreach ($entry in @($entries | Sort-Object { [string]$_.EntryId })) {
        $key = [string]$entry.StreamFingerprint
        if (-not $pool.ContainsKey($key)) { $pool[$key] = [System.Collections.Generic.List[object]]::new() }
        $pool[$key].Add($entry)
    }
    $ordered = foreach ($row in $rows) {
        $key = Get-ChannelForgeDomainHash -Domain 'stream-fingerprint/v2' -InputObject ([ordered]@{ Version = 'stream-fingerprint-v2'; StreamUrl = [string]$row.Url })
        $list = $pool[$key]
        if ($null -eq $list -or $list.Count -eq 0) { throw 'FAIL_CLOSED: match evidence row has no candidate entry.' }
        $name = Get-ChannelForgeWebLineupText ([string]$row.DisplayName)
        $hit = $list | Where-Object { (Get-ChannelForgeWebLineupText ([string]$_.DisplayName)) -ceq $name } | Select-Object -First 1
        if ($null -eq $hit) { if ($list.Count -gt 1) { throw "FAIL_CLOSED: match evidence row is ambiguous." }; $hit = $list[0] }
        [void]$list.Remove($hit)
        $hit
    }
    if (@($ordered).Count -ne $entries.Count) { throw 'FAIL_CLOSED: match evidence row count differs from candidate entries.' }
    return @($ordered)
}

function New-ChannelForgeMatchEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CandidateManifest,
        [Parameter(Mandatory)]$Accepted,
        [Parameter(Mandatory)][byte[]]$M3UBytes
    )

    # Builds the match-evidence/v1 document for one accepted generation: one row per
    # accepted playlist entry, in merged.m3u order (outputOrdinal, 1-based).
    $ordered = @(Get-ChannelForgeMatchEvidenceOrder -CandidateManifest $CandidateManifest -M3UBytes $M3UBytes)
    $bindingByEntry = @{}
    foreach ($binding in @($CandidateManifest.BindingRecords)) {
        if ([string]$binding.BindingKind -ceq 'M3U') { $bindingByEntry[[string]$binding.EntryId] = $binding }
    }
    $sourceByGuideId = @{}
    foreach ($guide in @($CandidateManifest.GuideOccurrences)) {
        if ([string]$guide.RawIdentityPresence -ceq 'Present') { $sourceByGuideId["$($guide.RawIdentityValue)|$($guide.OccurrenceOrdinal)"] = [string]$guide.LogicalSourceId }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $ordered) {
        $binding = $bindingByEntry[[string]$entry.EntryId]
        $guideId = if ($null -ne $binding -and [string]$binding.M3URawIdPresence -ceq 'Present') { [string]$binding.M3URawId } else { $null }
        # The binding record has no source field; the guide occurrence list gives it back.
        $sources = @()
        if ($null -ne $binding -and [string]$binding.XMLTVIdPresence -ceq 'Present') {
            $sources = @(@($binding.CandidateChannelOccurrenceOrdinals) | ForEach-Object { $sourceByGuideId["$($binding.XMLTVId)|$_"] } | Where-Object { $_ } | Sort-Object -Unique)
        }
        $rows.Add([ordered]@{
                entryId = [string]$entry.EntryId
                bindingId = if ($null -eq $binding) { $null } else { [string]$binding.BindingId }
                outputOrdinal = $rows.Count + 1
                channelName = Get-ChannelForgeWebLineupText ([string]$entry.DisplayName)
                status = if ($null -eq $binding) { $null } else { [string]$binding.Status }
                reasonCode = if ($null -eq $binding) { $null } else { [string]$binding.ReasonCode }
                guideId = if ($null -eq $guideId) { $null } else { Get-ChannelForgeWebLineupText $guideId 256 }
                guideSourceId = if ($sources.Count -eq 1) { Get-ChannelForgeWebLineupText $sources[0] 256 } else { $null }
                collisionCount = if ($null -eq $binding) { 0 } else { @($binding.CollisionEvidence).Count }
            })
    }
    $document = [ordered]@{
        schemaVersion = 'match-evidence/v1'
        generationId = [string]$Accepted.GenerationId
        acceptedStateHash = [string]$Accepted.AcceptedState.AcceptedStateHash
        acceptedOutputManifestHash = [string]$Accepted.AcceptedOutputManifest.OutputManifestHash
        candidateManifestHash = [string]$Accepted.GenerationManifest.CandidateManifestHash
        entryCount = $rows.Count
        entries = @($rows)
    }
    $document.evidenceHash = Get-ChannelForgeDomainHash -Domain 'match-evidence/v1' -InputObject $document
    return $document
}
