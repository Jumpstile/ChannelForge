[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$ProviderConfigPath,
    [string]$EpgConfigPath,
    [string]$CacheRoot,
    [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]::UtcNow),
    [string]$OutputRoot,
    [string]$EnrollmentPath
)

$ErrorActionPreference = 'Stop'
$rootFull = [IO.Path]::GetFullPath($Root)
if ([string]::IsNullOrWhiteSpace($ProviderConfigPath)) { $ProviderConfigPath = Join-Path $rootFull 'data/providers/provider.local.json'; if (-not (Test-Path $ProviderConfigPath)) { $ProviderConfigPath = Join-Path $rootFull 'data/providers/provider.example.json' } }
if ([string]::IsNullOrWhiteSpace($EpgConfigPath)) { $EpgConfigPath = Join-Path $rootFull 'data/epg/epg_sources.local.json'; if (-not (Test-Path $EpgConfigPath)) { $EpgConfigPath = Join-Path $rootFull 'data/epg/epg_sources.example.json' } }
if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $rootFull 'output/cache' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $rootFull 'output/reports' }

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'src/ChannelForge/ChannelForge.psd1') -Force

$providerId = 'provider'
$providerConfig = @()
$epgConfig = @()
if ([string]::IsNullOrWhiteSpace($EnrollmentPath)) {
    $providerRaw = Get-Content -LiteralPath $ProviderConfigPath -Raw | ConvertFrom-Json
    $providerId = if (-not [string]::IsNullOrWhiteSpace([string]$providerRaw.provider)) { [string]$providerRaw.provider } else { 'provider' }
    $providerConfig = @(Read-ChannelForgeProvider -Path $ProviderConfigPath)
    $epgConfig = @(Read-ChannelForgeEpgSource -Path $EpgConfigPath)
}
$planArguments = @{
    ProviderConfigPath = $ProviderConfigPath
    EpgConfigPath = $EpgConfigPath
    CacheRoot = $CacheRoot
    EvaluationTimeUtc = $EvaluationTimeUtc
}
if (-not [string]::IsNullOrWhiteSpace($EnrollmentPath)) { $planArguments.EnrollmentPath = $EnrollmentPath }
$plan = @(Get-ChannelForgeSourceRefreshPlan @planArguments) |
    Where-Object { $_.PSObject.Properties.Name -contains 'RecommendedAction' }
$rows = [System.Collections.Generic.List[object]]::new()
$reportRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null

function Get-ChannelForgeRefreshManagedSourceHash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $domain = [Text.UTF8Encoding]::new($false).GetBytes('managed-source-bytes/v1')
    $payload = [byte[]]::new($domain.Length + 1 + $Bytes.Length)
    [Buffer]::BlockCopy($domain, 0, $payload, 0, $domain.Length)
    $payload[$domain.Length] = 0
    [Buffer]::BlockCopy($Bytes, 0, $payload, $domain.Length + 1, $Bytes.Length)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function New-ChannelForgeEnrolledRefreshSourceSetCandidate {
    param(
        [Parameter(Mandatory)]$EnrollmentInputs,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ReplacementSourceId,
        [Parameter(Mandatory)][string]$ReplacementPath,
        [Parameter(Mandatory)][string]$OutputRoot
    )
    $makeSources = {
        param($records, [string]$kind)
        foreach ($record in @($records | Where-Object Enabled | Sort-Object Priority, OrderKey, SourceId) ) {
            $path = if ([string]$record.SourceId -eq $ReplacementSourceId) {
                $ReplacementPath
            } elseif ([string]::IsNullOrWhiteSpace([string]$record.ManagedPath)) {
                throw "Enrolled $kind source has no last-known-good snapshot."
            } else {
                Join-Path $RepositoryRoot ([string]$record.ManagedPath -replace '/', '\')
            }
            if (-not [IO.File]::Exists($path)) { throw "Enrolled $kind source snapshot is unavailable." }
            [pscustomobject]@{
                Kind = $kind
                SourceId = [string]$record.SourceId
                SourceKey = [string]$record.SourceId
                Label = [string]$record.Label
                Priority = [int]$record.Priority
                SourceKind = [string]$record.SourceKind
                Url = if ($record.PSObject.Properties.Name -contains 'Url') { [string]$record.Url } else { $null }
                Path = [IO.Path]::GetFullPath($path)
            }
        }
    }
    $playlists = @(& $makeSources $EnrollmentInputs.Enrollment.Playlists 'M3U')
    $guides = @(& $makeSources $EnrollmentInputs.Enrollment.Guides 'XMLTV')
    return New-ChannelForgeSourceSetCandidateProposal `
        -Root $RepositoryRoot `
        -PlaylistSources $playlists `
        -GuideSources $guides `
        -Bindings @($EnrollmentInputs.Bindings) `
        -OutputRoot $OutputRoot `
        -CandidateContractVersion 'blocker-2-contract/v7'
}
 $sourceUpdates = [System.Collections.Generic.List[object]]::new()
 foreach ($planned in $plan) {
     if ([string]$planned.SourceKind -eq 'enrolled') {
         $inputs = Get-ChannelForgeEnrolledSourceInput -RepositoryRoot $rootFull
         $record = @($inputs.Enrollment.Playlists + $inputs.Enrollment.Guides | Where-Object {
             [string]$_.SourceId -eq [string]$planned.EnrollmentSourceId
         }) | Select-Object -First 1
         $isRemote = [string]$planned.Kind -eq 'remote'
         $row = [ordered]@{
             SourceId = [string]$planned.SourceId
             Name = [string]$planned.Name
             Kind = [string]$planned.Kind
             PlannedAction = [string]$planned.RecommendedAction
             Attempted = $false
             Result = 'NOT_ATTEMPTED'
             Classification = 'ReviewNeeded'
             ReasonCode = 'InvalidCache'
             CacheChanged = $false
             LastKnownGoodPreserved = $false
             ValidatorOutcome = [string]$planned.Validator
             SafeReason = [string]$planned.Reason
         }
         if ($isRemote) {
             $row.Attempted = $true
             try {
                 if ($null -eq $record -or [string]::IsNullOrWhiteSpace([string]$record.Url)) { throw 'Enrolled public source URL is unavailable.' }
                 $maxBytes = if ([string]$record.Kind -eq 'M3U') { 4MB } else { 12MB }
                 $bytes = Get-ChannelForgeRemoteSourceBytes -Kind ([string]$record.Kind) -Url ([string]$record.Url) -MaxBytes $maxBytes
                 $hash = Get-ChannelForgeRefreshManagedSourceHash -Bytes $bytes
                 $same = -not [string]::IsNullOrWhiteSpace([string]$record.ContentHash) -and [string]$record.ContentHash -ceq $hash
                 if ($same) {
                     $row.Result = 'REUSED_VALID_CACHE'
                     $row.Classification = 'AutoHandled'
                     $row.ReasonCode = 'RemoteUnchanged'
                     $row.SafeReason = 'Public HTTPS source was fetched and matched the saved snapshot; accepted state was not modified.'
                     $sourceUpdates.Add([pscustomobject]@{ SourceId = [string]$record.SourceId; State = 'up-to-date' }) | Out-Null
                 }
                 else {
                     $candidateRoot = Join-Path (Join-Path $reportRoot 'refresh-candidates') ([string]$record.SourceId)
                     New-Item -ItemType Directory -Force -Path $candidateRoot | Out-Null
                     $extension = if ([string]$record.Kind -eq 'M3U') { 'm3u' } else { 'xml' }
                     $candidatePath = Join-Path $candidateRoot "$([string]$record.SourceId).$extension"
                     [IO.File]::WriteAllBytes($candidatePath, $bytes)
                     if ([string]$record.Kind -eq 'M3U') {
                         $channels = @(Import-ChannelForgeM3UPlaylist -Path $candidatePath -Provider 'candidate' -Playlist ([string]$record.Label))
                         if ($channels.Count -eq 0) { throw 'Remote M3U response contained no channels.' }
                     }
                     else {
                         $xmlStatus = [ordered]@{}
                         $programmes = @(Import-ChannelForgeXmltvSource -Path $candidatePath -SourceId ([string]$record.SourceId) -AcquisitionStatus $xmlStatus)
                         if ($programmes.Count -eq 0) { throw 'Remote XMLTV response contained no programmes.' }
                     }
                     try {
                         New-ChannelForgeEnrolledRefreshSourceSetCandidate `
                             -EnrollmentInputs $inputs `
                             -RepositoryRoot $rootFull `
                             -ReplacementSourceId ([string]$record.SourceId) `
                             -ReplacementPath $candidatePath `
                             -OutputRoot (Join-Path (Join-Path $reportRoot 'refresh-candidates') 'source-set') | Out-Null
                         $row.ReasonCode = 'CandidateGenerated'
                         $row.SafeReason = 'Changed public HTTPS source produced a review-only source-set candidate; accepted state and last-known-good snapshot were not modified.'
                     }
                     catch {
                         $row.ReasonCode = 'CandidateReviewRequired'
                         $row.SafeReason = 'Changed public HTTPS source was validated, but a complete source-set candidate could not be generated; accepted state and last-known-good snapshot were preserved.'
                     }
                     $row.Result = 'REVIEW_REQUIRED'
                     $row.Classification = 'ReviewNeeded'
                     $row.CacheChanged = $true
                     $row.LastKnownGoodPreserved = -not [string]::IsNullOrWhiteSpace([string]$record.ContentHash)
                     $sourceUpdates.Add([pscustomobject]@{ SourceId = [string]$record.SourceId; State = 'changes-found' }) | Out-Null
                 }
             }
             catch {
                 $row.Result = 'REFRESH_FAILED'
                 $row.Classification = if (-not [string]::IsNullOrWhiteSpace([string]$record.ContentHash)) { 'Degraded' } else { 'ReviewNeeded' }
                 $row.ReasonCode = if ($row.Classification -eq 'Degraded') { 'RefreshFailedLkgPreserved' } else { 'RefreshFailedNoLkg' }
                 $row.LastKnownGoodPreserved = -not [string]::IsNullOrWhiteSpace([string]$record.ContentHash)
                 $row.SafeReason = if ($row.LastKnownGoodPreserved) { 'Public HTTPS refresh failed; the saved last-known-good snapshot and accepted state were preserved.' } else { 'Public HTTPS refresh failed and no saved snapshot was available.' }
                 $sourceUpdates.Add([pscustomobject]@{ SourceId = [string]$record.SourceId; State = 'source-unavailable' }) | Out-Null
             }
         }
         elseif ([string]$planned.RecommendedAction -eq 'USE_VALID_CACHE') {
             $row.Result = 'REUSED_VALID_CACHE'
             $row.Classification = 'AutoHandled'
             $row.ReasonCode = 'ReusedValidCache'
             $row.SafeReason = 'Saved source bytes are unchanged; no network request was made and accepted state was not modified.'
         }
         elseif ([string]$planned.RecommendedAction -eq 'FULL_REFRESH') {
             $row.Attempted = $true
             try {
                 $candidateRoot = Join-Path $reportRoot 'refresh-candidates'
                 New-Item -ItemType Directory -Force -Path $candidateRoot | Out-Null
                 $candidateM3UPath = if ([string]$planned.EnrollmentKind -eq 'XMLTV') { [string]$inputs.M3UPath } else { [string]$planned.SourcePath }
                 $candidateXMLTVPath = if ([string]$planned.EnrollmentKind -eq 'XMLTV') { [string]$planned.SourcePath } else { [string]$planned.GuidePath }
                 New-ChannelForgeCandidateProposal `
                     -Root $rootFull `
                     -M3UPath $candidateM3UPath `
                     -XMLTVPath $candidateXMLTVPath `
                     -OutputRoot $candidateRoot `
                     -CandidateContractVersion 'blocker-2-contract/v8' | Out-Null
                 $row.Result = 'REVIEW_REQUIRED'
                 $row.Classification = 'ReviewNeeded'
                 $row.ReasonCode = 'CandidateGenerated'
                 $row.SafeReason = 'Changed saved source bytes produced a review-only candidate; accepted state was not modified.'
             }
             catch {
                 $row.Result = 'REFRESH_FAILED'
                 $row.Classification = 'ReviewNeeded'
                 $row.ReasonCode = 'RefreshFailedLkgPreserved'
                 $row.LastKnownGoodPreserved = $true
                 $row.SafeReason = 'Changed saved source could not produce a candidate; accepted state was preserved.'
             }
         }
         else {
             $row.Result = 'REVIEW_REQUIRED'
             $row.Classification = 'ReviewNeeded'
             $row.ReasonCode = 'InvalidCache'
             $row.SafeReason = [string]$planned.Reason
         }
         $rows.Add([pscustomobject]$row) | Out-Null
         continue
     }

     $source = if ($planned.Kind -eq 'remote' -and $planned.SourceId.StartsWith('m3u-')) {
         $providerConfig | Where-Object Name -eq $planned.Name | Select-Object -First 1
     }
     else {
         $epgConfig | Where-Object Name -eq $planned.Name | Select-Object -First 1
     }
     $row = [ordered]@{
         SourceId                = [string]$planned.SourceId
         Name                    = [string]$planned.Name
         Kind                    = [string]$planned.Kind
         PlannedAction           = [string]$planned.RecommendedAction
         Attempted               = $false
         Result                  = 'NOT_ATTEMPTED'
         Classification          = 'ReviewNeeded'
         ReasonCode              = 'InvalidCache'
         CacheChanged            = $false
         LastKnownGoodPreserved  = $false
         ValidatorOutcome        = [string]$planned.Validator
         SafeReason              = [string]$planned.Reason
     }
     if ($planned.RecommendedAction -in @('CONDITIONAL_REFRESH', 'FULL_REFRESH')) {
         $row.Attempted = $true
         $status = [ordered]@{}
         try {
             if ($planned.SourceId.StartsWith('m3u-')) {
                 @(Import-ChannelForgeConfiguredM3USource `
                     -Source $source `
                     -Provider $providerId `
                     -CacheRoot $CacheRoot `
                     -EvaluationTimeUtc $EvaluationTimeUtc `
                     -AcquisitionStatus $status) | Out-Null
             }
             else {
                 @(Import-ChannelForgeConfiguredXmltvSource `
                     -Source $source `
                     -CacheRoot $CacheRoot `
                     -EvaluationTimeUtc $EvaluationTimeUtc `
                     -AcquisitionStatus $status) | Out-Null
             }
             $outcome = [string]$status['Outcome']
             $reason = [string]$status['Reason']
             $statusCode = [int]$status['StatusCode']
             $isNotModified = $statusCode -eq 304 -or
                 $reason -eq 'Validated304' -or
                 $outcome -match '304|NotModified'
             $row.Result = if ($isNotModified) {
                 'CONDITIONAL_REFRESHED'
             }
             elseif ($planned.RecommendedAction -eq 'CONDITIONAL_REFRESH') {
                 'CONDITIONAL_REFRESHED'
             }
             else {
                 'FULL_REFRESHED'
             }
             $row.CacheChanged = -not $isNotModified
             $row.Classification = 'AutoHandled'
             $row.ValidatorOutcome = if ($status['HasETag'] -and $status['HasLastModified']) {
                 'ETAG_AND_LAST_MODIFIED'
             }
             elseif ($status['HasETag']) {
                 'ETAG'
             }
             elseif ($status['HasLastModified']) {
                 'LAST_MODIFIED'
             }
             else {
                 [string]$planned.Validator
             }
             if ($isNotModified) {
                 $row.ReasonCode = 'ConditionalUnchanged'
                 $row.SafeReason = 'Source was unchanged; existing validated cache payload was retained.'
             }
             elseif ($planned.RecommendedAction -eq 'CONDITIONAL_REFRESH') {
                 $row.ReasonCode = 'ConditionalChanged'
                 $row.SafeReason = 'Changed source content was validated; cache payload was updated.'
             }
             else {
                 $row.ReasonCode = 'FullRefreshValidated'
                 $row.SafeReason = 'Fetched response was validated before cache promotion.'
             }
         }
         catch {
             $row.Result = 'REFRESH_FAILED'
             $row.LastKnownGoodPreserved = $planned.CacheState -eq 'EXPIRED'
             if ($row.LastKnownGoodPreserved) {
                 $row.Classification = 'Degraded'
                 $row.ReasonCode = 'RefreshFailedLkgPreserved'
                 $row.SafeReason = 'Refresh failed; last-known-good cache was preserved.'
             }
             else {
                 $row.Classification = 'ReviewNeeded'
                 $row.ReasonCode = 'RefreshFailedNoLkg'
                 $row.SafeReason = 'Refresh failed; no validated cache was available to preserve.'
             }
         }
     }
     elseif ($planned.RecommendedAction -eq 'USE_VALID_CACHE') {
         $row.Result = 'REUSED_VALID_CACHE'
         $row.Classification = 'AutoHandled'
         $row.ReasonCode = 'ReusedValidCache'
         $row.SafeReason = 'Validated cache reused; no network request was made.'
     }
     elseif ($planned.RecommendedAction -eq 'REVIEW') {
         $row.Result = 'REVIEW_REQUIRED'
         if (-not [bool]$planned.Enabled) {
             $row.Classification = 'NoAction'
             $row.ReasonCode = 'DisabledSource'
         }
         elseif ([string]$planned.Kind -eq 'local' -or
             [string]$planned.CacheState -eq 'NOT_APPLICABLE_LOCAL') {
             $row.Classification = 'NoAction'
             $row.ReasonCode = 'LocalSource'
         }
         else {
             $row.Classification = 'ReviewNeeded'
             $row.ReasonCode = 'InvalidCache'
         }
         $row.SafeReason = [string]$planned.Reason
     }
     else {
         $row.Result = 'NOT_APPLICABLE'
         $row.Classification = 'NoAction'
         $row.ReasonCode = if ([string]$planned.Kind -eq 'local') {
             'LocalSource'
         }
         else {
             'DisabledSource'
         }
     }
     $rows.Add([pscustomobject]$row) | Out-Null
 }

 $sourceRows = @($rows | Sort-Object Kind, SourceId)
 $reviewNeededCount = @($sourceRows | Where-Object {
     [string]$_.Classification -eq 'ReviewNeeded'
 }).Count
if (-not [string]::IsNullOrWhiteSpace($EnrollmentPath)) {
    try {
        $refreshState = if ($reviewNeededCount -gt 0) { 'changes-found' } else { 'up-to-date' }
        Set-ChannelForgeSourceEnrollmentRefreshState -RepositoryRoot $rootFull -RefreshStatus $refreshState -SourceUpdates @($sourceUpdates.ToArray()) | Out-Null
    }
    catch {
        # Refresh evidence remains reportable; inability to update the non-authoritative status marker cannot mutate accepted state.
    }
}
 $projection = [ordered]@{
     SchemaVersion      = 'source-refresh-result/v2'
     EvaluationTimeUtc  = $EvaluationTimeUtc.ToUniversalTime().ToString('o')
     ReviewNeeded       = $reviewNeededCount -gt 0
     ReviewNeededCount  = [int]$reviewNeededCount
     Sources            = $sourceRows
 }
 $reportRoot = [IO.Path]::GetFullPath($OutputRoot)
 New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
 $jsonPath = Join-Path $reportRoot 'source-refresh-result.json'
 $mdPath = Join-Path $reportRoot 'source-refresh-result.md'
 [IO.File]::WriteAllText(
     $jsonPath,
     (($projection | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
     [Text.UTF8Encoding]::new($false))
 $md = [System.Collections.Generic.List[string]]::new()
 $md.Add('# Source refresh result')
 $md.Add('')
 $md.Add("Evaluation time: $($projection.EvaluationTimeUtc)")
 $md.Add("Review needed: $($projection.ReviewNeeded)")
 $md.Add("Review-needed sources: $($projection.ReviewNeededCount)")
 $md.Add('This one-shot operation refreshes disposable source cache evidence only. It does not publish or change accepted output.')
 $md.Add('')
 $md.Add('| Source | Kind | Planned action | Result | Classification | Reason | Cache changed | Last-known-good preserved |')
 $md.Add('| --- | --- | --- | --- | --- | --- | --- | --- |')
 foreach ($s in $projection.Sources) {
     $md.Add("| $($s.Name) | $($s.Kind) | $($s.PlannedAction) | $($s.Result) | $($s.Classification) | $($s.ReasonCode) | $($s.CacheChanged) | $($s.LastKnownGoodPreserved) |")
 }
 $md.Add('')
 $md.Add('A failed refresh never replaces a previously validated cache.')
 [IO.File]::WriteAllText(
     $mdPath,
     (($md -join [Environment]::NewLine) + [Environment]::NewLine),
     [Text.UTF8Encoding]::new($false))
 [pscustomobject][ordered]@{
     JsonPath     = $jsonPath
     MarkdownPath = $mdPath
     SourceCount  = $projection.Sources.Count
 }
