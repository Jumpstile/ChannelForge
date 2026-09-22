function Get-ChannelForgeSourceRefreshPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProviderConfigPath,
        [Parameter(Mandatory)][string]$EpgConfigPath,
        [Parameter(Mandatory)][string]$CacheRoot,
        [Parameter(Mandatory)][datetimeoffset]$EvaluationTimeUtc,
        [string]$EnrollmentPath = ''
    )
    if (-not [string]::IsNullOrWhiteSpace($EnrollmentPath)) {
        $enrollmentRoot = Split-Path -Parent (Split-Path -Parent ([System.IO.Path]::GetFullPath($EnrollmentPath)))
        $enrollmentStatus = Get-ChannelForgeSourceEnrollment -RepositoryRoot $enrollmentRoot
        $enrollmentRows = [System.Collections.Generic.List[object]]::new()
        $managed = $null
        try { $managed = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $enrollmentRoot } catch { $managed = $null }
        if ($null -eq $managed) {
            $enrollmentRows.Add([pscustomobject][ordered]@{
                SourceId = 'enrollment-m3u'
                Name = 'Saved playlist'
                Kind = 'local'
                SourceKind = 'enrolled'
                Enabled = $true
                CacheState = 'MANAGED_SOURCE_UNAVAILABLE'
                Validator = 'SOURCE_FINGERPRINT'
                LastValidatedAtUtc = $enrollmentStatus.LastCheckedUtc
                RecommendedAction = 'REVIEW'
                Reason = 'Saved playlist is unavailable or failed integrity checks.'
                EnrollmentKind = 'M3U'
                SourcePath = $null
                GuidePath = $null
            }) | Out-Null
            return @($enrollmentRows)
        }
        $states = @{}
        foreach ($state in @($managed.SourceStates)) { $states[[string]$state.SourceId] = $state }
        foreach ($record in @($managed.Enrollment.Playlists) + @($managed.Enrollment.Guides) | Where-Object Enabled | Sort-Object Kind, Priority, OrderKey, SourceId) {
            $sourceState = if ($states.ContainsKey([string]$record.SourceId)) { [string]$states[[string]$record.SourceId].State } else { 'Unavailable' }
            $isRemote = [string]$record.SourceKind -eq 'public-https'
            if ($isRemote) {
                $action = 'REVIEW'
                $reason = 'Public source refresh is not part of this enrollment slice; review the source before acquisition.'
                $cacheState = 'PUBLIC_SOURCE_REVIEW'
            }
            else {
                $action = if ($sourceState -eq 'Ready') { 'USE_VALID_CACHE' } elseif ($sourceState -eq 'Changed') { 'FULL_REFRESH' } else { 'REVIEW' }
                $reason = if ($sourceState -eq 'Ready') { 'Saved source bytes are unchanged; no source acquisition is required.' } elseif ($sourceState -eq 'Changed') { 'Saved source bytes changed; a candidate refresh is required for review.' } else { 'Saved source is unavailable or failed integrity checks.' }
                $cacheState = 'MANAGED_SOURCE_' + $sourceState.ToUpperInvariant()
            }
            $managedPath = if ($isRemote -or [string]::IsNullOrWhiteSpace([string]$record.ManagedPath)) { $null } else { [System.IO.Path]::GetFullPath((Join-Path $enrollmentRoot ([string]$record.ManagedPath -replace '/', '\'))) }
            $enrollmentRows.Add([pscustomobject][ordered]@{
                SourceId = 'enrollment-' + ([string]$record.Kind).ToLowerInvariant() + '-' + ([string]$record.SourceId).Substring(0, 16)
                Name = [string]$record.Label
                Kind = if ($isRemote) { 'remote' } else { 'local' }
                SourceKind = 'enrolled'
                Enabled = [bool]$record.Enabled
                CacheState = $cacheState
                Validator = 'SOURCE_FINGERPRINT'
                LastValidatedAtUtc = $enrollmentStatus.LastCheckedUtc
                RecommendedAction = $action
                Reason = $reason
                EnrollmentKind = [string]$record.Kind
                SourcePath = if ([string]$record.Kind -eq 'M3U') { $managedPath } else { $null }
                GuidePath = if ([string]$record.Kind -eq 'XMLTV') { $managedPath } else { $null }
            }) | Out-Null
        }
        return @($enrollmentRows | Sort-Object Kind, SourceId)
    }


    $providerRaw = Get-Content -LiteralPath $ProviderConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $providerId = if (-not [string]::IsNullOrWhiteSpace([string]$providerRaw.provider)) { [string]$providerRaw.provider } else { 'provider' }
    $providerSources = @(Read-ChannelForgeProvider -Path $ProviderConfigPath)
    $epgSources = @(Read-ChannelForgeEpgSource -Path $EpgConfigPath)
    $sources = [System.Collections.Generic.List[object]]::new()

    foreach ($source in $providerSources) {
        $name = ([string]$source.Name).Trim()
        $local = -not [string]::IsNullOrWhiteSpace([string]$source.LocalPlaylist)
        $enabled = [bool]$source.Enabled
        $id = 'm3u-' + (Get-ChannelForgeDomainHash -Domain 'refresh-plan-source/v1' -InputObject "m3u|$providerId|$name").Substring(0, 16)
        $row = [ordered]@{ SourceId=$id; Name=$name; Kind=if($local){'local'}else{'remote'}; Enabled=$enabled; CacheState=if(-not $enabled){'DISABLED'}elseif($local){'NOT_APPLICABLE_LOCAL'}else{'MISSING'}; Validator='NONE'; LastValidatedAtUtc=$null; RecommendedAction='REVIEW'; Reason=if(-not $enabled){'Disabled source is excluded from unattended planning.'}elseif($local){'Local source is read from the working tree; no network refresh is planned.'}else{'No validated cache metadata was found.'} }
        if ($enabled -and -not $local) {
            try {
                $cache = Read-ChannelForgeRemoteM3UFetchCache -CacheRoot $CacheRoot -ProviderId $providerId -SourceId $name -Url ([string]$source.Url) -EvaluationTimeUtc $EvaluationTimeUtc
                if ($cache.MetadataValid -and $cache.PayloadValid) {
                    $row.Validator = if ($cache.Metadata.ETag -and $cache.Metadata.LastModified) {'ETAG_AND_LAST_MODIFIED'} elseif ($cache.Metadata.ETag) {'ETAG'} elseif ($cache.Metadata.LastModified) {'LAST_MODIFIED'} else {'NONE'}
                    $row.LastValidatedAtUtc = ([datetimeoffset]$cache.Metadata.ValidatedAtUtc).ToUniversalTime().ToString('o')
                    if ($cache.IsFresh) {$row.CacheState='FRESH';$row.RecommendedAction='USE_VALID_CACHE';$row.Reason='Validated cache is within the fixed provider cache lifetime.'} elseif ($cache.CanConditional) {$row.CacheState='EXPIRED';$row.RecommendedAction='CONDITIONAL_REFRESH';$row.Reason='Validated cache expired; reusable validator evidence exists.'} else {$row.CacheState='EXPIRED';$row.RecommendedAction='FULL_REFRESH';$row.Reason='Validated cache expired and has no reusable validator.'}
                } else {$row.CacheState=if($cache.InvalidReason -eq 'MissingMetadata'){'MISSING'}else{'INVALID'};$row.RecommendedAction=if($cache.InvalidReason -eq 'MissingMetadata'){'FULL_REFRESH'}else{'REVIEW'};$row.Reason=if($cache.InvalidReason -eq 'MissingMetadata'){'No validated cache metadata was found; a complete refresh is required.'}else{"Cache cannot be planned safely: $($cache.InvalidReason)."}}
            } catch {$row.CacheState='INVALID';$row.RecommendedAction='REVIEW';$row.Reason='Source or cache metadata could not be validated safely.'}
        }
        $sources.Add([pscustomobject]$row)
    }
    foreach ($source in $epgSources) {
        $name = ([string]$source.Name).Trim(); $local = $source.SourceKind -eq 'local'; $enabled=[bool]$source.Enabled
        $id = 'xmltv-' + (Get-ChannelForgeDomainHash -Domain 'refresh-plan-source/v1' -InputObject "xmltv|$name").Substring(0,16)
        $row = [ordered]@{SourceId=$id;Name=$name;Kind=if($local){'local'}else{'remote'};Enabled=$enabled;CacheState=if(-not $enabled){'DISABLED'}elseif($local){'NOT_APPLICABLE_LOCAL'}else{'MISSING'};Validator='NONE';LastValidatedAtUtc=$null;RecommendedAction='REVIEW';Reason=if(-not $enabled){'Disabled source is excluded from unattended planning.'}elseif($local){'Local source is read from the working tree; no network refresh is planned.'}else{'No validated cache metadata was found.'}}
        if ($enabled -and -not $local) {
            try {
                $cache=Read-ChannelForgeRemoteXmltvFetchCache -CacheRoot $CacheRoot -SourceId $name -Url ([string]$source.Url) -EvaluationTimeUtc $EvaluationTimeUtc
                if($cache.MetadataValid -and $cache.PayloadValid){$row.Validator=if($cache.Metadata.ETag -and $cache.Metadata.LastModified){'ETAG_AND_LAST_MODIFIED'}elseif($cache.Metadata.ETag){'ETAG'}elseif($cache.Metadata.LastModified){'LAST_MODIFIED'}else{'NONE'};$row.LastValidatedAtUtc=([datetimeoffset]$cache.Metadata.ValidatedAtUtc).ToUniversalTime().ToString('o');if($cache.IsFresh){$row.CacheState='FRESH';$row.RecommendedAction='USE_VALID_CACHE';$row.Reason='Validated cache is within the fixed EPG cache lifetime.'}elseif($cache.CanConditional){$row.CacheState='EXPIRED';$row.RecommendedAction='CONDITIONAL_REFRESH';$row.Reason='Validated cache expired; reusable validator evidence exists.'}else{$row.CacheState='EXPIRED';$row.RecommendedAction='FULL_REFRESH';$row.Reason='Validated cache expired and has no reusable validator.'}}else{$row.CacheState=if($cache.InvalidReason -eq 'MissingMetadata'){'MISSING'}else{'INVALID'};$row.RecommendedAction=if($cache.InvalidReason -eq 'MissingMetadata'){'FULL_REFRESH'}else{'REVIEW'};$row.Reason=if($cache.InvalidReason -eq 'MissingMetadata'){'No validated cache metadata was found; a complete refresh is required.'}else{"Cache cannot be planned safely: $($cache.InvalidReason)."}}
            } catch {$row.CacheState='INVALID';$row.RecommendedAction='REVIEW';$row.Reason='Source or cache metadata could not be validated safely.'}
        }
        $sources.Add([pscustomobject]$row)
    }
    @($sources | Sort-Object Kind, SourceId)
}
