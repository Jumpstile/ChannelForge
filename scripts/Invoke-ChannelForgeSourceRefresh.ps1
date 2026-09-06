[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$ProviderConfigPath,
    [string]$EpgConfigPath,
    [string]$CacheRoot,
    [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]::UtcNow),
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$rootFull = [IO.Path]::GetFullPath($Root)
if ([string]::IsNullOrWhiteSpace($ProviderConfigPath)) { $ProviderConfigPath = Join-Path $rootFull 'data/providers/provider.local.json'; if (-not (Test-Path $ProviderConfigPath)) { $ProviderConfigPath = Join-Path $rootFull 'data/providers/provider.example.json' } }
if ([string]::IsNullOrWhiteSpace($EpgConfigPath)) { $EpgConfigPath = Join-Path $rootFull 'data/epg/epg_sources.local.json'; if (-not (Test-Path $EpgConfigPath)) { $EpgConfigPath = Join-Path $rootFull 'data/epg/epg_sources.example.json' } }
if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $rootFull 'output/cache' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $rootFull 'output/reports' }

$moduleRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'src/ChannelForge/ChannelForge.psd1') -Force

$providerRaw = Get-Content -LiteralPath $ProviderConfigPath -Raw | ConvertFrom-Json
 $providerId = if (-not [string]::IsNullOrWhiteSpace([string]$providerRaw.provider)) {
     [string]$providerRaw.provider
 }
 else {
     'provider'
 }
 $providerConfig = @(Read-ChannelForgeProvider -Path $ProviderConfigPath)
 $epgConfig = @(Read-ChannelForgeEpgSource -Path $EpgConfigPath)
 $plan = @(Get-ChannelForgeSourceRefreshPlan `
     -ProviderConfigPath $ProviderConfigPath `
     -EpgConfigPath $EpgConfigPath `
     -CacheRoot $CacheRoot `
     -EvaluationTimeUtc $EvaluationTimeUtc) |
     Where-Object { $_.PSObject.Properties.Name -contains 'RecommendedAction' }
 $rows = [System.Collections.Generic.List[object]]::new()

 foreach ($planned in $plan) {
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
