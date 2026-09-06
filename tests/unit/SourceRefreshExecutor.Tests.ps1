BeforeAll {
    $script:Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Executor = Join-Path $script:Root 'scripts/Invoke-ChannelForgeSourceRefresh.ps1'
    $script:ResultSchema = Join-Path $script:Root 'schemas/source-refresh-result.schema.json'
    function Invoke-ExecutorHarness {
        param(
            [Parameter(Mandatory)]
            [object[]]$Plan,

            [Parameter(Mandatory)]
            [System.Collections.IDictionary]$Status,

            [string]$ErrorMessage = '',

            [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]'2026-01-01T00:00:00Z'),

            [ValidateSet('m3u', 'xmltv')]
            [string]$Kind = 'm3u'
        )

        $root = Join-Path $TestDrive ('executor-harness-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/providers'), (Join-Path $root 'data/epg') | Out-Null
        $providerPath = Join-Path $root 'data/providers/provider.json'
        $epgPath = Join-Path $root 'data/epg/epg.json'
        Set-Content -LiteralPath $providerPath -Value '{"provider":"fixture","sources":[]}'
        Set-Content -LiteralPath $epgPath -Value '{"epg_sources":[]}'

        $sourceName = [string]$Plan[0].Name
        $global:ChannelForgeExecutorHarnessPlan = @($Plan)
        $global:ChannelForgeExecutorHarnessStatus = $Status
        $global:ChannelForgeExecutorHarnessError = $ErrorMessage
        $global:ChannelForgeExecutorHarnessCalls = [System.Collections.Generic.List[object]]::new()
        $global:ChannelForgeExecutorHarnessProviderSources = if ($Kind -eq 'm3u') {
            @([pscustomobject]@{ Name = $sourceName })
        }
        else {
            @()
        }
        $global:ChannelForgeExecutorHarnessEpgSources = if ($Kind -eq 'xmltv') {
            @([pscustomobject]@{ Name = $sourceName })
        }
        else {
            @()
        }

        $functionNames = @(
            'Import-Module',
            'Read-ChannelForgeProvider',
            'Read-ChannelForgeEpgSource',
            'Get-ChannelForgeSourceRefreshPlan',
            'Import-ChannelForgeConfiguredM3USource',
            'Import-ChannelForgeConfiguredXmltvSource'
        )
        $previousDefinitions = @{}
        foreach ($functionName in $functionNames) {
            $previous = Get-Item -LiteralPath "Function:\$functionName" -ErrorAction SilentlyContinue
            $previousDefinitions[$functionName] = if ($null -ne $previous) {
                $previous.Definition
            }
            else {
                $null
            }
        }

        try {
            Set-Item -Path Function:\Import-Module -Value {
                param([object]$Name, [switch]$Force)
            }
            Set-Item -Path Function:\Read-ChannelForgeProvider -Value {
                param([string]$Path)
                @($global:ChannelForgeExecutorHarnessProviderSources)
            }
            Set-Item -Path Function:\Read-ChannelForgeEpgSource -Value {
                param([string]$Path)
                @($global:ChannelForgeExecutorHarnessEpgSources)
            }
            Set-Item -Path Function:\Get-ChannelForgeSourceRefreshPlan -Value {
                param(
                    [string]$ProviderConfigPath,
                    [string]$EpgConfigPath,
                    [string]$CacheRoot,
                    [datetimeoffset]$EvaluationTimeUtc
                )
                @($global:ChannelForgeExecutorHarnessPlan)
            }
            Set-Item -Path Function:\Import-ChannelForgeConfiguredM3USource -Value {
                param(
                    [psobject]$Source,
                    [string]$Provider,
                    [string]$CacheRoot,
                    [datetimeoffset]$EvaluationTimeUtc,
                    [System.Collections.IDictionary]$AcquisitionStatus
                )
                $global:ChannelForgeExecutorHarnessCalls.Add(
                    [pscustomobject]@{ Kind = 'm3u'; EvaluationTimeUtc = $EvaluationTimeUtc }
                ) | Out-Null
                if (-not [string]::IsNullOrWhiteSpace($global:ChannelForgeExecutorHarnessError)) {
                    throw $global:ChannelForgeExecutorHarnessError
                }
                if ($null -ne $AcquisitionStatus) {
                    foreach ($key in $global:ChannelForgeExecutorHarnessStatus.Keys) {
                        $AcquisitionStatus[$key] = $global:ChannelForgeExecutorHarnessStatus[$key]
                    }
                }
            }
            Set-Item -Path Function:\Import-ChannelForgeConfiguredXmltvSource -Value {
                param(
                    [psobject]$Source,
                    [string]$CacheRoot,
                    [datetimeoffset]$EvaluationTimeUtc,
                    [System.Collections.IDictionary]$AcquisitionStatus
                )
                $global:ChannelForgeExecutorHarnessCalls.Add(
                    [pscustomobject]@{ Kind = 'xmltv'; EvaluationTimeUtc = $EvaluationTimeUtc }
                ) | Out-Null
                if (-not [string]::IsNullOrWhiteSpace($global:ChannelForgeExecutorHarnessError)) {
                    throw $global:ChannelForgeExecutorHarnessError
                }
                if ($null -ne $AcquisitionStatus) {
                    foreach ($key in $global:ChannelForgeExecutorHarnessStatus.Keys) {
                        $AcquisitionStatus[$key] = $global:ChannelForgeExecutorHarnessStatus[$key]
                    }
                }
            }

            $result = & $script:Executor `
                -Root $root `
                -ProviderConfigPath $providerPath `
                -EpgConfigPath $epgPath `
                -CacheRoot (Join-Path $root 'cache') `
                -OutputRoot (Join-Path $root 'reports') `
                -EvaluationTimeUtc $EvaluationTimeUtc
            $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
            $harnessResult = [pscustomobject]@{
                Root   = $root
                Result = $result
                Report = $report
                Calls  = $global:ChannelForgeExecutorHarnessCalls
            }
        }
        finally {
            foreach ($functionName in $functionNames) {
                $definition = $previousDefinitions[$functionName]
                if ($null -eq $definition) {
                    Remove-Item -LiteralPath "Function:\$functionName" -Force -ErrorAction SilentlyContinue
                }
                else {
                    Set-Item -Path Function:\$functionName -Value $definition
                }
            }
            foreach ($variableName in @(
                    'ChannelForgeExecutorHarnessPlan',
                    'ChannelForgeExecutorHarnessStatus',
                    'ChannelForgeExecutorHarnessError',
                    'ChannelForgeExecutorHarnessCalls',
                    'ChannelForgeExecutorHarnessProviderSources',
                    'ChannelForgeExecutorHarnessEpgSources'
                )) {
                Remove-Variable -Name $variableName -Scope Global -Force -ErrorAction SilentlyContinue
            }
        }
        $harnessResult
    }


}
Describe 'one-shot source refresh executor' {
    It 'reports disabled sources without contacting a source and writes safe reports' {
        $root = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/providers'),(Join-Path $root 'data/epg') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'data/providers/provider.local.json') -Value '{"provider":"fixture","sources":[{"name":"Disabled","url":"https://example.invalid/secret","enabled":false}]}'
        Set-Content -LiteralPath (Join-Path $root 'data/epg/epg_sources.local.json') -Value '{"epg_sources":[]}'
        $result = & $script:Executor -Root $root
        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        Test-Json -Path $result.JsonPath -SchemaFile $script:ResultSchema | Should -BeTrue
        $report.SchemaVersion | Should -Be 'source-refresh-result/v2'
        $report.ReviewNeeded | Should -BeFalse
        $report.ReviewNeededCount | Should -Be 0
        $report.Sources[0].Result | Should -Be 'REVIEW_REQUIRED'
        $report.Sources[0].Classification | Should -Be 'NoAction'
        $report.Sources[0].ReasonCode | Should -Be 'DisabledSource'
        $report.Sources[0].Attempted | Should -BeFalse
        $report.Sources[0].SafeReason | Should -Not -Match 'example.invalid|secret'
        Test-Path $result.MarkdownPath | Should -BeTrue
    }

    It 'does not create accepted-state or generation output' {
        $root = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/providers'),(Join-Path $root 'data/epg') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'data/providers/provider.local.json') -Value '{"provider":"fixture","sources":[]}'
        Set-Content -LiteralPath (Join-Path $root 'data/epg/epg_sources.local.json') -Value '{"epg_sources":[]}'
        $null = & $script:Executor -Root $root
        Test-Path (Join-Path $root 'output/accepted') | Should -BeFalse
        Test-Path (Join-Path $root 'output/generations') | Should -BeFalse
    }

    It 'orders results deterministically and excludes private source details' {
        $root = Join-Path $TestDrive 'ordered-project'
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data/providers'),(Join-Path $root 'data/epg') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'data/providers/provider.local.json') -Value '{"provider":"fixture","sources":[{"name":"Zulu","url":"https://example.invalid/ACCOUNT_ID/API_TOKEN/z","enabled":false},{"name":"Alpha","url":"https://example.invalid/ACCOUNT_ID/API_TOKEN/a","enabled":false}]}'
        Set-Content -LiteralPath (Join-Path $root 'data/epg/epg_sources.local.json') -Value '{"epg_sources":[{"name":"Guide","url":"https://example.invalid/ACCOUNT_ID/API_TOKEN/g","enabled":false,"role":"primary"}]}'
        $result = & $script:Executor -Root $root
        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        @($report.Sources | ForEach-Object Name) | Should -Be @('Alpha','Zulu','Guide')
        ($report | ConvertTo-Json -Depth 8) | Should -Not -Match 'ACCOUNT_ID|API_TOKEN|example.invalid'
        Test-Json -Path $result.JsonPath -SchemaFile $script:ResultSchema | Should -BeTrue
        $report.Sources[0].Classification | Should -Be 'NoAction'
        $report.Sources[0].ReasonCode | Should -Be 'DisabledSource'
        $report.ReviewNeeded | Should -BeFalse
        $report.ReviewNeededCount | Should -Be 0
    }
    It 'reports validated 304 responses as unchanged for both source formats' {
        foreach ($kind in @('m3u', 'xmltv')) {
            $name = if ($kind -eq 'm3u') { 'Playlist' } else { 'Guide' }
            $sourceId = if ($kind -eq 'm3u') { 'm3u-fixture' } else { 'xmltv-fixture' }
            $status = [ordered]@{
                Outcome        = 'CacheHit'
                Reason         = if ($kind -eq 'm3u') { 'Validated304' } else { 'ConditionalResponse' }
                StatusCode      = 304
                HasETag        = $kind -eq 'm3u'
                HasLastModified = $kind -eq 'xmltv'
            }
            $plan = [pscustomobject][ordered]@{
                SourceId         = $sourceId
                Name             = $name
                Kind             = 'remote'
                RecommendedAction = 'CONDITIONAL_REFRESH'
                CacheState       = 'EXPIRED'
                Validator        = if ($kind -eq 'm3u') { 'ETAG' } else { 'LAST_MODIFIED' }
                Reason           = 'Validated cache expired; reusable validator evidence exists.'
            }

            $harness = Invoke-ExecutorHarness -Plan $plan -Status $status -Kind $kind
            $row = @($harness.Report.Sources)[0]
            $row.Result | Should -Be 'CONDITIONAL_REFRESHED'
            $row.CacheChanged | Should -BeFalse
            $row.LastKnownGoodPreserved | Should -BeFalse
            $row.ValidatorOutcome | Should -Be $plan.Validator
            $row.SafeReason | Should -Match 'unchanged.*cache payload.*retained'
            $row.Classification | Should -Be 'AutoHandled'
            $row.ReasonCode | Should -Be 'ConditionalUnchanged'
            @($harness.Calls).Count | Should -Be 1
            $harness.Calls[0].EvaluationTimeUtc | Should -Be ([datetimeoffset]'2026-01-01T00:00:00Z')
        }
    }

    It 'reports changed conditional 200 responses as validated cache updates' {
        foreach ($kind in @('m3u', 'xmltv')) {
            $name = if ($kind -eq 'm3u') { 'Changed Playlist' } else { 'Changed Guide' }
            $sourceId = if ($kind -eq 'm3u') { 'm3u-changed' } else { 'xmltv-changed' }
            $status = [ordered]@{
                Outcome         = 'Fetched'
                Reason          = 'FreshFetched'
                StatusCode       = 200
                HasETag         = $true
                HasLastModified = $false
            }
            $plan = [pscustomobject][ordered]@{
                SourceId          = $sourceId
                Name              = $name
                Kind              = 'remote'
                RecommendedAction = 'CONDITIONAL_REFRESH'
                CacheState        = 'EXPIRED'
                Validator         = 'ETAG'
                Reason            = 'Validated cache expired; reusable validator evidence exists.'
            }

            $harness = Invoke-ExecutorHarness -Plan $plan -Status $status -Kind $kind
            $row = @($harness.Report.Sources)[0]
            $row.Result | Should -Be 'CONDITIONAL_REFRESHED'
            $row.CacheChanged | Should -BeTrue
            $row.ValidatorOutcome | Should -Be 'ETAG'
            $row.Classification | Should -Be 'AutoHandled'
            $row.ReasonCode | Should -Be 'ConditionalChanged'
            $row.SafeReason | Should -Match 'changed source content was validated.*cache payload was updated'
            @($harness.Calls).Count | Should -Be 1
        }
    }

    It 'preserves an expired last-known-good cache across refresh failure classes' {
        foreach ($failure in @(
                'network failure',
                'malformed response',
                'empty response',
                'unsafe redirect'
            )) {
            $plan = [pscustomobject][ordered]@{
                SourceId          = 'm3u-failure'
                Name              = 'Failure Fixture'
                Kind              = 'remote'
                RecommendedAction = 'CONDITIONAL_REFRESH'
                CacheState        = 'EXPIRED'
                Validator         = 'ETAG'
                Reason            = 'Validated cache expired; reusable validator evidence exists.'
            }
            $status = [ordered]@{}
            $harness = Invoke-ExecutorHarness `
                -Plan $plan `
                -Status $status `
                -ErrorMessage $failure
            $row = @($harness.Report.Sources)[0]
            $row.Result | Should -Be 'REFRESH_FAILED'
            $row.CacheChanged | Should -BeFalse
            $row.LastKnownGoodPreserved | Should -BeTrue
            $row.Classification | Should -Be 'Degraded'
            $row.ReasonCode | Should -Be 'RefreshFailedLkgPreserved'
            $harness.Report.ReviewNeeded | Should -BeFalse
            $harness.Report.ReviewNeededCount | Should -Be 0
            $row.SafeReason | Should -Match 'last-known-good cache was preserved'
            @($harness.Calls).Count | Should -Be 1
            Test-Path -LiteralPath (Join-Path $harness.Root 'output/accepted') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $harness.Root 'output/generations') | Should -BeFalse
        }
    }

    It 'propagates a fixed evaluation time through the actual executor report path' {
        $evaluationTime = [datetimeoffset]'2026-01-01T05:59:59Z'
        $plan = [pscustomobject][ordered]@{
            SourceId          = 'm3u-fresh'
            Name              = 'Fresh Fixture'
            Kind              = 'remote'
            RecommendedAction = 'USE_VALID_CACHE'
            CacheState        = 'FRESH'
            Validator         = 'ETAG'
            Reason            = 'Validated cache is within the fixed provider cache lifetime.'
        }
        $harness = Invoke-ExecutorHarness `
            -Plan $plan `
            -Status ([ordered]@{}) `
            -EvaluationTimeUtc $evaluationTime
        $row = @($harness.Report.Sources)[0]
        $row.Result | Should -Be 'REUSED_VALID_CACHE'
        $row.Attempted | Should -BeFalse
        $row.CacheChanged | Should -BeFalse
        $row.Classification | Should -Be 'AutoHandled'
        $row.ReasonCode | Should -Be 'ReusedValidCache'
        $row.SafeReason | Should -Match 'no network request was made'
        ([datetimeoffset]$harness.Report.EvaluationTimeUtc).ToUniversalTime().ToString('o') | Should -Be $evaluationTime.ToUniversalTime().ToString('o')
        @($harness.Calls).Count | Should -Be 0
    }

    It 'classifies unresolved planned review and counts only review-needed rows' {
        $plan = [pscustomobject][ordered]@{
            SourceId          = 'm3u-invalid'
            Name              = 'Invalid Fixture'
            Kind              = 'remote'
            Enabled           = $true
            RecommendedAction = 'REVIEW'
            CacheState        = 'INVALID'
            Validator         = 'NONE'
            Reason            = 'Cache cannot be planned safely: MalformedMetadata.'
        }
        $harness = Invoke-ExecutorHarness `
            -Plan $plan `
            -Status ([ordered]@{})
        $row = @($harness.Report.Sources)[0]
        Test-Json -Path $harness.Result.JsonPath -SchemaFile $script:ResultSchema | Should -BeTrue
        $row.Result | Should -Be 'REVIEW_REQUIRED'
        $row.Classification | Should -Be 'ReviewNeeded'
        $row.ReasonCode | Should -Be 'InvalidCache'
        $harness.Report.ReviewNeeded | Should -BeTrue
        $harness.Report.ReviewNeededCount | Should -Be 1
    }

    It 'does not count local sources as review-needed' {
        $root = Join-Path $TestDrive 'local-project'
        $playlist = Join-Path $root 'data/playlists/local.m3u'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $playlist), (Join-Path $root 'data/providers'), (Join-Path $root 'data/epg') | Out-Null
        Set-Content -LiteralPath $playlist -Value '#EXTM3U'
        Set-Content -LiteralPath (Join-Path $root 'data/providers/provider.local.json') -Value '{"provider":"fixture","sources":[{"name":"Local","url":"https://example.invalid/local.m3u","enabled":true,"local_playlist":"data/playlists/local.m3u"}]}'
        Set-Content -LiteralPath (Join-Path $root 'data/epg/epg_sources.local.json') -Value '{"epg_sources":[]}'
        $result = & $script:Executor -Root $root
        $report = Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json
        $row = @($report.Sources)[0]
        Test-Json -Path $result.JsonPath -SchemaFile $script:ResultSchema | Should -BeTrue
        $row.Classification | Should -Be 'NoAction'
        $row.ReasonCode | Should -Be 'LocalSource'
        $report.ReviewNeeded | Should -BeFalse
        $report.ReviewNeededCount | Should -Be 0
    }

    It 'classifies a validated full refresh as automatically handled' {
        $plan = [pscustomobject][ordered]@{
            SourceId          = 'm3u-full'
            Name              = 'Full Fixture'
            Kind              = 'remote'
            Enabled           = $true
            RecommendedAction = 'FULL_REFRESH'
            CacheState        = 'MISSING'
            Validator         = 'NONE'
            Reason            = 'No validated cache metadata was found; a complete refresh is required.'
        }
        $status = [ordered]@{
            Outcome         = 'Fetched'
            Reason          = 'FreshFetched'
            StatusCode      = 200
            HasETag         = $false
            HasLastModified = $false
        }
        $harness = Invoke-ExecutorHarness `
            -Plan $plan `
            -Status $status
        $row = @($harness.Report.Sources)[0]
        $row.Result | Should -Be 'FULL_REFRESHED'
        $row.Classification | Should -Be 'AutoHandled'
        $row.ReasonCode | Should -Be 'FullRefreshValidated'
        $harness.Report.ReviewNeeded | Should -BeFalse
        $harness.Report.ReviewNeededCount | Should -Be 0
    }

}
