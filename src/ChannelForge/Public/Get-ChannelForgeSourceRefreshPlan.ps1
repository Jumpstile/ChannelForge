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
        $m3uState = if ($null -eq $managed) { 'Unavailable' } else { [string]$managed.M3UState }
        $m3uAction = if ($m3uState -eq 'Ready') { 'USE_VALID_CACHE' } elseif ($m3uState -eq 'Changed') { 'FULL_REFRESH' } else { 'REVIEW' }
        $m3uReason = if ($m3uState -eq 'Ready') { 'Saved playlist bytes are unchanged; no source acquisition is required.' } elseif ($m3uState -eq 'Changed') { 'Saved playlist bytes changed; a candidate refresh is required for review.' } else { 'Saved playlist is unavailable or failed integrity checks.' }
        $enrollmentRows.Add([pscustomobject][ordered]@{
            SourceId = if ($null -eq $managed) { 'enrollment-m3u' } else { 'enrollment-m3u-' + ([string]$managed.Enrollment.M3U.SourceId).Substring(0, 16) }
            Name = 'Saved playlist'
            Kind = 'local'
            SourceKind = 'enrolled'
            Enabled = $true
            CacheState = 'MANAGED_SOURCE_' + $m3uState.ToUpperInvariant()
            Validator = 'SOURCE_FINGERPRINT'
            LastValidatedAtUtc = $enrollmentStatus.LastCheckedUtc
            RecommendedAction = $m3uAction
            Reason = $m3uReason
            EnrollmentKind = 'M3U'
            SourcePath = if ($null -eq $managed) { $null } else { $managed.M3UPath }
            GuidePath = if ($null -eq $managed) { $null } else { $managed.XMLTVPath }
        }) | Out-Null
        if ([string]$enrollmentStatus.XMLTVStatus -ne 'no-guide') {
            $xmlState = if ($null -eq $managed) { 'Unavailable' } else { [string]$managed.XMLTVState }
            $xmlAction = if ($xmlState -eq 'Ready') { 'USE_VALID_CACHE' } elseif ($xmlState -eq 'Changed') { 'FULL_REFRESH' } else { 'REVIEW' }
            $xmlReason = if ($xmlState -eq 'Ready') { 'Saved guide bytes are unchanged; no source acquisition is required.' } elseif ($xmlState -eq 'Changed') { 'Saved guide bytes changed; a candidate refresh is required for review.' } else { 'Saved guide is unavailable or failed integrity checks.' }
            $enrollmentRows.Add([pscustomobject][ordered]@{
                SourceId = if ($null -eq $managed) { 'enrollment-xmltv' } else { 'enrollment-xmltv-' + ([string]$managed.Enrollment.XMLTV.SourceId).Substring(0, 16) }
                Name = 'Saved guide'
                Kind = 'local'
                SourceKind = 'enrolled'
                Enabled = $true
                CacheState = 'MANAGED_SOURCE_' + $xmlState.ToUpperInvariant()
                Validator = 'SOURCE_FINGERPRINT'
                LastValidatedAtUtc = $enrollmentStatus.LastCheckedUtc
                RecommendedAction = $xmlAction
                Reason = $xmlReason
                EnrollmentKind = 'XMLTV'
                SourcePath = if ($null -eq $managed) { $null } else { $managed.XMLTVPath }
                PlaylistPath = if ($null -eq $managed) { $null } else { $managed.M3UPath }
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
