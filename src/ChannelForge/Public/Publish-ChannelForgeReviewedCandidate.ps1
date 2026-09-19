
function Publish-ChannelForgeReviewedCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$CandidateManifest,
        [Parameter(Mandatory)][byte[]]$M3UBytes,
        [AllowNull()][byte[]]$XMLTVBytes,
        [Parameter(Mandatory)][object[]]$DecisionRecords,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$IncludedEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExcludedEntryIds,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$ExpectedParentGenerationManifestHash,
        [AllowNull()][string]$FaultHook = ''
    )

    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $null = Recover-ChannelForgeAcceptedStateCore -RepositoryRoot $root
    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $root
    $prior = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $root -Paths $paths
    $currentParent = if ($null -eq $prior) { $null } else { [string]$prior.Manifest.Object.GenerationManifestHash }
    $expectedParent = if ([string]::IsNullOrWhiteSpace($ExpectedParentGenerationManifestHash)) { $null } else { [string]$ExpectedParentGenerationManifestHash }
    if ($currentParent -cne $expectedParent) {
        throw 'STALE: The reviewed proposal is based on an accepted parent that is no longer current; nothing was published.'
    }

    $candidateHash = [string]$CandidateManifest.CandidateManifestHash
    $buildIdentity = [string]$CandidateManifest.BuildIdentity
    $parentStateHash = if ($null -eq $prior) { $null } else { [string]$prior.State.Object.AcceptedStateHash }
    $parentOutputHash = if ($null -eq $prior) { $null } else { [string]$prior.Output.Object.OutputManifestHash }

    $decisionM3U = New-ChannelForgeDecisionM3U `
        -CandidateManifestHash $candidateHash `
        -BuildIdentity $buildIdentity `
        -AcceptedParentGenerationManifestHash $currentParent `
        -IncludedCandidateEntryIds @($IncludedEntryIds | Sort-Object) `
        -ExcludedCandidateEntryIds @($ExcludedEntryIds | Sort-Object) `
        -DecisionIds @($DecisionRecords | Sort-Object @{ Expression = { if ($_.DecisionType -eq 'AcceptGuideBinding') { 0 } elseif ($_.DecisionType -eq 'IncludeCandidateEntry') { 3 } else { 4 } } }, DecisionId | ForEach-Object DecisionId)

    $xmltvStatus = if ($null -eq $XMLTVBytes) { 'NotGenerated' } else { 'Generated' }
    $decisionXMLTV = if ($xmltvStatus -eq 'Generated') {
        New-ChannelForgeDecisionXMLTV `
            -CandidateManifestHash $candidateHash `
            -BuildIdentity $buildIdentity `
            -AcceptedParentGenerationManifestHash $currentParent `
            -AcceptedXMLTVStatus 'Generated' `
            -IncludedCandidateEntryIds @($decisionM3U.IncludedCandidateEntryIds) `
            -ExcludedCandidateEntryIds @($decisionM3U.ExcludedCandidateEntryIds) `
            -DecisionIds @($decisionM3U.DecisionIds)
    }
    else { $null }

    $decisionManifest = New-ChannelForgeDecisionManifest `
        -CandidateManifestHash $candidateHash `
        -BuildIdentity $buildIdentity `
        -M3UDecision $decisionM3U `
        -XMLTVDecision $decisionXMLTV `
        -XMLTVDecisionStatus $xmltvStatus

    $acceptance = New-ChannelForgeAcceptance `
        -CandidateManifest $CandidateManifest `
        -DecisionManifest $decisionManifest `
        -M3UDecision $decisionM3U `
        -DecisionRecords $DecisionRecords

    $activeM3UHash = Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $M3UBytes
    $activeXMLTVHash = if ($null -eq $XMLTVBytes) { $null } else { Get-ChannelForgeDomainHash -Domain 'active-xmltv/v2' -Bytes $XMLTVBytes }
    $generationId = Get-ChannelForgeDomainHash -Domain 'generation-id/v2' -InputObject ([ordered]@{
        CandidateManifestHash = $candidateHash
        BuildIdentity = $buildIdentity
        DecisionManifestHash = [string]$decisionManifest.DecisionManifestHash
        Nonce = ([guid]::NewGuid().ToString('N'))
    })
    $acceptedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

    $acceptedOutputManifest = New-ChannelForgeAcceptedOutputManifest `
        -GenerationId $generationId `
        -ActiveM3UHash $activeM3UHash `
        -ActiveXMLTVStatus $xmltvStatus `
        -ActiveXMLTVHash $activeXMLTVHash `
        -AcceptedStateHash ('0' * 64)
    $acceptedState = New-ChannelForgeAcceptedState `
        -GenerationId $generationId `
        -BuildIdentity $buildIdentity `
        -CandidateManifestHash $candidateHash `
        -DecisionManifestHash ([string]$decisionManifest.DecisionManifestHash) `
        -AcceptedOutputManifestHash ([string]$acceptedOutputManifest.OutputManifestHash) `
        -PreviousStateHash $parentStateHash `
        -IncludedCandidateEntryIds @($decisionM3U.IncludedCandidateEntryIds) `
        -ExcludedCandidateEntryIds @($decisionM3U.ExcludedCandidateEntryIds) `
        -AcceptedBindingIds @($decisionM3U.DecisionIds) `
        -AcceptedXMLTVStatus $xmltvStatus `
        -AcceptedAtUtc $acceptedAtUtc
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
    $generationManifest.GenerationManifestHash = Get-ChannelForgeAcceptanceHash `
        -Domain 'generation-manifest/v2' `
        -Projection $generationManifest `
        -HashProperty 'GenerationManifestHash' `
        -Omit @('GenerationId')

    $publishArguments = @{
        RepositoryRoot = $root
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
