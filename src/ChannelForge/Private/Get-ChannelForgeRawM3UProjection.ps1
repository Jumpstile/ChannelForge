function Get-ChannelForgeRawM3UProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Channel[]]$Channel,
        [string]$LogicalSourceId = ''
    )
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($channelValue in @($Channel)) {
        if ($null -eq $channelValue) { continue }
        $hasRawIdentity = $null -ne $channelValue.PSObject.Properties['RawTvgIdPresence']
        $tvgId = if ($hasRawIdentity -and $null -ne $channelValue.PSObject.Properties['RawTvgId']) {
            $channelValue.RawTvgId
        }
        elseif ($null -eq $channelValue.TvgId) { $null } else { [string]$channelValue.TvgId }
        $sourceId = if ([string]::IsNullOrWhiteSpace($LogicalSourceId)) { Get-ChannelForgeLogicalSourceId -ProviderName ([string]$channelValue.Provider) -SourceName ([string]$channelValue.Playlist) -SourceKind 'M3U' } else { $LogicalSourceId }
        $presence = if ($hasRawIdentity) {
            [string]$channelValue.RawTvgIdPresence
        }
        elseif ($null -eq $tvgId) { 'Missing' }
        elseif ($tvgId.Length -eq 0) { 'Empty' }
        elseif ($tvgId -match '^[\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+$') { 'WhitespaceOnly' }
        else { 'Present' }
        $rawValue = if ($presence -eq 'Missing') { $null } else { $tvgId }
        $rawIdentityDigest = if ($presence -eq 'Missing') { $null } else { Get-ChannelForgeDomainHash -Domain 'raw-identity/v2' -InputObject ([ordered]@{ Version='raw-identity-v2'; Presence=$presence; RawValue=$rawValue }) }
        $base = [ordered]@{
            Version='raw-m3u-occurrence-v2'; LogicalSourceId=$sourceId; RawTvgIdPresence=$presence; RawTvgId=$rawValue; RawIdentityDigest=$rawIdentityDigest
            TvgName=[string]$channelValue.TvgName; DisplayName=[string]$channelValue.DisplayName; GroupTitle=[string]$channelValue.Group; Logo=[string]$channelValue.Logo; ChannelNumber=$channelValue.AssignedNumber; StreamUrl=[string]$channelValue.Url
            SafeDisplayFingerprint=Get-ChannelForgeDomainHash -Domain 'safe-display-fingerprint/v2' -InputObject ([ordered]@{ Version='safe-display-fingerprint-v2'; Value=[string]$channelValue.DisplayName })
            SafeGroupFingerprint=Get-ChannelForgeDomainHash -Domain 'safe-group-fingerprint/v2' -InputObject ([ordered]@{ Version='safe-group-fingerprint-v2'; Value=[string]$channelValue.Group })
            SafeTvgNameFingerprint=Get-ChannelForgeDomainHash -Domain 'safe-tvg-name-fingerprint/v2' -InputObject ([ordered]@{ Version='safe-tvg-name-fingerprint-v2'; Value=[string]$channelValue.TvgName; PolicyResult='Text' })
            StreamFingerprint=Get-ChannelForgeDomainHash -Domain 'stream-fingerprint/v2' -InputObject ([ordered]@{ Version='stream-fingerprint-v2'; Presence='Present'; StreamUrl=[string]$channelValue.Url })
        }
        $records.Add([pscustomobject][ordered]@{ Base=$base; BaseDigest=(Get-ChannelForgeDomainHash -Domain 'raw-m3u-occurrence/v2' -InputObject $base); Channel=$channelValue; SourceLocalOrdinal=0 })
    }
    foreach ($group in @($records | Group-Object { $_.Base.LogicalSourceId })) {
        $ordered = @($group.Group | Sort-Object BaseDigest)
        for ($i=0; $i -lt $ordered.Count; $i++) { $ordered[$i].SourceLocalOrdinal=$i }
    }
    $result=[System.Collections.Generic.List[object]]::new()
    foreach ($record in @($records | Sort-Object @{Expression={ [string]$_.Base.LogicalSourceId }}, @{Expression={ [int]$_.SourceLocalOrdinal }}, BaseDigest)) {
        $p=[ordered]@{}
        foreach ($key in @($record.Base.Keys)) { $p[$key]=$record.Base[$key] }
        $p.SourceLocalOrdinal=[int]$record.SourceLocalOrdinal
        $digest=Get-ChannelForgeDomainHash -Domain 'raw-m3u-occurrence/v2' -InputObject $p
        $history=$null
        if ($null -ne $p.RawTvgId) {
            $history=[regex]::Replace(([string]$p.RawTvgId).Normalize([Text.NormalizationForm]::FormC), '^[\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+|[\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+$', '').ToLowerInvariant()
            if ($history.Length -eq 0) { $history=$null }
        }
        $entryInput=[ordered]@{ Version='entry-id-v2'; EntryKind=if($null -eq $history){'MissingIdCandidate'}else{'StableHistory'}; LogicalSourceId=$p.LogicalSourceId; HistoryKey=$history; RawIdentityDigest=$p.RawIdentityDigest; IdentityOccurrenceOrdinal=0; SourceLocalOrdinal=$p.SourceLocalOrdinal; StructuralEvidenceHash=$null; StructuralOccurrenceOrdinal=$null }
        $result.Add([pscustomobject][ordered]@{ Version='raw-m3u-occurrence-v2'; EntryId=(Get-ChannelForgeDomainHash -Domain 'entry-id/v2' -InputObject $entryInput); LogicalSourceId=$p.LogicalSourceId; SourceLocalOrdinal=$p.SourceLocalOrdinal; HistoryKey=$history; HistoryIdentityStatus=if($null -eq $history){'MissingId'}else{'StableUnique'}; RawTvgIdPresence=$p.RawTvgIdPresence; RawTvgId=$p.RawTvgId; TvgName=$p.TvgName; DisplayName=$p.DisplayName; GroupTitle=$p.GroupTitle; Logo=$p.Logo; ChannelNumber=$p.ChannelNumber; StreamFingerprint=$p.StreamFingerprint; RawM3UOccurrenceDigest=$digest; Channel=$record.Channel })
    }
    return @($result.ToArray())
}
