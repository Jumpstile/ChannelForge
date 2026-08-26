function Get-ChannelForgeRawM3UProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Channel[]]$Channel,
        [string]$LogicalSourceId = ''
    )

    # SourceLocalOrdinal is assigned only after the single ordinal-free raw
    # digest has been computed and the frozen tuple has been sorted. Keep the
    # Channel reference internal; it is not hashed or published.
    $records = [System.Collections.Generic.List[object]]::new()
    $whitespacePattern = '^[\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+$'

    foreach ($channelValue in @($Channel)) {
        if ($null -eq $channelValue) { continue }
        $hasRawPresence = $null -ne $channelValue.PSObject.Properties['RawTvgIdPresence']
        $hasRawValue = $null -ne $channelValue.PSObject.Properties['RawTvgId']
        $rawTvgId = if ($hasRawValue) {
            $channelValue.RawTvgId
        }
        elseif ($hasRawPresence -and [string]$channelValue.RawTvgIdPresence -eq 'Missing') {
            $null
        }
        elseif ($null -eq $channelValue.TvgId) {
            $null
        }
        else {
            [string]$channelValue.TvgId
        }
        $presence = if ($hasRawPresence) {
            [string]$channelValue.RawTvgIdPresence
        }
        elseif ($null -eq $rawTvgId) {
            'Missing'
        }
        else {
            'Present'
        }
        if ($presence -notin @('Missing', 'Present')) {
            throw "Raw M3U tvg-id presence '$presence' is invalid."
        }
        if ($presence -eq 'Missing') { $rawTvgId = $null }

        $sourceId = if ([string]::IsNullOrEmpty($LogicalSourceId)) {
            Get-ChannelForgeLogicalSourceId -ProviderName ([string]$channelValue.Provider) -SourceName ([string]$channelValue.Playlist) -SourceKind 'M3U'
        }
        else {
            $LogicalSourceId
        }
        $getRawProperty = {
            param([string]$Name, [object]$Fallback)
            $property = $channelValue.PSObject.Properties[$Name]
            if ($null -ne $property) { return $property.Value }
            return $Fallback
        }
        $tvgName = [string](& $getRawProperty 'RawTvgName' $channelValue.TvgName)
        $displayName = [string](& $getRawProperty 'RawDisplayName' $channelValue.DisplayName)
        $groupTitle = [string](& $getRawProperty 'RawGroupTitle' $channelValue.Group)
        $logo = [string](& $getRawProperty 'RawLogo' $channelValue.Logo)
        $channelNumber = & $getRawProperty 'RawChannelNumber' $channelValue.AssignedNumber
        if ($null -ne $channelNumber) { $channelNumber = [string]$channelNumber }
        $streamUrl = [string]$channelValue.Url

        # Exact frozen digest projection: ten fields, in this order.
        $projection = [ordered]@{
            Version          = 'raw-m3u-occurrence-v2'
            LogicalSourceId  = [string]$sourceId
            RawTvgIdPresence = $presence
            RawTvgId         = $rawTvgId
            TvgName          = $tvgName
            DisplayName      = $displayName
            GroupTitle       = $groupTitle
            Logo             = $logo
            ChannelNumber    = $channelNumber
            StreamUrl        = $streamUrl
        }
        $digest = Get-ChannelForgeDomainHash -Domain 'raw-m3u-occurrence/v2' -InputObject $projection
        [void]$records.Add([pscustomobject][ordered]@{
                Projection = $projection
                Digest = $digest
                Channel = $channelValue
                SourceLocalOrdinal = 0
            })
    }

    foreach ($group in @($records | Group-Object { [string]$_.Projection.LogicalSourceId })) {
        $ordered = [System.Collections.Generic.List[object]]::new()
        foreach ($record in @($group.Group)) { [void]$ordered.Add($record) }
        $ordered.Sort([System.Comparison[object]]{
                param($left, $right)
                $lp = $left.Projection
                $rp = $right.Projection
                $comparison = [System.StringComparer]::Ordinal.Compare([string]$left.Digest, [string]$right.Digest)
                if ($comparison -ne 0) { return $comparison }
                $leftRank = if ([string]$lp.RawTvgIdPresence -eq 'Missing') { 0 } else { 1 }
                $rightRank = if ([string]$rp.RawTvgIdPresence -eq 'Missing') { 0 } else { 1 }
                if ($leftRank -ne $rightRank) { return $leftRank - $rightRank }
                foreach ($field in @('RawTvgId', 'TvgName', 'DisplayName', 'GroupTitle', 'Logo', 'ChannelNumber', 'StreamUrl')) {
                    $comparison = [System.StringComparer]::Ordinal.Compare([string]$lp[$field], [string]$rp[$field])
                    if ($comparison -ne 0) { return $comparison }
                }
                return 0
            })
        for ($index = 0; $index -lt $ordered.Count; $index++) {
            $ordered[$index].SourceLocalOrdinal = $index
        }
    }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($records | Sort-Object `
                @{ Expression = { [string]$_.Projection.LogicalSourceId } }, `
                @{ Expression = { [int]$_.SourceLocalOrdinal } }, `
                @{ Expression = { [string]$_.Digest } })) {
        $projection = $record.Projection
        $history = $null
        if ([string]$projection.RawTvgIdPresence -eq 'Present') {
            $history = ([string]$projection.RawTvgId).Normalize([Text.NormalizationForm]::FormC)
            $history = [regex]::Replace($history, '^[\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+|[\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u205F\u3000]+$', '')
            $history = $history.ToLowerInvariant()
            if ($history.Length -eq 0) { $history = $null }
        }
        $entryInput = [ordered]@{
            Version = 'entry-id-v2'
            LogicalSourceId = [string]$projection.LogicalSourceId
            SourceLocalOrdinal = [int]$record.SourceLocalOrdinal
            RawM3UOccurrenceDigest = [string]$record.Digest
        }
        [void]$result.Add([pscustomobject][ordered]@{
                Version = 'raw-m3u-occurrence-v2'
                EntryId = Get-ChannelForgeDomainHash -Domain 'entry-id/v2' -InputObject $entryInput
                LogicalSourceId = [string]$projection.LogicalSourceId
                SourceLocalOrdinal = [int]$record.SourceLocalOrdinal
                HistoryKey = $history
                HistoryIdentityStatus = if ($null -eq $history) { 'MissingId' } else { 'StableUnique' }
                RawTvgIdPresence = [string]$projection.RawTvgIdPresence
                RawTvgId = $projection.RawTvgId
                TvgName = [string]$projection.TvgName
                DisplayName = [string]$projection.DisplayName
                GroupTitle = [string]$projection.GroupTitle
                Logo = [string]$projection.Logo
                ChannelNumber = $projection.ChannelNumber
                StreamUrl = [string]$projection.StreamUrl
                RawM3UOccurrenceDigest = [string]$record.Digest
                Channel = $record.Channel
            })
    }
    return @($result.ToArray())
}
