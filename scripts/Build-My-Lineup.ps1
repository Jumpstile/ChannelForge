[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$M3UPath,
    [string]$XMLTVPath,
    [ValidateSet('KeepWithoutGuide', 'Cancel')]
    [string]$AmbiguousAction,
    [switch]$Accept,
    [Alias('EventPreview')]
    [switch]$EventPatternPreview,
    [Alias('EventExamples')]
    [AllowEmptyCollection()]
    [string[]]$EventPatternExamples = @(),
    [AllowNull()]
    [object[]]$EventPatternEvidence = @(),
    [ValidateSet('Fight', 'PPV', 'TemporaryEvent', 'League', 'SingleTeam', 'StreamingEvent', 'Sports', 'Other', 'Unknown')]
    [string]$EventPatternType = 'Unknown',
    [ValidateSet('DisplayName', 'TvgName', 'OriginalName')]
    [string]$EventPatternInputField = 'DisplayName',
    [AllowEmptyString()]
    [string]$EventPatternGroup = '',
    [AllowNull()]
    [System.Collections.IDictionary]$EventPatternTimezoneMap = [ordered]@{ UTC = '+00:00' },
    [AllowEmptyString()]
    [string]$EventPatternDefaultTimezone = '',
    [AllowNull()]
    [Nullable[datetimeoffset]]$EventPatternReferenceInstantUtc,
    [ValidateSet('MonthFirst', 'DayFirst')]
    [string]$EventPatternDateOrder = 'MonthFirst',
    [ValidateRange(2, 50)]
    [int]$EventPatternMinimumExamples = 3,
    [AllowNull()]
    [object]$EventPatternExistingRule = $null,
    [string]$OutputRoot,
    [string]$FaultHook = '',
    [string]$ExpectedCandidateManifestHash,
    [string]$ExpectedBuildIdentity,
    [string]$ExpectedParentGenerationManifestHash,
    [switch]$PlanOnly,
    [switch]$MachineResult
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\src\ChannelForge\ChannelForge.psd1'
Import-Module $modulePath -Force
$module = Get-Module -Name ChannelForge | Select-Object -First 1

function Invoke-ChannelForgePrivate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Arguments
    )

    if ($null -eq $module) {
        throw 'ChannelForge module is not loaded.'
    }

    return @(& $module {
            param($privateName, $privateArguments)
            & $privateName @privateArguments
        } $Name $Arguments)
}

function Get-SafeWorkflowMessage {
    param([AllowNull()][object]$Message)

    $text = if ($null -eq $Message) { '' } else { ([string]$Message).Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) { return 'The requested workflow step could not be completed.' }
    if ($text -match '(?i)(https?://|ftp://|file://|[a-z]:[\\/]|^\\\\|ACCOUNT_ID|API_TOKEN|PASSWORD|TOKEN|SECRET)') {
        return 'The requested workflow step could not be completed.'
    }
    return $text
}

function Write-WorkflowReport {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Report
    )

    $reportDirectory = Join-Path $Root 'output\reports'
    Assert-ChannelForgeWritePath -Path $reportDirectory -AllowedRoot (Join-Path $Root 'output')
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
    $jsonPath = Join-Path $reportDirectory 'guided-setup-summary.json'
    $markdownPath = Join-Path $reportDirectory 'guided-setup-plan.md'
    Assert-ChannelForgeWritePath -Path $jsonPath -AllowedRoot (Join-Path $Root 'output')
    Assert-ChannelForgeWritePath -Path $markdownPath -AllowedRoot (Join-Path $Root 'output')

    $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $lines = @(
        '# ChannelForge Guided Setup'
        ''
        "Status: $($Report.Status)"
        "Channels: $($Report.ChannelCount)"
        "Guide: $($Report.GuideStatus)"
        "Exact guide matches: $($Report.ExactGuideMatchCount)"
        "Needs your choice: $($Report.AmbiguityCount)"
        "Guide-only records: $($Report.GuideOnlyCount)"
        if ($Report.EventPatternPreview.Enabled) {
            "Event-pattern preview: $($Report.EventPatternPreview.Status)"
            "Event-pattern inference ran: $($Report.EventPatternPreview.InferenceRan.ToString().ToLowerInvariant())"
            "Event-pattern review state: $($Report.EventPatternPreview.ReviewState)"
            "Event-pattern report: $($Report.EventPatternPreview.Output.MarkdownPath)"
            'Event-pattern preview never publishes a guide or changes accepted state.'
        }
        if ($null -ne $Report.ConsumerM3UPath) { "M3U lineup: $($Report.ConsumerM3UPath)" }
        if ($null -ne $Report.ConsumerXMLTVPath) { "XMLTV guide: $($Report.ConsumerXMLTVPath)" }
        ''
        ''
        "What happened: $($Report.WhatHappened)"
        "Preserved: $($Report.Preserved)"
        "Changed: $($Report.Changed)"
        "Next: $($Report.Next)"
    )
    $lines -join "`n" | Set-Content -LiteralPath $markdownPath -Encoding UTF8

    return [pscustomobject][ordered]@{
        SummaryPath = [System.IO.Path]::GetRelativePath($Root, $jsonPath).Replace('\', '/')
        PlanPath = [System.IO.Path]::GetRelativePath($Root, $markdownPath).Replace('\', '/')
    }
}
function Write-WorkflowConsumerOutputs {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][byte[]]$M3UBytes,
        [AllowNull()][byte[]]$XMLTVBytes,
        [string]$FaultHook = ''
    )

    $directory = Join-Path $Root 'output\guided-setup'
    Assert-ChannelForgeWritePath -Path $directory -AllowedRoot (Join-Path $Root 'output')
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $liveDirectory = Join-Path $directory 'accepted'
    $previousDirectory = Join-Path $directory 'accepted.previous'
    $stagingDirectory = Join-Path $directory ('.accepted-' + [guid]::NewGuid().ToString('N'))
    $m3uPath = Join-Path $liveDirectory 'lineup.m3u'
    $xmltvPath = Join-Path $liveDirectory 'guide.xml'

    New-Item -ItemType Directory -Force -Path $stagingDirectory | Out-Null
    try {
        [IO.File]::WriteAllBytes((Join-Path $stagingDirectory 'lineup.m3u'), $M3UBytes)
        if ($null -ne $XMLTVBytes) { [IO.File]::WriteAllBytes((Join-Path $stagingDirectory 'guide.xml'), $XMLTVBytes) }
        if ($FaultHook -eq 'ConsumerView.BeforeSwap') { throw 'Stable consumer view refresh fault injected before swap.' }
        if (Test-Path -LiteralPath $previousDirectory -PathType Container) { Remove-Item -LiteralPath $previousDirectory -Recurse -Force }
        if (Test-Path -LiteralPath $liveDirectory -PathType Container) { [IO.Directory]::Move($liveDirectory, $previousDirectory) }
        try {
            [IO.Directory]::Move($stagingDirectory, $liveDirectory)
        }
        catch {
            if (-not (Test-Path -LiteralPath $liveDirectory -PathType Container) -and (Test-Path -LiteralPath $previousDirectory -PathType Container)) {
                [IO.Directory]::Move($previousDirectory, $liveDirectory)
            }
            throw
        }

        return [pscustomobject][ordered]@{
            M3UPath = [IO.Path]::GetRelativePath($Root, $m3uPath).Replace('\', '/')
            XMLTVPath = if ($null -eq $XMLTVBytes) { $null } else { [IO.Path]::GetRelativePath($Root, $xmltvPath).Replace('\', '/') }
        }
    }
    finally {
        if (Test-Path -LiteralPath $stagingDirectory -PathType Container) { Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
function New-WorkflowEventPatternPreviewReport {
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [Parameter(Mandatory)][bool]$InferenceRan,
        [AllowNull()][object]$Review,
        [AllowEmptyString()][string]$State = 'NotRun',
        [AllowEmptyString()][string]$Reason = ''
    )

    if (-not $Enabled) {
        return [ordered]@{
            Version = 'guided-setup/event-pattern-preview/v1'
            Enabled = $false
            InferenceRan = $false
            Status = 'DISABLED'
            State = 'NotRun'
            ReviewState = 'NotRun'
            RepresentativePattern = $null
            Confidence = $null
            Review = $null
            Drift = $null
            Usability = [ordered]@{
                ForReview = $false
                ForAutomaticUse = $false
                Blocked = $true
                Reason = 'Event-pattern preview was not requested.'
            }
            Safety = [ordered]@{
                PublicationState = 'CandidateOnly'
                CanPublish = $false
                PromotionRequired = 'ExplicitAcceptance'
                AcceptedStateMutation = 'None'
                ProviderMutation = $false
                DownstreamMutation = $false
                FilesystemMutation = $false
                RedactionApplied = $true
            }
            Output = $null
        }
    }

    if ($null -eq $Review) {
        $reasonCode = if ([string]::IsNullOrWhiteSpace($State) -or $State -eq 'NeedsReview') { 'InsufficientExamples' } else { $State }
        return [ordered]@{
            Version = 'guided-setup/event-pattern-preview/v1'
            Enabled = $true
            InferenceRan = $InferenceRan
            Status = 'BLOCKED'
            State = $State
            ReviewState = $State
            RepresentativePattern = $null
            Confidence = [ordered]@{ State = 'NeedsReview'; Score = 0 }
            Review = [ordered]@{
                Required = $true
                Reasons = @([ordered]@{ Code = $reasonCode; Message = $Reason })
                PlainLanguage = $Reason
            }
            Drift = [ordered]@{ Status = 'NotEvaluated'; ReviewOnly = $true; Adoption = 'NotApplied' }
            Usability = [ordered]@{
                ForReview = $false
                ForAutomaticUse = $false
                Blocked = $true
                Reason = $Reason
            }
            Safety = [ordered]@{
                PublicationState = 'CandidateOnly'
                CanPublish = $false
                PromotionRequired = 'ExplicitAcceptance'
                AcceptedStateMutation = 'None'
                ProviderMutation = $false
                DownstreamMutation = $false
                FilesystemMutation = $false
                RedactionApplied = $true
            }
            Output = [ordered]@{
                JsonPath = 'output/reports/guided-event-pattern-preview.json'
                MarkdownPath = 'output/reports/guided-event-pattern-preview.md'
                TextPath = 'output/reports/guided-event-pattern-preview.txt'
            }
        }
    }

    $reviewState = [string]$Review.Summary.State
    $reviewable = $reviewState -in @('Confirmed', 'SafeCandidate')
    $blocked = $reviewState -in @('NeedsReview', 'Unresolved', 'Contradiction', 'StaleSource', 'SourceUnavailable')
    $reasonText = if ($blocked) { [string]$Review.Review.PlainLanguage } else { 'The event pattern is useful for review but cannot be adopted automatically.' }
    return [ordered]@{
        Version = 'guided-setup/event-pattern-preview/v1'
        Enabled = $true
        InferenceRan = $InferenceRan
        Status = if ($blocked) { 'BLOCKED' } else { 'PREVIEW_READY' }
        State = $reviewState
        ReviewState = $reviewState
        RepresentativePattern = [string]$Review.Pattern.Description
        Confidence = $Review.Confidence
        Review = $Review.Review
        Drift = $Review.Drift
        Event = $Review.Event
        Fields = @($Review.Fields)
        Provenance = $Review.Provenance
        Usability = [ordered]@{
            ForReview = $reviewable
            ForAutomaticUse = $false
            Blocked = $blocked
            Reason = $reasonText
        }
        Safety = [ordered]@{
            PublicationState = 'CandidateOnly'
            CanPublish = $false
            PromotionRequired = 'ExplicitAcceptance'
            AcceptedStateMutation = 'None'
            ProviderMutation = $false
            DownstreamMutation = $false
            FilesystemMutation = $false
            RedactionApplied = $true
        }
        Output = [ordered]@{
            JsonPath = 'output/reports/guided-event-pattern-preview.json'
            MarkdownPath = 'output/reports/guided-event-pattern-preview.md'
            TextPath = 'output/reports/guided-event-pattern-preview.txt'
        }
    }
}

function Write-WorkflowEventPatternPreviewReports {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object]$Report,
        [AllowNull()][object]$InferenceResult,
        [AllowNull()][object]$Review
    )

    $directory = Join-Path $Root 'output\reports'
    Assert-ChannelForgeWritePath -Path $directory -AllowedRoot (Join-Path $Root 'output')
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $jsonPath = Join-Path $directory 'guided-event-pattern-preview.json'
    $markdownPath = Join-Path $directory 'guided-event-pattern-preview.md'
    $textPath = Join-Path $directory 'guided-event-pattern-preview.txt'
    foreach ($path in @($jsonPath, $markdownPath, $textPath)) {
        Assert-ChannelForgeWritePath -Path $path -AllowedRoot (Join-Path $Root 'output')
    }

    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $json = $Report | ConvertTo-Json -Depth 20 -Compress
    $markdown = if ($null -eq $Review) {
        @(
            '# ChannelForge event-pattern preview'
            ''
            '**Status:** BLOCKED'
            ''
            'ChannelForge did not run event-pattern inference because more representative event-channel examples are needed.'
            ''
            '**Safety:** This preview is CandidateOnly, cannot publish, and did not change accepted state, provider state, downstream state, or guide output.'
        ) -join "`n"
    }
    else {
        Get-ChannelForgeGuidePatternReview -InferenceResult $InferenceResult -OutputFormat Markdown
    }
    $confidenceText = if ($null -eq $Report.Confidence) {
        'Not evaluated.'
    }
    else {
        "$($Report.Confidence.State) ($($Report.Confidence.Score)/100)"
    }
    $patternText = if ([string]::IsNullOrWhiteSpace([string]$Report.RepresentativePattern)) {
        'Not detected.'
    }
    else {
        [string]$Report.RepresentativePattern
    }
    $driftText = if ($null -eq $Report.Drift) { 'Not evaluated.' } else { [string]$Report.Drift.Status }
    $text = @(
        'ChannelForge event-pattern preview'
        ''
        "Inference ran: $($Report.InferenceRan.ToString().ToLowerInvariant())"
        "Review state: $($Report.ReviewState)"
        "Representative pattern: $patternText"
        "Confidence: $confidenceText"
        "Usable for review: $($Report.Usability.ForReview.ToString().ToLowerInvariant())"
        'Usable for automatic adoption: false'
        "Why: $($Report.Usability.Reason)"
        "Drift: $driftText"
        ''
        'Safety boundary: CandidateOnly; CanPublish=false; PromotionRequired=ExplicitAcceptance; AcceptedStateMutation=None.'
        'No guide was published. Accepted state, provider state, and downstream state did not change.'
        'Sensitive source values and raw examples were redacted from this report.'
    ) -join "`n"
    [IO.File]::WriteAllText($jsonPath, $json, $encoding)
    [IO.File]::WriteAllText($markdownPath, $markdown + "`n", $encoding)
    [IO.File]::WriteAllText($textPath, $text + "`n", $encoding)
    return [pscustomobject][ordered]@{
        JsonPath = [IO.Path]::GetRelativePath($Root, $jsonPath).Replace('\', '/')
        MarkdownPath = [IO.Path]::GetRelativePath($Root, $markdownPath).Replace('\', '/')
        TextPath = [IO.Path]::GetRelativePath($Root, $textPath).Replace('\', '/')
    }
}


function Resolve-WorkflowInput {
    param(
        [AllowNull()][string]$Path,
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$Optional
    )

    $value = if ([string]::IsNullOrWhiteSpace($Path)) { Read-Host $Prompt } else { $Path }
    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($Optional) { return $null }
        throw 'An IPTV playlist is required.'
    }

    $full = [System.IO.Path]::GetFullPath($value)
    Assert-ChannelForgePathExists -Path $full -PathType Leaf -Description 'Selected input file'
    return $full
}

function Copy-WorkflowInput {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$DestinationDirectory,
        [Parameter(Mandatory)][string]$Label
    )

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $extension = [System.IO.Path]::GetExtension($Path)
    if ([string]::IsNullOrWhiteSpace($extension)) { $extension = '.data' }
    $destination = Join-Path $DestinationDirectory ("{0}-{1}{2}" -f $Label, $hash, $extension)
    New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Force
    return $destination
}

function Get-WorkflowCandidateFile {
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [Parameter(Mandatory)][string]$Name
    )

    $path = Join-Path $CandidateDirectory $Name
    Assert-ChannelForgePathExists -Path $path -PathType Leaf -Description "Candidate $Name"
    return $path
}

function New-WorkflowDecision {
    param(
        [Parameter(Mandatory)][string]$DecisionType,
        [AllowNull()][string]$CandidateEntryId,
        [AllowNull()][string]$BindingId,
        [Parameter(Mandatory)][string]$ReasonCode
    )

    $base = [ordered]@{
        Version = 'blocker-2-contract/v8-acceptance'
        DecisionType = $DecisionType
        CandidateEntryId = $CandidateEntryId
        BindingId = $BindingId
        ReasonCode = $ReasonCode
        ReviewStatus = 'Resolved'
    }
    $decisionId = [string](Invoke-ChannelForgePrivate -Name 'Get-ChannelForgeDomainHash' -Arguments @{
            Domain = 'decision-manifest/v2'
            InputObject = $base
        } | Select-Object -Last 1)
    $base.DecisionId = $decisionId
    return [pscustomobject]$base
}

function Get-WorkflowAcceptedM3UBytes {
    param(
        [Parameter(Mandatory)][byte[]]$CandidateBytes,
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string[]]$IncludedEntryIds
    )

    $entryById = @{}
    foreach ($entry in $Entries) { $entryById[[string]$entry.EntryId] = $entry }
    $selected = @($IncludedEntryIds | ForEach-Object {
            if (-not $entryById.ContainsKey([string]$_)) { throw 'Candidate entry selection is incomplete.' }
            $entryById[[string]$_]
        } | Sort-Object { [int64]$_.EntryOutputSlice.ByteOffset })
    if ($selected.Count -eq 0) { throw 'At least one channel must remain in the accepted lineup.' }

    $newline = [Array]::IndexOf($CandidateBytes, [byte]10)
    if ($newline -lt 0) { throw 'Candidate M3U header is invalid.' }
    $stream = [IO.MemoryStream]::new()
    try {
        $stream.Write($CandidateBytes, 0, $newline + 1)
        foreach ($entry in $selected) {
            $slice = $entry.EntryOutputSlice
            $offset = [int64]$slice.ByteOffset
            $length = [int64]$slice.ByteLength
            if ($offset -lt 0 -or $length -le 0 -or $offset + $length -gt $CandidateBytes.Length) {
                throw 'Candidate entry slice is invalid.'
            }
            $stream.Write($CandidateBytes, [int]$offset, [int]$length)
        }
        return [byte[]]$stream.ToArray()
    }
    finally {
        $stream.Dispose()
    }
}

function Get-WorkflowCurrentSnapshot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $paths = Invoke-ChannelForgePrivate -Name 'Get-ChannelForgeGenerationPaths' -Arguments @{ RepositoryRoot = $RepositoryRoot } | Select-Object -Last 1
    if (-not (Test-Path -LiteralPath $paths.Current -PathType Leaf)) { return $null }
    return @(Invoke-ChannelForgePrivate -Name 'Get-ChannelForgeGenerationCurrentSnapshot' -Arguments @{
            RepositoryRoot = $RepositoryRoot
            Paths = $paths
        } | Select-Object -Last 1)[0]
}

function Publish-WorkflowAcceptedCandidate {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$CandidateManifest,
        [Parameter(Mandatory)][byte[]]$M3UBytes,
        [AllowNull()][byte[]]$XMLTVBytes,
        [Parameter(Mandatory)][object[]]$DecisionRecords,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$IncludedEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExcludedEntryIds,
        [Parameter(Mandatory)][AllowNull()]$PriorSnapshot
    )

    $candidateHash = [string]$CandidateManifest.CandidateManifestHash
    $buildIdentity = [string]$CandidateManifest.BuildIdentity
    $priorManifestHash = if ($null -eq $PriorSnapshot) { $null } else { [string]$PriorSnapshot.Manifest.Object.GenerationManifestHash }
    $parentStateHash = if ($null -eq $PriorSnapshot) { $null } else { [string]$PriorSnapshot.State.Object.AcceptedStateHash }
    $parentOutputHash = if ($null -eq $PriorSnapshot) { $null } else { [string]$PriorSnapshot.Output.Object.OutputManifestHash }
    $parentGenerationManifestHash = $priorManifestHash

    $decisionM3U = Invoke-ChannelForgePrivate -Name 'New-ChannelForgeDecisionM3U' -Arguments @{
        CandidateManifestHash = $candidateHash
        BuildIdentity = $buildIdentity
        AcceptedParentGenerationManifestHash = $parentGenerationManifestHash
        IncludedCandidateEntryIds = @($IncludedEntryIds | Sort-Object)
        ExcludedCandidateEntryIds = @($ExcludedEntryIds | Sort-Object)
        DecisionIds = @($DecisionRecords | Sort-Object @{ Expression = { if ($_.DecisionType -eq 'AcceptGuideBinding') { 0 } elseif ($_.DecisionType -eq 'IncludeCandidateEntry') { 3 } else { 4 } } }, DecisionId | ForEach-Object DecisionId)
    } | Select-Object -Last 1

    $xmltvStatus = if ($null -eq $XMLTVBytes) { 'NotGenerated' } else { 'Generated' }
    $decisionXMLTV = if ($xmltvStatus -eq 'Generated') {
        Invoke-ChannelForgePrivate -Name 'New-ChannelForgeDecisionXMLTV' -Arguments @{
            CandidateManifestHash = $candidateHash
            BuildIdentity = $buildIdentity
            AcceptedParentGenerationManifestHash = $parentGenerationManifestHash
            AcceptedXMLTVStatus = 'Generated'
            IncludedCandidateEntryIds = @($decisionM3U.IncludedCandidateEntryIds)
            ExcludedCandidateEntryIds = @($decisionM3U.ExcludedCandidateEntryIds)
            DecisionIds = @($decisionM3U.DecisionIds)
        } | Select-Object -Last 1
    }
    else { $null }

    $decisionManifest = Invoke-ChannelForgePrivate -Name 'New-ChannelForgeDecisionManifest' -Arguments @{
        CandidateManifestHash = $candidateHash
        BuildIdentity = $buildIdentity
        M3UDecision = $decisionM3U
        XMLTVDecision = $decisionXMLTV
        XMLTVDecisionStatus = $xmltvStatus
    } | Select-Object -Last 1

    # Consume the existing acceptance boundary before constructing the immutable
    # publication graph. It performs complete candidate/decision coverage checks.
    $acceptance = New-ChannelForgeAcceptance `
        -CandidateManifest $CandidateManifest `
        -DecisionManifest $decisionManifest `
        -M3UDecision $decisionM3U `
        -DecisionRecords $DecisionRecords

    $activeM3UHash = [string](Invoke-ChannelForgePrivate -Name 'Get-ChannelForgeDomainHash' -Arguments @{ Domain = 'active-m3u/v2'; Bytes = $M3UBytes } | Select-Object -Last 1)
    $activeXMLTVHash = if ($null -eq $XMLTVBytes) { $null } else { [string](Invoke-ChannelForgePrivate -Name 'Get-ChannelForgeDomainHash' -Arguments @{ Domain = 'active-xmltv/v2'; Bytes = $XMLTVBytes } | Select-Object -Last 1) }
    $generationId = [string](Invoke-ChannelForgePrivate -Name 'Get-ChannelForgeDomainHash' -Arguments @{
            Domain = 'generation-id/v2'
            InputObject = [ordered]@{ CandidateManifestHash = $candidateHash; BuildIdentity = $buildIdentity; DecisionManifestHash = [string]$decisionManifest.DecisionManifestHash; Nonce = ([guid]::NewGuid().ToString('N')) }
        } | Select-Object -Last 1)
    $acceptedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

    $acceptedOutputManifest = Invoke-ChannelForgePrivate -Name 'New-ChannelForgeAcceptedOutputManifest' -Arguments @{
        GenerationId = $generationId
        ActiveM3UHash = $activeM3UHash
        ActiveXMLTVStatus = $xmltvStatus
        ActiveXMLTVHash = $activeXMLTVHash
        AcceptedStateHash = ('0' * 64)
    } | Select-Object -Last 1
    $acceptedState = Invoke-ChannelForgePrivate -Name 'New-ChannelForgeAcceptedState' -Arguments @{
        GenerationId = $generationId
        BuildIdentity = $buildIdentity
        CandidateManifestHash = $candidateHash
        DecisionManifestHash = [string]$decisionManifest.DecisionManifestHash
        AcceptedOutputManifestHash = [string]$acceptedOutputManifest.OutputManifestHash
        PreviousStateHash = $parentStateHash
        IncludedCandidateEntryIds = @($decisionM3U.IncludedCandidateEntryIds)
        ExcludedCandidateEntryIds = @($decisionM3U.ExcludedCandidateEntryIds)
        AcceptedBindingIds = @($decisionM3U.DecisionIds)
        AcceptedXMLTVStatus = $xmltvStatus
        AcceptedAtUtc = $acceptedAtUtc
    } | Select-Object -Last 1
    $acceptedOutputManifest.AcceptedStateHash = [string]$acceptedState.AcceptedStateHash

    $generationManifest = [ordered]@{
        Version = 'blocker-2-contract/v8-acceptance'
        GenerationId = $generationId
        BuildIdentity = $buildIdentity
        CandidateManifestHash = $candidateHash
        DecisionManifestHash = [string]$decisionManifest.DecisionManifestHash
        AcceptedStateHash = [string]$acceptedState.AcceptedStateHash
        AcceptedOutputManifestHash = [string]$acceptedOutputManifest.OutputManifestHash
        ActiveM3UHash = $activeM3UHash
        ActiveXMLTVHash = $activeXMLTVHash
        PreviousOutputManifestHash = $parentOutputHash
        GenerationManifestHash = $null
    }
    $generationManifest.GenerationManifestHash = [string](Invoke-ChannelForgePrivate -Name 'Get-ChannelForgeAcceptanceHash' -Arguments @{
            Domain = 'generation-manifest/v2'
            Projection = $generationManifest
            HashProperty = 'GenerationManifestHash'
            Omit = @('GenerationId')
        } | Select-Object -Last 1)

$publishArguments = @{
    RepositoryRoot = $RepositoryRoot
    GenerationManifest = [pscustomobject]$generationManifest
    AcceptedState = $acceptedState
    AcceptedOutputManifest = $acceptedOutputManifest
    DecisionManifest = $decisionManifest
    M3UBytes = $M3UBytes
    XMLTVBytes = $XMLTVBytes
}
if (-not [string]::IsNullOrWhiteSpace($FaultHook)) { $publishArguments.FaultHook = $FaultHook }
$publish = Publish-ChannelForgeAcceptedGeneration @publishArguments

    return [pscustomobject][ordered]@{
        Publish = $publish
        Acceptance = $acceptance
        GenerationId = $generationId
        GenerationManifest = [pscustomobject]$generationManifest
        AcceptedState = $acceptedState
        AcceptedOutputManifest = $acceptedOutputManifest
        DecisionManifest = $decisionManifest
    }
}

$report = [ordered]@{
    Version = 'guided-setup/v1'
    Status = 'FAILED'
    ChannelCount = 0
    ExactGuideMatchCount = 0
    AmbiguityCount = 0
    GuideOnlyCount = 0
    GuideStatus = 'NOT_SELECTED'
    EventPatternPreview = New-WorkflowEventPatternPreviewReport -Enabled:$false -InferenceRan:$false -Review $null
    ConsumerM3UPath = $null
    ConsumerXMLTVPath = $null
    WhatHappened = $null
    Preserved = 'No accepted output was changed.'
    Changed = 'No accepted output was changed.'
    Next = 'Correct the input and run Build-My-Lineup.ps1 again.'
}
if ($EventPatternPreview) {
    $report.EventPatternPreview = New-WorkflowEventPatternPreviewReport `
        -Enabled:$true `
        -InferenceRan:$false `
        -Review $null `
        -State 'NeedsReview' `
        -Reason 'Event-pattern preview is report-only and cannot be combined with -Accept.'
}
$machineCandidateManifestHash = $null
$machineBuildIdentity = $null
$machineParentGenerationManifestHash = $null
$machineAcceptedEntryCount = $null
$prior = $null
$stagedInputs = @()
$acceptedPublicationCompleted = $false
$acceptedGenerationChanged = $false
$eventInference = $null
$eventReview = $null
$consumerViewRefreshCompleted = $false
try {
    Write-Host 'ChannelForge Guided Setup' -ForegroundColor Cyan
    Write-Host '1. Add your IPTV playlist (M3U).' -ForegroundColor Gray
    $playlist = Resolve-WorkflowInput -Path $M3UPath -Prompt 'Playlist path'
    Write-Host '2. Add a TV guide (XMLTV), or press Enter for no guide.' -ForegroundColor Gray
    $guide = Resolve-WorkflowInput -Path $XMLTVPath -Prompt 'Guide path (optional)' -Optional
    $report.GuideStatus = if ($null -eq $guide) { 'NO_GUIDE_SELECTED' } else { 'XMLTV_SELECTED' }

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    if ($EventPatternPreview -and $Accept) {
        throw 'Event-pattern preview is report-only; do not combine it with -Accept. No guide or accepted state can be changed by this step.'
    }
    $outputFull = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
        [System.IO.Path]::GetFullPath((Join-Path $rootFull 'output\\guided-setup'))
    }
    else {
        [System.IO.Path]::GetFullPath($OutputRoot)
    }
    Assert-ChannelForgeWritePath -Path $outputFull -AllowedRoot (Join-Path $rootFull 'output')
    $inputDirectory = Join-Path $outputFull 'inputs'
    $stagedInputs += Copy-WorkflowInput -Path $playlist -DestinationDirectory $inputDirectory -Label 'playlist'
    if ($null -ne $guide) { $stagedInputs += Copy-WorkflowInput -Path $guide -DestinationDirectory $inputDirectory -Label 'guide' }

    Write-Host '3. Build My Lineup: analyzing channels and guide identity.' -ForegroundColor Cyan
    $candidateXmltvInput = if ($null -eq $guide) { $null } else { $stagedInputs[1] }

    $candidateScript = Join-Path $PSScriptRoot 'Build-Candidate.ps1'
    $candidateResult = @(& $candidateScript `
        -Root $rootFull `
        -M3UPath $stagedInputs[0] `
        -XMLTVPath $candidateXmltvInput `
        -OutputRoot $outputFull `
        -CandidateContractVersion 'blocker-2-contract/v8' `
        -FaultHook $FaultHook) | Select-Object -Last 1
    if ($candidateResult.Count -eq 0 -or $null -eq $candidateResult[0].CandidateDirectory) { throw 'Candidate build did not return a candidate artifact.' }
    $candidateDirectory = [System.IO.Path]::GetFullPath([string]$candidateResult[0].CandidateDirectory)
    $manifestPath = Get-WorkflowCandidateFile -CandidateDirectory $candidateDirectory -Name 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $machineCandidateManifestHash = [string]$manifest.CandidateManifestHash
    $machineBuildIdentity = [string]$manifest.BuildIdentity
    if (($PSBoundParameters.ContainsKey('ExpectedCandidateManifestHash') -and
         $machineCandidateManifestHash -cne [string]$ExpectedCandidateManifestHash) -or
        ($PSBoundParameters.ContainsKey('ExpectedBuildIdentity') -and
         $machineBuildIdentity -cne [string]$ExpectedBuildIdentity)) {
        $report.Status = 'STALE'
        if ($MachineResult) { return }
        throw 'The candidate is no longer current; nothing was published.'
    }
    $candidateM3UPath = Get-WorkflowCandidateFile -CandidateDirectory $candidateDirectory -Name 'merged.m3u'
    [byte[]]$candidateM3UBytes = [IO.File]::ReadAllBytes($candidateM3UPath)
    $candidateXMLTVPath = Join-Path $candidateDirectory 'merged.xml'
    [byte[]]$candidateXMLTVBytes = if (Test-Path -LiteralPath $candidateXMLTVPath -PathType Leaf) { [IO.File]::ReadAllBytes($candidateXMLTVPath) } else { $null }

    $report.ChannelCount = @($manifest.Entries).Count
    if ($report.ChannelCount -eq 0) {
        throw 'No channels were found in the IPTV playlist.'
    }
    $m3uBindings = @($manifest.BindingRecords | Where-Object { [string]$_.BindingKind -eq 'M3U' })
    $report.ExactGuideMatchCount = @($m3uBindings | Where-Object { [string]$_.Status -eq 'ExactBound' }).Count
    $report.AmbiguityCount = @($m3uBindings | Where-Object { [string]$_.Status -eq 'ReviewNeeded' }).Count
    $report.GuideOnlyCount = @($manifest.BindingRecords | Where-Object { [string]$_.BindingKind -eq 'XMLTVOnly' }).Count
    if ($null -eq $guide) {

        $report.ExactGuideMatchCount = 0
        $report.AmbiguityCount = 0
        $report.GuideOnlyCount = 0
    }
    if ($EventPatternPreview) {
        Write-Host '4. Previewing event-channel naming intelligence (report only).' -ForegroundColor Cyan
        $evidence = @($EventPatternEvidence)
        $examples = @($EventPatternExamples | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim() })
        if ($evidence.Count -eq 0 -and $examples.Count -eq 0 -and
            -not $PSBoundParameters.ContainsKey('EventPatternExamples') -and
            -not $PSBoundParameters.ContainsKey('EventPatternEvidence')) {
            $pasted = Read-Host 'Paste representative event-channel names separated by "|" (or press Enter to review later)'
            if (-not [string]::IsNullOrWhiteSpace($pasted)) {
                $examples = @($pasted -split '\s*\|\s*' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim() })
            }
        }

        $inputCount = if ($evidence.Count -gt 0) { $evidence.Count } else { $examples.Count }
        if ($inputCount -lt $EventPatternMinimumExamples) {
            $eventReport = New-WorkflowEventPatternPreviewReport `
                -Enabled:$true `
                -InferenceRan:$false `
                -Review $null `
                -State 'NeedsReview' `
                -Reason "Provide at least $EventPatternMinimumExamples representative event-channel examples or evidence records so ChannelForge can compare one pattern safely."
        }
        else {
            try {
                $inferenceArguments = @{
                    EventType = $EventPatternType
                    InputField = $EventPatternInputField
                    TimezoneMap = $EventPatternTimezoneMap
                    DefaultTimezone = $EventPatternDefaultTimezone
                    ReferenceInstantUtc = $EventPatternReferenceInstantUtc
                    DateOrder = $EventPatternDateOrder
                    MinimumExamples = $EventPatternMinimumExamples
                    ExistingRule = $EventPatternExistingRule
                }
                if ($evidence.Count -gt 0) {
                    $inferenceArguments.Evidence = $evidence
                }
                else {
                    $inferenceArguments.Examples = $examples
                    $inferenceArguments.Group = $EventPatternGroup
                }
                $eventInference = Invoke-ChannelForgeGuidePatternInference @inferenceArguments
                $eventReview = Get-ChannelForgeGuidePatternReview -InferenceResult $eventInference
                $eventReport = New-WorkflowEventPatternPreviewReport `
                    -Enabled:$true `
                    -InferenceRan:$true `
                    -Review $eventReview
            }
            catch {
                $eventReport = New-WorkflowEventPatternPreviewReport `
                    -Enabled:$true `
                    -InferenceRan:$true `
                    -Review $null `
                    -State 'SourceUnavailable' `
                    -Reason 'ChannelForge could not safely analyze the supplied event-channel examples. No event pattern was trusted.'
            }
        }
        $eventFiles = Write-WorkflowEventPatternPreviewReports -Root $rootFull -Report $eventReport -InferenceResult $eventInference -Review $eventReview
        $report.EventPatternPreview = $eventReport
        Write-Host "Event-pattern preview: $($eventFiles.MarkdownPath)" -ForegroundColor Yellow
        Write-Host 'No event rule was accepted and no guide was published by this preview.' -ForegroundColor Yellow
    }

    if ($PlanOnly -or $Accept) {
        $prior = Get-WorkflowCurrentSnapshot -RepositoryRoot $rootFull
        $machineParentGenerationManifestHash = if ($null -eq $prior) { $null } else { [string]$prior.Manifest.Object.GenerationManifestHash }
        $machineAcceptedEntryCount = if ($null -eq $prior) { $null } else { @($prior.State.Object.IncludedCandidateEntryIds).Count }
        if ($Accept -and $PSBoundParameters.ContainsKey('ExpectedParentGenerationManifestHash')) {
            $expectedParent = if ([string]::IsNullOrWhiteSpace($ExpectedParentGenerationManifestHash)) { $null } else { [string]$ExpectedParentGenerationManifestHash }
            if ($machineParentGenerationManifestHash -cne $expectedParent) {
                $report.Status = 'STALE'
                if ($MachineResult) { return }
                throw 'The accepted parent is no longer current; nothing was published.'
            }
        }
    }
    $report.WhatHappened = "Analyzed $($report.ChannelCount) channels."

    $report.Next = if ($report.AmbiguityCount -gt 0) {
        'Review the ambiguous guide matches, then run again with -Accept and a choice.'
    }
    elseif (-not $Accept) {
        'Review the proposal. Run again with -Accept to publish it.'
    }
    else {
        'The accepted lineup is ready for the downstream player or guide consumer.'
    }

    Write-Host ''
    Write-Host 'Proposed result' -ForegroundColor Yellow
    Write-Host "  Channels: $($report.ChannelCount)"
    Write-Host "  Exact guide matches: $($report.ExactGuideMatchCount)"
    Write-Host "  Needs your choice: $($report.AmbiguityCount)"
    Write-Host "  Guide-only records: $($report.GuideOnlyCount)"

    if (-not $Accept) {
        $report.Status = 'PROPOSAL_READY'
        $report.Changed = 'Candidate and proposal reports only; accepted output was not changed.'
        $report.Preserved = 'All existing accepted output was preserved.'
        if ($PlanOnly) {
            return
        }
        $reportFiles = Write-WorkflowReport -Root $rootFull -Report ([pscustomobject]$report)
        Write-Host "`nProposal saved to $($reportFiles.PlanPath). Nothing was published." -ForegroundColor Yellow
        return
    }
    $ambiguous = @($m3uBindings | Where-Object { [string]$_.Status -eq 'ReviewNeeded' })
    foreach ($binding in $ambiguous) {
        $entry = @($manifest.Entries | Where-Object { [string]$_.EntryId -ceq [string]$binding.EntryId }) | Select-Object -First 1
        $choice = $AmbiguousAction
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choiceText = Read-Host "Guide match for '$($entry.DisplayName)' is ambiguous. Enter K to keep the channels but publish no guide, or C to cancel"
            $choice = if ($choiceText -match '^(?i)c') { 'Cancel' } else { 'KeepWithoutGuide' }
        }

        if ($choice -eq 'Cancel') {
            throw 'An ambiguous guide match was left unresolved; nothing was published.'
        }
    }
    if ($ambiguous.Count -gt 0) {
        if ($null -ne $prior -and [string]$prior.Output.Object.ActiveXMLTVStatus -eq 'Generated') {
            throw 'An existing accepted guide is present; nothing was published. Cancel or provide an unambiguous guide to preserve it.'
        }
        # Ambiguous guide identity is never published. The channel candidate is
        # retained, while the accepted generation stays M3U-only.
        $candidateXMLTVBytes = $null
        $report.GuideStatus = 'GUIDE_SKIPPED_AMBIGUITY'
    }

    $included = @($manifest.Entries | ForEach-Object EntryId | Sort-Object)
    $excludedIds = @()
    $decisionRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($entryId in $included) {
        [void]$decisionRecords.Add((New-WorkflowDecision -DecisionType 'IncludeCandidateEntry' -CandidateEntryId $entryId -BindingId $null -ReasonCode 'GuidedSetupAccepted'))
    }
    $decisionRecords = @($decisionRecords | Sort-Object @{ Expression = { if ($_.DecisionType -eq 'AcceptGuideBinding') { 0 } elseif ($_.DecisionType -eq 'IncludeCandidateEntry') { 3 } else { 4 } } }, DecisionId)
    $acceptedM3UBytes = Get-WorkflowAcceptedM3UBytes -CandidateBytes $candidateM3UBytes -Entries @($manifest.Entries) -IncludedEntryIds $included
    if ($null -ne $prior -and [string]$prior.Manifest.Object.CandidateManifestHash -ceq [string]$manifest.CandidateManifestHash -and [string]$prior.Manifest.Object.BuildIdentity -ceq [string]$manifest.BuildIdentity) {
        $report.Status = 'ALREADY_ACCEPTED'
        $report.WhatHappened = 'This exact proposal is already the accepted lineup.'
        $report.Changed = 'Nothing; the accepted lineup was reused.'
        $report.Preserved = 'The accepted lineup remains unchanged.'
        $report.Next = 'Use the accepted lineup in your downstream player or guide consumer.'
    }
    else {
        [void](Publish-WorkflowAcceptedCandidate `
            -RepositoryRoot $rootFull `
            -CandidateManifest $manifest `
            -M3UBytes $acceptedM3UBytes `
            -XMLTVBytes $candidateXMLTVBytes `
            -DecisionRecords $decisionRecords `
            -IncludedEntryIds $included `
            -ExcludedEntryIds $excludedIds `
            -PriorSnapshot $prior)
        $report.Status = 'PUBLISHED'
        $report.WhatHappened = 'Accepted lineup published successfully.'
        $report.Changed = 'The accepted lineup was updated.'
        $report.Preserved = 'The previous accepted lineup remains available for rollback.'
        $report.Next = 'Use the accepted lineup in your downstream player or guide consumer.'
        $acceptedGenerationChanged = $true
    }
    $machineAcceptedEntryCount = $included.Count
    $acceptedPublicationCompleted = $true
    $consumerOutputs = Write-WorkflowConsumerOutputs -Root $rootFull -M3UBytes $acceptedM3UBytes -XMLTVBytes $candidateXMLTVBytes -FaultHook $FaultHook
    $report.ConsumerM3UPath = $consumerOutputs.M3UPath
    $report.ConsumerXMLTVPath = $consumerOutputs.XMLTVPath
    $consumerViewRefreshCompleted = $true
    if ($FaultHook -eq 'Report.BeforeWrite') { throw 'Guided Setup report write fault injected.' }

    $reportFiles = Write-WorkflowReport -Root $rootFull -Report ([pscustomobject]$report)
    Write-Host "`nSuccess: $($report.WhatHappened)" -ForegroundColor Green
    if ($null -ne $candidateXMLTVBytes) { Write-Host 'M3U lineup and XMLTV guide are ready for use.' }
    else { Write-Host 'M3U lineup is ready for use. No guide was selected.' }
    Write-Host "M3U lineup: $($report.ConsumerM3UPath)"
    if ($null -ne $report.ConsumerXMLTVPath) { Write-Host "XMLTV guide: $($report.ConsumerXMLTVPath)" }
    Write-Host "Summary: $($reportFiles.SummaryPath)"
}
catch {
    if ($acceptedPublicationCompleted) {
        if (-not $consumerViewRefreshCompleted) {
            if ($acceptedGenerationChanged) {
                $report.Status = 'PUBLISHED_VIEW_REFRESH_FAILED'
                $report.WhatHappened = 'The accepted lineup was published, but its stable consumer view could not be refreshed.'
                $report.Preserved = 'The accepted lineup remains authoritative; the previous stable consumer view was preserved.'
                $report.Changed = 'Accepted state changed; the stable consumer view was not updated.'
                $report.Next = 'Retry Build-My-Lineup.ps1 to refresh the stable consumer view.'
            }
            else {
                $report.Status = 'ALREADY_ACCEPTED'
                $report.WhatHappened = 'This exact proposal is already the accepted lineup.'
                $report.Changed = 'Nothing; the accepted lineup was reused.'
                $report.Preserved = 'The accepted lineup remains unchanged.'
                $report.Next = 'Retry Build-My-Lineup.ps1 to refresh the stable consumer view.'
            }
        }
        elseif ($acceptedGenerationChanged) {
            $report.Status = 'PUBLISHED_REPORT_WRITE_FAILED'
            $report.WhatHappened = 'The accepted lineup and stable consumer view were written, but the Guided Setup report could not be written.'
            $report.Preserved = 'The accepted lineup and stable consumer view remain available.'
            $report.Changed = 'Accepted state and the stable consumer view were updated.'
            $report.Next = 'Retry Build-My-Lineup.ps1 to write a fresh Guided Setup report.'
        }
        else {
            $report.Status = 'ALREADY_ACCEPTED'
            $report.WhatHappened = 'This exact proposal is already the accepted lineup.'
            $report.Changed = 'Nothing; the accepted lineup was reused.'
            $report.Preserved = 'The accepted lineup remains unchanged.'
            $report.Next = 'Retry Build-My-Lineup.ps1 to write a fresh Guided Setup report.'
        }
    }
    else {
        $report.WhatHappened = Get-SafeWorkflowMessage $_.Exception.Message
        if ($_.Exception.Message -match "empty array") {
            $report.WhatHappened = 'No channels were found in the IPTV playlist.'
        }
        $report.Preserved = 'Existing accepted output was not changed.'
        $report.Changed = 'Candidate staging and safe failure reports may have been created.'
        $report.Next = 'Correct the input or review the candidate report, then run Build-My-Lineup.ps1 again.'
    }
    try {
        $rootForReport = [System.IO.Path]::GetFullPath($Root)
        $reportFiles = Write-WorkflowReport -Root $rootForReport -Report ([pscustomobject]$report)
        if ($acceptedPublicationCompleted) {
            if (-not $consumerViewRefreshCompleted) {
                if ($acceptedGenerationChanged) {
                    Write-Host "Accepted lineup remains published. Stable consumer view was not refreshed. Details: $($reportFiles.PlanPath)" -ForegroundColor Yellow
                }
                else {
                    Write-Host "Accepted lineup was reused. Stable consumer view was not refreshed. Details: $($reportFiles.PlanPath)" -ForegroundColor Yellow
                }
            }
            elseif ($acceptedGenerationChanged) {
                Write-Host "Accepted lineup and stable consumer view remain published. Guided Setup report was not written. Details: $($reportFiles.PlanPath)" -ForegroundColor Yellow
            }
            else {
                Write-Host "Accepted lineup was reused and stable consumer view remains available. Guided Setup report was not written. Details: $($reportFiles.PlanPath)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Nothing was published. Details: $($reportFiles.PlanPath)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host 'ChannelForge could not finish, and the failure report could not be written.' -ForegroundColor Red
    }
    throw
}
finally {
    foreach ($path in @($stagedInputs)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
    if ($MachineResult) {
        $machineAcceptedLineupStatus = if ($acceptedPublicationCompleted -or $null -ne $prior) { 'present' } else { 'none' }
        $machinePayload = [ordered]@{
            Status = [string]$report.Status
            CandidateManifestHash = $machineCandidateManifestHash
            BuildIdentity = $machineBuildIdentity
            ParentGenerationManifestHash = $machineParentGenerationManifestHash
            AcceptedLineupStatus = $machineAcceptedLineupStatus
            AcceptedEntryCount = $machineAcceptedEntryCount
        }
        Write-Output ("CHANNELFORGE_MACHINE_RESULT:" + ($machinePayload | ConvertTo-Json -Compress))
    }
}

