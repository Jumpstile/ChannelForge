[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$ProviderConfigPath,
    [string]$EpgConfigPath,
    [string]$CacheRoot,
    [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]::UtcNow),
    [string]$OutputRoot
)

$rootFull = [IO.Path]::GetFullPath($Root)
if ([string]::IsNullOrWhiteSpace($ProviderConfigPath)) { $ProviderConfigPath = Join-Path $rootFull 'data/providers/provider.local.json'; if (-not (Test-Path $ProviderConfigPath)) { $ProviderConfigPath = Join-Path $rootFull 'data/providers/provider.example.json' } }
if ([string]::IsNullOrWhiteSpace($EpgConfigPath)) { $EpgConfigPath = Join-Path $rootFull 'data/epg/epg_sources.local.json'; if (-not (Test-Path $EpgConfigPath)) { $EpgConfigPath = Join-Path $rootFull 'data/epg/epg_sources.example.json' } }
if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $rootFull 'output/cache' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $rootFull 'output/reports' }

Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/ChannelForge/ChannelForge.psd1') -Force
$plan = @(Get-ChannelForgeSourceRefreshPlan -ProviderConfigPath $ProviderConfigPath -EpgConfigPath $EpgConfigPath -CacheRoot $CacheRoot -EvaluationTimeUtc $EvaluationTimeUtc)
$projection = [ordered]@{
    SchemaVersion = 'source-refresh-plan/v1'
    EvaluationTimeUtc = $EvaluationTimeUtc.ToUniversalTime().ToString('o')
    Sources = @($plan)
}
$reportRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
$jsonPath = Join-Path $reportRoot 'source-refresh-plan.json'
$mdPath = Join-Path $reportRoot 'source-refresh-plan.md'
$json = $projection | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($jsonPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
$md = [System.Collections.Generic.List[string]]::new()
$md.Add('# Source refresh plan')
$md.Add('')
$md.Add("Evaluation time: $($projection.EvaluationTimeUtc)")
$md.Add('This report plans work from configuration and validated cache evidence only. It does not contact sources or change accepted output.')
$md.Add('')
$md.Add('| Source | Kind | Enabled | Cache | Validator | Recommended action |')
$md.Add('| --- | --- | --- | --- | --- | --- |')
foreach ($source in $plan) { $md.Add("| $($source.Name) | $($source.Kind) | $($source.Enabled) | $($source.CacheState) | $($source.Validator) | $($source.RecommendedAction) |") }
$md.Add('')
$md.Add('## Terms')
$md.Add('')
$md.Add('- Cache: a previously downloaded copy ChannelForge can safely reuse.')
$md.Add('- Validator: ETag or Last-Modified evidence that lets a later remote request ask whether content changed.')
$md.Add('- Expired: the cached copy reached the point where ChannelForge should check the source again.')
$md.Add('- Disabled and local sources are not planned for unattended network work.')
[IO.File]::WriteAllText($mdPath, ($md -join [Environment]::NewLine) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
[pscustomobject][ordered]@{ JsonPath = $jsonPath; MarkdownPath = $mdPath; SourceCount = $plan.Count }
