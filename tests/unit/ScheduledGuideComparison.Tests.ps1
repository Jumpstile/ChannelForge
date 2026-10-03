BeforeAll {
    $script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:Repo 'src/ChannelForge/ChannelForge.psd1'
    $script:ComparisonScript = Join-Path $script:Repo 'scripts/Invoke-ChannelForgeScheduledGuideComparison.ps1'
    $script:SourceResultSchema = Join-Path $script:Repo 'schemas/source-refresh-result.schema.json'
    $script:ComparisonSchema = Join-Path $script:Repo 'schemas/scheduled-guide-comparison.schema.json'
    Import-Module $script:ModulePath -Force
    if (-not ('ChannelForge.Tests.ScheduledComparisonCachePayload' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
namespace ChannelForge.Tests
{
    public sealed class ScheduledComparisonCachePayload : IDisposable
    {
        public Stream ResponseStream { get; }
        public int StatusCode => 200;
        public string ContentType => "application/xml";
        public string[] ContentEncodings => Array.Empty<string>();
        public long? ContentLength { get; }
        public bool HasPayload => true;
        public string ETag => "\"scheduled-comparison-fixture\"";
        public DateTimeOffset? LastModified => null;
        public ScheduledComparisonCachePayload(byte[] bytes)
        {
            ResponseStream = new MemoryStream(bytes, false);
            ContentLength = bytes.LongLength;
        }
        public void Dispose() => ResponseStream.Dispose();
    }
}
'@
    }


    function Set-RemoteCacheFixture {
        param(
            [Parameter(Mandatory)]$Project,
            [Parameter(Mandatory)][datetimeoffset]$EvaluationTimeUtc,
            [string]$SourceName = 'Remote Guide',
            [string]$Channel = 'station.one',
            [string]$Title = 'Alpha Beta Championship Final'
        )
        $xml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><tv><channel id=`"$Channel`"><display-name>Remote Channel</display-name></channel><programme start=`"20260101130000 +0000`" stop=`"20260101140000 +0000`" channel=`"$Channel`"><title>$Title</title><desc>A sufficiently detailed description of the same scheduled regional championship event.</desc><category>Wrestling</category></programme></tv>"
        $global:ScheduledComparisonCacheBytes = [Text.Encoding]::UTF8.GetBytes($xml)
        Mock -CommandName Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -MockWith {
            param($SourceId,$Url,$MaxRawResponseBytes,$IfNoneMatch,$IfModifiedSince,$Allow304MetadataOnly)
            [ChannelForge.Tests.ScheduledComparisonCachePayload]::new($global:ScheduledComparisonCacheBytes)
        }
        $source = @(Read-ChannelForgeEpgSource -Path $Project.ConfigPath | Where-Object { $_.Name.Trim() -ceq $SourceName })[0]
        $status = [ordered]@{}
        Import-ChannelForgeConfiguredXmltvSource -Source $source -CacheRoot $Project.CacheRoot -EvaluationTimeUtc $EvaluationTimeUtc -AcquisitionStatus $status | Out-Null
        $status.Outcome | Should -Be 'Fetched'
    }

    function New-ComparisonProject {
        $root = Join-Path $TestDrive ('scheduled-comparison-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'schemas') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'data/epg') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'output/cache') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'output/reports') -Force
        Copy-Item -LiteralPath $script:SourceResultSchema -Destination (Join-Path $root 'schemas/source-refresh-result.schema.json')
        [pscustomobject]@{
            Root = $root
            ConfigPath = Join-Path $root 'data/epg/sources.json'
            OutputRoot = Join-Path $root 'output/reports'
            CacheRoot = Join-Path $root 'output/cache'
            SourceResultPath = Join-Path $root 'output/reports/source-refresh-result.json'
        }
    }

    function Get-TestEpgSourceId {
        param([Parameter(Mandatory)][string]$Name,[ValidateSet('local','remote')][string]$Kind='local')
        $module = Get-Module ChannelForge | Select-Object -First 1
        & $module {
            param($sourceKind,$sourceName)
            $json = ConvertTo-ChannelForgeCanonicalJson -InputObject ([ordered]@{ Kind = $sourceKind; Name = $sourceName })
            'source-' + ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)))).ToLowerInvariant().Substring(0,16)
        } $Kind $Name
    }
    function Get-TestRefreshSourceId {
        param([Parameter(Mandatory)][string]$Name)
        $module = Get-Module ChannelForge | Select-Object -First 1
        & $module {
            param($sourceName)
            'xmltv-' + (Get-ChannelForgeDomainHash -Domain 'refresh-plan-source/v1' -InputObject "xmltv|$sourceName").Substring(0,16)
        } $Name
    }


    function Write-ComparisonFixture {
        param([Parameter(Mandatory)]$Project,[string]$FirstChannel = 'station.one',[string]$SecondChannel = 'station.two',[string]$FirstTitle = 'Alpha Beta Championship Final',[string]$SecondTitle = 'Alpha Beta Championship',[string]$FirstStart = '20260101130000 +0000',[string]$FirstStop = '20260101140000 +0000',[string]$SecondStart = '20260101130000 +0000',[string]$SecondStop = '20260101140000 +0000')
        $sources = [ordered]@{ epg_sources = @(
            [ordered]@{ name = 'Guide One'; priority = 1; path = 'guide-one.xml'; enabled = $true; role = 'primary' },
            [ordered]@{ name = 'Guide Two'; priority = 2; path = 'guide-two.xml'; enabled = $true; role = 'secondary' }
        ) }
        [IO.File]::WriteAllText($Project.ConfigPath, ($sources | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        foreach ($entry in @(@{ File = 'guide-one.xml'; Channel = $FirstChannel; Title = $FirstTitle; Start = $FirstStart; Stop = $FirstStop }, @{ File = 'guide-two.xml'; Channel = $SecondChannel; Title = $SecondTitle; Start = $SecondStart; Stop = $SecondStop })) {
            $xml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><tv><channel id=`"$($entry.Channel)`"><display-name>Guide Channel</display-name></channel><programme start=`"$($entry.Start)`" stop=`"$($entry.Stop)`" channel=`"$($entry.Channel)`"><title>$($entry.Title)</title><desc>A sufficiently detailed description of the same scheduled regional championship event.</desc><category>Wrestling</category></programme></tv>"
            [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $Project.ConfigPath) $entry.File), $xml, [Text.UTF8Encoding]::new($false))
        }
        $evaluation = '2026-01-01T15:00:00Z'
        $rows = @(
            [ordered]@{ SourceId='xmltv-aaaaaaaaaaaaaaaa'; Name='Guide One'; Kind='local'; PlannedAction='REVIEW'; Attempted=$false; Result='REVIEW_REQUIRED'; Classification='NoAction'; ReasonCode='LocalSource'; CacheChanged=$false; LastKnownGoodPreserved=$false; ValidatorOutcome='NONE'; SafeReason='Local XMLTV source.' },
            [ordered]@{ SourceId='xmltv-bbbbbbbbbbbbbbbb'; Name='Guide Two'; Kind='local'; PlannedAction='REVIEW'; Attempted=$false; Result='REVIEW_REQUIRED'; Classification='NoAction'; ReasonCode='LocalSource'; CacheChanged=$false; LastKnownGoodPreserved=$false; ValidatorOutcome='NONE'; SafeReason='Local XMLTV source.' }
        )
        $result = [ordered]@{ SchemaVersion='source-refresh-result/v2'; EvaluationTimeUtc=$evaluation; ReviewNeeded=$false; ReviewNeededCount=0; Sources=$rows }
        [IO.File]::WriteAllText($Project.SourceResultPath, ($result | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        [pscustomobject]@{ EvaluationTimeUtc = [datetimeoffset]$evaluation; Rows = $rows }
    }

    function Set-ApprovedTestBindings {
        param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$BindingRows)
        $identityActions = @(
            @{ Action='RegisterIdentity'; Entry=@{ ChannelId='channel-one' }; Reason='Register fixture channel one.' },
            @{ Action='RegisterIdentity'; Entry=@{ ChannelId='channel-two' }; Reason='Register fixture channel two.' }
        )
        $identityPlan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $Root -CreatedAtUtc '2026-01-01T00:00:00Z' -Actions $identityActions
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $Root -Plan $identityPlan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:00:00Z' | Out-Null
        $bindingActions = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $BindingRows) {
            $channelId = if ($row.ContainsKey('ChannelId')) { [string]$row.ChannelId } elseif ($row.Name -eq 'Guide One') { 'channel-one' } else { 'channel-two' }
            $kind = if ($row.ContainsKey('Kind')) { [string]$row.Kind } else { 'local' }
            $bindingActions.Add(@{ Action='AddBinding'; Entry=@{ ChannelId=$channelId; PlaylistId='playlist-one'; SourceId=(Get-TestEpgSourceId -Name $row.Name -Kind $kind); SourceChannelReference=$row.Reference; ObservationIds=@() }; Reason='Propose exact fixture source binding.' })
        }
        $bindingPlan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $Root -CreatedAtUtc '2026-01-01T00:01:00Z' -Actions @($bindingActions.ToArray())
        $added = Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $Root -Plan $bindingPlan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:01:00Z'
        $approveActions = @($added.Entries | Where-Object Kind -eq 'ChannelBinding' | ForEach-Object { @{ Action='Approve'; EntryId=$_.EntryId; Reason='Approve exact fixture binding.' } })
        $approvalPlan = New-ChannelForgeKnowledgeChangePlan -RepositoryRoot $Root -CreatedAtUtc '2026-01-01T00:02:00Z' -Actions $approveActions
        Apply-ChannelForgeKnowledgeChangePlan -RepositoryRoot $Root -Plan $approvalPlan -ConfirmApply APPLY -AppliedAtUtc '2026-01-01T00:02:00Z' | Out-Null
    }

    function Invoke-ComparisonFixture {
        param([Parameter(Mandatory)]$Project,[Parameter(Mandatory)][datetimeoffset]$EvaluationTimeUtc)
        & $script:ComparisonScript -Root $Project.Root -OutputRoot $Project.OutputRoot -EpgConfigPath $Project.ConfigPath -CacheRoot $Project.CacheRoot -SourceResultPath $Project.SourceResultPath -PlaylistId 'playlist-one' -EvaluationTimeUtc $EvaluationTimeUtc | Out-Null
        $path = Join-Path $Project.OutputRoot 'scheduled-guide-comparison.json'
        Test-Json -Path $path -SchemaFile $script:ComparisonSchema -ErrorAction Stop | Should -BeTrue
        Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    }
}

Describe 'bounded scheduled guide comparison' {
    It 'resolves only exact approved bindings and leaves local freshness unknown without a plan' {
        $project = New-ComparisonProject
        $fixture = Write-ComparisonFixture -Project $project
        Set-ApprovedTestBindings -Root $project.Root -BindingRows @(
            @{ Name='Guide One'; Reference='station.one' },
            @{ Name='Guide Two'; Reference='station.two' }
        )

        $report = Invoke-ComparisonFixture -Project $project -EvaluationTimeUtc $fixture.EvaluationTimeUtc

        $report.Status | Should -Be 'SUCCEEDED'
        $report.ObservationCount | Should -Be 2
        $report.UnresolvedReferenceCount | Should -Be 0
        $report.KnowledgeStateRevision | Should -Be 3
        @($report.Comparer.FreshnessAssessments | Where-Object FreshnessState -eq 'Unknown').Count | Should -Be 2
        $report.Comparer.ContextualAliasProposals.Count | Should -Be 0
        $report.KnowledgeChangePlan | Should -BeNullOrEmpty
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $project.Root).Revision | Should -Be 3
    }
    It 'does not correlate unrelated programmes on the same canonical channel by a provisional channel key' {
        $project = New-ComparisonProject
        $fixture = Write-ComparisonFixture -Project $project -FirstTitle 'Morning regional wrestling event' -SecondTitle 'Evening cooking programme' -SecondStart '20260101140000 +0000' -SecondStop '20260101150000 +0000'
        Set-ApprovedTestBindings -Root $project.Root -BindingRows @(
            @{ Name='Guide One'; Reference='station.one'; ChannelId='channel-one' },
            @{ Name='Guide Two'; Reference='station.two'; ChannelId='channel-one' }
        )

        $report = Invoke-ComparisonFixture -Project $project -EvaluationTimeUtc $fixture.EvaluationTimeUtc

        $report.ObservationCount | Should -Be 2
        $report.Comparer.Summary.CorrelationCount | Should -Be 0
        $report.Comparer.CrossChannelCorrelations.Count | Should -Be 0
    }



    It 'does not pass unbound or raw-reference-mismatched XMLTV rows to the comparer' {
        $project = New-ComparisonProject
        $fixture = Write-ComparisonFixture -Project $project -FirstChannel ' station.one'
        Set-ApprovedTestBindings -Root $project.Root -BindingRows @(
            @{ Name='Guide One'; Reference='station.one' }
        )

        $report = Invoke-ComparisonFixture -Project $project -EvaluationTimeUtc $fixture.EvaluationTimeUtc

        $report.Status | Should -Be 'SUCCEEDED'
        $report.ObservationCount | Should -Be 0
        $report.UnresolvedReferenceCount | Should -Be 2
        @($report.UnresolvedReasonCounts | Where-Object Reason -eq 'UnsafeOrMismatchedReference')[0].Count | Should -Be 1
        @($report.UnresolvedReasonCounts | Where-Object Reason -eq 'UnmatchedBinding')[0].Count | Should -Be 1
        $report.Comparer.ObservationCount | Should -Be 0
        $report.KnowledgeChangePlan | Should -BeNullOrEmpty
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $project.Root).Revision | Should -Be 3
    }

    It 'uses only an existing remote cache and reports cache absence without acquisition' {
        $project = New-ComparisonProject
        $mappedSourceId = Get-TestEpgSourceId -Name 'Remote Guide' -Kind remote
        $refreshSourceId = Get-TestRefreshSourceId -Name 'Remote Guide'
        $config = @{
            epg_sources = @(
                @{
                    name = ' Remote Guide '
                    priority = 1
                    url = 'https://example.invalid/guide.xml'
                    enabled = $true
                    role = 'primary'
                }
            )
        }
        [IO.File]::WriteAllText($project.ConfigPath, ($config | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        $sourceResult = @{
            SchemaVersion = 'source-refresh-result/v2'
            EvaluationTimeUtc = '2026-08-14T12:00:00Z'
            ReviewNeeded = $false
            ReviewNeededCount = 0
            Sources = @(
                @{
                    SourceId = $refreshSourceId
                    Name = 'Remote Guide'
                    Kind = 'remote'
                    PlannedAction = 'USE_VALID_CACHE'
                    Attempted = $false
                    Result = 'REUSED_VALID_CACHE'
                    Classification = 'AutoHandled'
                    ReasonCode = 'ReusedValidCache'
                    CacheChanged = $false
                    LastKnownGoodPreserved = $false
                    SafeReason = 'FreshCache'

                    ValidatorOutcome = 'NONE'
                }
            )
        }
        [IO.File]::WriteAllText($project.SourceResultPath, ($sourceResult | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        $cacheFilesBefore = @(Get-ChildItem -LiteralPath $project.CacheRoot -File -Recurse -ErrorAction SilentlyContinue).Count

        $report = Invoke-ComparisonFixture -Project $project -EvaluationTimeUtc ([datetimeoffset]'2026-08-14T12:00:00Z')

        $report.Status | Should -Be 'SUCCEEDED' -Because "adapter failure code was $($report.FailureCode)"
        $report.ObservationCount | Should -Be 0
        @($report.SourceAssessments | Where-Object { $_.SourceId -eq $mappedSourceId -and $_.ReasonCode -eq 'FreshCacheUnavailable' }).Count | Should -Be 1 -Because "assessments: $(ConvertTo-Json -InputObject $report.SourceAssessments -Compress -Depth 5)"
        $report.KnowledgeChangePlan | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $project.CacheRoot -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be $cacheFilesBefore
    }

    It 'does not persist alias evidence when redaction changes its context identity' {
        $project = New-ComparisonProject
        $evaluation = [datetimeoffset]'2026-08-14T12:00:00Z'
        $sources = @{
            epg_sources = @(
                @{ name='Guide One'; priority=1; url='https://example.invalid/one.xml'; enabled=$true; role='primary' },
                @{ name='Guide Two'; priority=2; url='https://example.invalid/two.xml'; enabled=$true; role='secondary' }
            )
        }
        [IO.File]::WriteAllText($project.ConfigPath, ($sources | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        Set-RemoteCacheFixture -Project $project -EvaluationTimeUtc $evaluation -SourceName 'Guide One' -Title 'Championship Alpha vs Beta https://example.invalid/event-one'
        Set-RemoteCacheFixture -Project $project -EvaluationTimeUtc $evaluation -SourceName 'Guide Two' -Channel 'station.two' -Title 'Alpha v Beta Championship https://example.invalid/event-two'
        $sourceResult = @{
            SchemaVersion = 'source-refresh-result/v2'
            EvaluationTimeUtc = $evaluation.ToUniversalTime().ToString('o')
            ReviewNeeded = $false
            ReviewNeededCount = 0
            Sources = @(
                foreach ($name in @('Guide One','Guide Two')) {
                    @{
                        SourceId = Get-TestRefreshSourceId -Name $name
                        Name = $name
                        Kind = 'remote'
                        PlannedAction = 'USE_VALID_CACHE'
                        Attempted = $false
                        Result = 'REUSED_VALID_CACHE'
                        Classification = 'AutoHandled'
                        ReasonCode = 'ReusedValidCache'
                        CacheChanged = $false
                        LastKnownGoodPreserved = $false
                        ValidatorOutcome = 'NONE'
                        SafeReason = 'Fresh cache reused.'
                    }
                }
            )
        }
        [IO.File]::WriteAllText($project.SourceResultPath, ($sourceResult | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Set-ApprovedTestBindings -Root $project.Root -BindingRows @(
            @{ Name='Guide One'; Kind='remote'; Reference='station.one' },
            @{ Name='Guide Two'; Kind='remote'; Reference='station.two' }
        )

        $report = Invoke-ComparisonFixture -Project $project -EvaluationTimeUtc $evaluation

        $report.Status | Should -Be 'SUCCEEDED'
        $report.Comparer.ContextualAliasProposals.Count | Should -BeGreaterThan 0
        $report.KnowledgeChangePlan | Should -BeNullOrEmpty
        (Get-ChannelForgeKnowledgeState -RepositoryRoot $project.Root).Revision | Should -Be 3
    }

    It 'uses the configured cache name when reusing a fresh remote guide' {
        $project = New-ComparisonProject
        $sourceName = 'Remote Guide'
        $evaluation = [datetimeoffset]'2026-08-14T12:00:00Z'
        $config = @{
            epg_sources = @(
                @{
                    name = $sourceName
                    priority = 1
                    url = 'https://example.invalid/guide.xml'
                    enabled = $true
                    role = 'primary'
                }
            )
        }
        [IO.File]::WriteAllText($project.ConfigPath, ($config | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Set-RemoteCacheFixture -Project $project -EvaluationTimeUtc $evaluation -SourceName $sourceName
        $sourceResult = @{
            SchemaVersion = 'source-refresh-result/v2'
            EvaluationTimeUtc = $evaluation.ToUniversalTime().ToString('o')
            ReviewNeeded = $false
            ReviewNeededCount = 0
            Sources = @(
                @{
                    SourceId = Get-TestRefreshSourceId -Name $sourceName
                    Name = $sourceName
                    Kind = 'remote'
                    PlannedAction = 'USE_VALID_CACHE'
                    Attempted = $false
                    Result = 'REUSED_VALID_CACHE'
                    Classification = 'AutoHandled'
                    ReasonCode = 'ReusedValidCache'
                    CacheChanged = $false
                    LastKnownGoodPreserved = $false
                    ValidatorOutcome = 'NONE'
                    SafeReason = 'Fresh cache reused.'
                }
            )
        }
        [IO.File]::WriteAllText($project.SourceResultPath, ($sourceResult | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Set-ApprovedTestBindings -Root $project.Root -BindingRows @(
            @{ Name=$sourceName; Kind='remote'; Reference='station.one' }
        )

        $report = Invoke-ComparisonFixture -Project $project -EvaluationTimeUtc $evaluation

        $report.Status | Should -Be 'SUCCEEDED'
        $report.ObservationCount | Should -Be 1
        $report.UnresolvedReferenceCount | Should -Be 0
        @($report.SourceAssessments | Where-Object { $_.GateStatus -eq 'Included' -and $_.ReasonCode -eq 'FreshCache' }).Count | Should -Be 1
        $report.SourceAssessments[0].Name | Should -Be 'Remote Guide'
        Should -Invoke Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -Times 1 -Exactly
    }

    It 'redacts contact addresses and compound credentials from local source assessments' {
        $project = New-ComparisonProject
        $fixture = Write-ComparisonFixture -Project $project
        $sourceName = 'ops@example.com API_TOKEN=fixture-secret Authorization=Basic dXNlcjpwYXNz'
        $config = Get-Content -LiteralPath $project.ConfigPath -Raw | ConvertFrom-Json
        $config.epg_sources[0].name = $sourceName
        [IO.File]::WriteAllText($project.ConfigPath, ($config | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        $sourceResult = Get-Content -LiteralPath $project.SourceResultPath -Raw | ConvertFrom-Json
        $sourceResult.Sources[0].Name = $sourceName
        [IO.File]::WriteAllText($project.SourceResultPath, ($sourceResult | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Set-ApprovedTestBindings -Root $project.Root -BindingRows @(
            @{ Name=$sourceName; Kind='local'; Reference='station.one'; ChannelId='channel-one' },
            @{ Name='Guide Two'; Kind='local'; Reference='station.two'; ChannelId='channel-two' }
        )

        $report = Invoke-ComparisonFixture -Project $project -EvaluationTimeUtc $fixture.EvaluationTimeUtc

        $report.Status | Should -Be 'SUCCEEDED'
        $sourceId = Get-TestEpgSourceId -Name $sourceName -Kind local
        $assessment = @($report.SourceAssessments | Where-Object SourceId -eq $sourceId)[0]
        $assessment.Name | Should -Not -Match 'ops@example\.com|fixture-secret|dXNlcjpwYXNz|API_TOKEN|Authorization|Basic'
    }
    It 'fails the scheduled comparison instead of processing more than 256 parsed programmes' {
        $project = New-ComparisonProject
        $fixture = Write-ComparisonFixture -Project $project
        $guidePath = Join-Path (Split-Path -Parent $project.ConfigPath) 'guide-one.xml'
        $guideXml = Get-Content -LiteralPath $guidePath -Raw
        $extraProgrammes = for ($index = 0; $index -lt 256; $index++) {
            "<programme start=`"20260101130000 +0000`" stop=`"20260101140000 +0000`" channel=`"station.one`"><title>Extra $index</title></programme>"
        }
        $guideXml = $guideXml.Replace('</tv>', (($extraProgrammes -join '') + '</tv>'))
        [IO.File]::WriteAllText($guidePath,$guideXml,[Text.UTF8Encoding]::new($false))

        $report = Invoke-ComparisonFixture -Project $project -EvaluationTimeUtc $fixture.EvaluationTimeUtc

        $report.Status | Should -Be 'FAILED'
        $report.FailureCode | Should -Be 'ComparisonFailed'
        $report.KnowledgeChangePlan | Should -BeNullOrEmpty
    }
}
