$script:ChannelForgeAcceptanceVersion = 'blocker-2-contract/v8-acceptance'

function Assert-ChannelForgeAcceptanceHash {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Value -or ([string]$Value) -cnotmatch '^[0-9a-f]{64}$') {
        throw "FAIL_CLOSED: $Name must be a lowercase 64-hex hash."
    }
}

function Assert-ChannelForgeAcceptanceGenerationId {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Value -or ([string]$Value) -cnotmatch '^[0-9a-f]{64}$') {
        throw "FAIL_CLOSED: $Name must be a lowercase 64-hex generation ID."
    }
}

function Assert-ChannelForgeAcceptanceVersion {
    param([Parameter(Mandatory)][object]$Projection, [Parameter(Mandatory)][string]$Name)
    $value = if ($Projection -is [System.Collections.IDictionary]) {
        if ($Projection.Contains('Version')) { $Projection['Version'] } else { $null }
    } elseif ($null -ne $Projection.PSObject.Properties['Version']) {
        $Projection.PSObject.Properties['Version'].Value
    } else { $null }
    if ($null -eq $value -or [string]$value -cne $script:ChannelForgeAcceptanceVersion) {
        throw "FAIL_CLOSED: $Name must use $script:ChannelForgeAcceptanceVersion."
    }
}

function Assert-ChannelForgeCandidateVersion {
    param([Parameter(Mandatory)][object]$Projection, [Parameter(Mandatory)][string]$Name)
    $allowedVersions = @('blocker-2-contract/v7', 'blocker-2-contract/v8')
    foreach ($propertyName in @('Version','ContractVersion')) {
        $property = $Projection.PSObject.Properties[$propertyName]
        if ($null -eq $property -or [string]$property.Value -notin $allowedVersions) {
            throw "FAIL_CLOSED: $Name must use a supported candidate contract version."
        }
    }
    if ([string]$Projection.Version -cne [string]$Projection.ContractVersion) {
        throw "FAIL_CLOSED: $Name has mismatched candidate contract versions."
    }
}

function Assert-ChannelForgeAcceptanceUtc {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Value -or $Value -isnot [string]) { throw "FAIL_CLOSED: $Name must be canonical UTC." }
    $text = [string]$Value
    if ($text -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,7})?Z$') {
        throw "FAIL_CLOSED: $Name must be canonical UTC."
    }
    $format = if ($text.Contains('.')) { "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'" } else { "yyyy-MM-dd'T'HH:mm:ss'Z'" }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParseExact($text, $format, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        throw "FAIL_CLOSED: $Name must be canonical UTC."
    }
}

function Assert-ChannelForgeAcceptanceIds {
    param([AllowNull()][AllowEmptyCollection()][object[]]$Values, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Values) { $Values = @() }
    $ids = @($Values | ForEach-Object { [string]$_ })
    foreach ($id in $ids) {
        if ($id -notmatch '^[0-9a-f]{64}$') { throw "FAIL_CLOSED: invalid $Name." }
    }
    if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw "FAIL_CLOSED: duplicate $Name." }
    for ($index = 1; $index -lt $ids.Count; $index++) {
        if ([string]::CompareOrdinal($ids[$index - 1], $ids[$index]) -gt 0) {
            throw "FAIL_CLOSED: $Name must be sorted."
        }
    }
}

function Assert-ChannelForgeAcceptanceDisjointIds {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Included, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Excluded)
    $includedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($id in $Included) { [void]$includedSet.Add([string]$id) }
    foreach ($id in $Excluded) {
        if ($includedSet.Contains([string]$id)) { throw 'FAIL_CLOSED: included and excluded IDs overlap.' }
    }
}

function ConvertTo-ChannelForgeAcceptanceOrdered {
    param([Parameter(Mandatory)][object]$InputObject)
    $ordered = [ordered]@{}
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($entry in $InputObject.GetEnumerator()) { $ordered[$entry.Key] = $entry.Value }
    }
    else {
        foreach ($property in @($InputObject.PSObject.Properties)) { $ordered[$property.Name] = $property.Value }
    }
    return $ordered
}

function Get-ChannelForgeAcceptanceHash {
    param([Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][System.Collections.IDictionary]$Projection, [Parameter(Mandatory)][string]$HashProperty, [string[]]$Omit = @())
    $input = [ordered]@{}
    foreach ($entry in $Projection.GetEnumerator()) {
        if ($entry.Key -ne $HashProperty -and $entry.Key -notin $Omit) { $input[$entry.Key] = $entry.Value }
    }
    return Get-ChannelForgeDomainHash -Domain $Domain -InputObject $input
}

function Test-ChannelForgeAcceptanceHashProperty {
    param([Parameter(Mandatory)][object]$Projection, [Parameter(Mandatory)][string]$Domain, [Parameter(Mandatory)][string]$HashProperty, [string[]]$Omit = @())
    $ordered = ConvertTo-ChannelForgeAcceptanceOrdered $Projection
    if ($null -eq $ordered[$HashProperty]) { return $false }
    return (Get-ChannelForgeAcceptanceHash -Domain $Domain -Projection $ordered -HashProperty $HashProperty -Omit $Omit) -ceq [string]$ordered[$HashProperty]
}

function Get-ChannelForgeAcceptanceSortedIds {
    param([AllowNull()][AllowEmptyCollection()][object[]]$Values)
    if ($null -eq $Values) { return @() }
    return @($Values | ForEach-Object { [string]$_ } | Sort-Object)
}

function New-ChannelForgeReviewRecord {
    param(
        [Parameter(Mandatory)][ValidateSet('Actionable','Informational')][string]$ReviewCategory,
        [Parameter(Mandatory)][string]$Classification,
        [Parameter(Mandatory)][string]$ReasonCode,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CandidateEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AcceptedEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$CandidateBindingIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$DecisionTypesAllowed,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Evidence
    )
    if ($null -eq $CandidateEntryIds) { $CandidateEntryIds = @() }
    if ($null -eq $AcceptedEntryIds) { $AcceptedEntryIds = @() }
    if ($null -eq $CandidateBindingIds) { $CandidateBindingIds = @() }
    if ($null -eq $DecisionTypesAllowed) { $DecisionTypesAllowed = @() }
    $Evidence = @($Evidence | Sort-Object -Property @{Expression={ [string]$_.EvidenceType }; Ascending=$true }, @{Expression={ [string]$_.Value }; Ascending=$true }, @{Expression={ if ($null -eq $_.Ordinal) { -1 } else { [int]$_.Ordinal } }; Ascending=$true })
    if ($null -eq $Evidence) { $Evidence = @() }
    $candidateIds = Get-ChannelForgeAcceptanceSortedIds $CandidateEntryIds
    $acceptedIds = Get-ChannelForgeAcceptanceSortedIds $AcceptedEntryIds
    $bindingIds = Get-ChannelForgeAcceptanceSortedIds $CandidateBindingIds
    Assert-ChannelForgeAcceptanceIds $candidateIds 'CandidateEntryIds'
    Assert-ChannelForgeAcceptanceIds $acceptedIds 'AcceptedEntryIds'
    Assert-ChannelForgeAcceptanceIds $bindingIds 'CandidateBindingIds'
    $types = @($DecisionTypesAllowed | ForEach-Object { [string]$_ } | Sort-Object)
    $xmltvOnly = $candidateIds.Count -eq 0 -and $acceptedIds.Count -eq 0 -and $Evidence.Count -gt 0
    if ($ReviewCategory -eq 'Actionable' -and -not $xmltvOnly -and ($candidateIds.Count -ne 1 -or $acceptedIds.Count -ne 1 -or $types.Count -eq 0)) {
        throw 'FAIL_CLOSED: actionable review must identify one candidate, one accepted entry, and an allowed decision.'
    }
    if ($xmltvOnly -and $ReviewCategory -eq 'Actionable' -and $types -notcontains 'AcceptGuideBinding') {
        throw 'FAIL_CLOSED: XMLTV-only actionable review requires AcceptGuideBinding.'
    }
    if ($candidateIds.Count -eq 0 -and $acceptedIds.Count -eq 0 -and $bindingIds.Count -eq 0 -and $Evidence.Count -eq 0) {
        throw 'FAIL_CLOSED: review record has no identity evidence.'
    }
    $base = [ordered]@{
        ReviewCategory = $ReviewCategory
        Classification = $Classification
        ReasonCode = $ReasonCode
        CandidateEntryIds = @($candidateIds)
        AcceptedEntryIds = @($acceptedIds)
        CandidateBindingIds = @($bindingIds)
        DecisionTypesAllowed = @($types)
        Evidence = @($Evidence)
    }
    $reviewId = Get-ChannelForgeDomainHash -Domain 'review-id/v2' -InputObject $base
    $record = [ordered]@{
        ReviewId = $reviewId
        ReviewCategory = $ReviewCategory
        Classification = $Classification
        ReasonCode = $ReasonCode
        CandidateEntryIds = @($candidateIds)
        AcceptedEntryIds = @($acceptedIds)
        CandidateBindingIds = @($bindingIds)
        DecisionTypesAllowed = @($types)
        Evidence = @($Evidence)
        ReviewRecordDigest = $null
    }
    $record.ReviewRecordDigest = Get-ChannelForgeAcceptanceHash -Domain 'review-id/v2' -Projection $record -HashProperty ReviewRecordDigest
    return [pscustomobject]$record
}
function New-ChannelForgeDecisionM3U {
    param(
        [Parameter(Mandatory)][string]$CandidateManifestHash,
        [Parameter(Mandatory)][string]$BuildIdentity,
        [AllowNull()][object]$AcceptedParentGenerationManifestHash,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$IncludedCandidateEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ExcludedCandidateEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$DecisionIds
    )
    Assert-ChannelForgeAcceptanceHash $CandidateManifestHash 'CandidateManifestHash'
    Assert-ChannelForgeAcceptanceHash $BuildIdentity 'BuildIdentity'
    if ($null -ne $AcceptedParentGenerationManifestHash) { Assert-ChannelForgeAcceptanceHash $AcceptedParentGenerationManifestHash 'AcceptedParentGenerationManifestHash' }
    Assert-ChannelForgeAcceptanceIds $IncludedCandidateEntryIds 'IncludedCandidateEntryIds'
    Assert-ChannelForgeAcceptanceIds $ExcludedCandidateEntryIds 'ExcludedCandidateEntryIds'
    Assert-ChannelForgeAcceptanceIds $DecisionIds 'DecisionIds'
    Assert-ChannelForgeAcceptanceDisjointIds $IncludedCandidateEntryIds $ExcludedCandidateEntryIds
    $result = [ordered]@{
        Version = $script:ChannelForgeAcceptanceVersion
        CandidateManifestHash = $CandidateManifestHash
        BuildIdentity = $BuildIdentity
        AcceptedParentGenerationManifestHash = $AcceptedParentGenerationManifestHash
        IncludedCandidateEntryIds = @($IncludedCandidateEntryIds)
        ExcludedCandidateEntryIds = @($ExcludedCandidateEntryIds)
        DecisionIds = @($DecisionIds)
        M3UDecisionHash = $null
    }
    $result.M3UDecisionHash = Get-ChannelForgeAcceptanceHash -Domain 'decision-m3u/v2' -Projection $result -HashProperty M3UDecisionHash
    return [pscustomobject]$result
}

function New-ChannelForgeDecisionXMLTV {
    param(
        [Parameter(Mandatory)][string]$CandidateManifestHash,
        [Parameter(Mandatory)][string]$BuildIdentity,
        [AllowNull()][object]$AcceptedParentGenerationManifestHash,
        [Parameter(Mandatory)][ValidateSet('Generated','NotGenerated')][string]$AcceptedXMLTVStatus,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$IncludedCandidateEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ExcludedCandidateEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$DecisionIds
    )
    Assert-ChannelForgeAcceptanceHash $CandidateManifestHash 'CandidateManifestHash'
    Assert-ChannelForgeAcceptanceHash $BuildIdentity 'BuildIdentity'
    if ($null -ne $AcceptedParentGenerationManifestHash) { Assert-ChannelForgeAcceptanceHash $AcceptedParentGenerationManifestHash 'AcceptedParentGenerationManifestHash' }
    Assert-ChannelForgeAcceptanceIds $IncludedCandidateEntryIds 'IncludedCandidateEntryIds'
    Assert-ChannelForgeAcceptanceIds $ExcludedCandidateEntryIds 'ExcludedCandidateEntryIds'
    Assert-ChannelForgeAcceptanceIds $DecisionIds 'DecisionIds'
    Assert-ChannelForgeAcceptanceDisjointIds $IncludedCandidateEntryIds $ExcludedCandidateEntryIds
    $result = [ordered]@{
        Version = $script:ChannelForgeAcceptanceVersion
        CandidateManifestHash = $CandidateManifestHash
        BuildIdentity = $BuildIdentity
        AcceptedParentGenerationManifestHash = $AcceptedParentGenerationManifestHash
        AcceptedXMLTVStatus = $AcceptedXMLTVStatus
        IncludedCandidateEntryIds = @($IncludedCandidateEntryIds)
        ExcludedCandidateEntryIds = @($ExcludedCandidateEntryIds)
        DecisionIds = @($DecisionIds)
        XMLTVDecisionHash = $null
    }
    $result.XMLTVDecisionHash = Get-ChannelForgeAcceptanceHash -Domain 'decision-xmltv/v2' -Projection $result -HashProperty XMLTVDecisionHash
    return [pscustomobject]$result
}

function Get-ChannelForgeAcceptanceDecisionIds {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Decisions)
    return @($Decisions | ForEach-Object { [string]$_.DecisionId })
}

function Assert-ChannelForgeAcceptanceDecisionRecords {
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Decisions)
    if ($null -eq $Decisions) { $Decisions = @() }
    $ranks = @{ AcceptGuideBinding = 0; MapCandidateToAcceptedEntry = 1; KeepAcceptedEntry = 2; IncludeCandidateEntry = 3; ExcludeCandidateEntry = 4 }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $previousKey = $null
    foreach ($decision in $Decisions) {
        if ($null -eq $decision.PSObject.Properties['DecisionId'] -or $null -eq $decision.PSObject.Properties['DecisionType']) { throw 'FAIL_CLOSED: malformed decision record.' }
        $type = [string]$decision.DecisionType
        if (-not $ranks.ContainsKey($type)) { throw 'FAIL_CLOSED: unsupported decision type.' }
        $id = [string]$decision.DecisionId
        Assert-ChannelForgeAcceptanceHash $id 'DecisionId'
        if (-not $seen.Add($id)) { throw 'FAIL_CLOSED: duplicate DecisionId.' }
        $withoutId = [ordered]@{}
        foreach ($property in @($decision.PSObject.Properties)) { if ($property.Name -ne 'DecisionId') { $withoutId[$property.Name] = $property.Value } }
        if ((Get-ChannelForgeDomainHash -Domain 'decision-manifest/v2' -InputObject $withoutId) -cne $id) { throw 'FAIL_CLOSED: forged DecisionId.' }
        $sortKey = '{0}:{1}' -f $ranks[$type], $id
        if ($null -ne $previousKey -and [string]::CompareOrdinal($previousKey, $sortKey) -gt 0) { throw 'FAIL_CLOSED: Decisions must be sorted.' }
        $previousKey = $sortKey
    }
}

function New-ChannelForgeDecisionManifest {
    param([Parameter(Mandatory)][string]$CandidateManifestHash,[Parameter(Mandatory)][string]$BuildIdentity,[Parameter(Mandatory)]$M3UDecision,[AllowNull()]$XMLTVDecision,[Parameter(Mandatory)][ValidateSet('Generated','NotGenerated')][string]$XMLTVDecisionStatus)
    Assert-ChannelForgeAcceptanceHash $CandidateManifestHash 'CandidateManifestHash'
    Assert-ChannelForgeAcceptanceHash $BuildIdentity 'BuildIdentity'
    Assert-ChannelForgeAcceptanceVersion $M3UDecision 'M3UDecision'
    if (-not (Test-ChannelForgeAcceptanceHashProperty $M3UDecision 'decision-m3u/v2' 'M3UDecisionHash')) { throw 'FAIL_CLOSED: forged M3U decision hash.' }
    if ($M3UDecision.CandidateManifestHash -cne $CandidateManifestHash -or $M3UDecision.BuildIdentity -cne $BuildIdentity) { throw 'FAIL_CLOSED: candidate/build mismatch.' }
    if ($XMLTVDecisionStatus -eq 'Generated' -and $null -eq $XMLTVDecision) { throw 'FAIL_CLOSED: missing XMLTV decision.' }
    if ($XMLTVDecisionStatus -eq 'NotGenerated' -and $null -ne $XMLTVDecision) { throw 'FAIL_CLOSED: forbidden XMLTV decision.' }
    if ($null -ne $XMLTVDecision) {
        Assert-ChannelForgeAcceptanceVersion $XMLTVDecision 'XMLTVDecision'
        if (-not (Test-ChannelForgeAcceptanceHashProperty $XMLTVDecision 'decision-xmltv/v2' 'XMLTVDecisionHash')) { throw 'FAIL_CLOSED: forged XMLTV decision hash.' }
        foreach ($property in @('CandidateManifestHash','BuildIdentity','AcceptedParentGenerationManifestHash')) {
            if ([string]$XMLTVDecision.$property -cne [string]$M3UDecision.$property) { throw "FAIL_CLOSED: XMLTV decision $property mismatch." }
        }
        if ($XMLTVDecision.AcceptedXMLTVStatus -cne $XMLTVDecisionStatus -or (($XMLTVDecision.DecisionIds -join ',') -cne ($M3UDecision.DecisionIds -join ',')) -or (($XMLTVDecision.IncludedCandidateEntryIds -join ',') -cne ($M3UDecision.IncludedCandidateEntryIds -join ',')) -or (($XMLTVDecision.ExcludedCandidateEntryIds -join ',') -cne ($M3UDecision.ExcludedCandidateEntryIds -join ','))) { throw 'FAIL_CLOSED: M3U/XMLTV decision mismatch.' }
    }
    $result = [ordered]@{
        Version = $script:ChannelForgeAcceptanceVersion
        CandidateManifestHash = $CandidateManifestHash
        BuildIdentity = $BuildIdentity
        M3UDecisionHash = $M3UDecision.M3UDecisionHash
        XMLTVDecisionStatus = $XMLTVDecisionStatus
        XMLTVDecisionHash = if ($null -eq $XMLTVDecision) { $null } else { [string]$XMLTVDecision.XMLTVDecisionHash }
        DecisionIds = @($M3UDecision.DecisionIds)
        DecisionManifestHash = $null
    }
    $result.DecisionManifestHash = Get-ChannelForgeAcceptanceHash -Domain 'decision-manifest/v2' -Projection $result -HashProperty DecisionManifestHash
    return [pscustomobject]$result
}

function New-ChannelForgeAcceptedState {
    param(
        [Parameter(Mandatory)][string]$GenerationId,
        [Parameter(Mandatory)][string]$BuildIdentity,
        [Parameter(Mandatory)][string]$CandidateManifestHash,
        [Parameter(Mandatory)][string]$DecisionManifestHash,
        [Parameter(Mandatory)][string]$AcceptedOutputManifestHash,
        [AllowNull()][object]$PreviousStateHash = $null,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$IncludedCandidateEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ExcludedCandidateEntryIds,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AcceptedBindingIds,
        [Parameter(Mandatory)][ValidateSet('Generated','NotGenerated')][string]$AcceptedXMLTVStatus,
        [Parameter(Mandatory)][string]$AcceptedAtUtc
    )
    Assert-ChannelForgeAcceptanceGenerationId $GenerationId 'GenerationId'
    foreach ($name in @('BuildIdentity','CandidateManifestHash','DecisionManifestHash','AcceptedOutputManifestHash')) { Assert-ChannelForgeAcceptanceHash (Get-Variable $name -ValueOnly) $name }
    if ($null -ne $PreviousStateHash) { Assert-ChannelForgeAcceptanceHash $PreviousStateHash 'PreviousStateHash' }
    Assert-ChannelForgeAcceptanceIds $IncludedCandidateEntryIds 'IncludedCandidateEntryIds'
    Assert-ChannelForgeAcceptanceIds $ExcludedCandidateEntryIds 'ExcludedCandidateEntryIds'
    Assert-ChannelForgeAcceptanceIds $AcceptedBindingIds 'AcceptedBindingIds'
    Assert-ChannelForgeAcceptanceUtc $AcceptedAtUtc 'AcceptedAtUtc'
    $result = [ordered]@{
        Version = $script:ChannelForgeAcceptanceVersion
        GenerationId = $GenerationId
        BuildIdentity = $BuildIdentity
        CandidateManifestHash = $CandidateManifestHash
        DecisionManifestHash = $DecisionManifestHash
        AcceptedOutputManifestHash = $AcceptedOutputManifestHash
        PreviousStateHash = $PreviousStateHash
        IncludedCandidateEntryIds = @($IncludedCandidateEntryIds)
        ExcludedCandidateEntryIds = @($ExcludedCandidateEntryIds)
        AcceptedBindingIds = @($AcceptedBindingIds)
        AcceptedXMLTVStatus = $AcceptedXMLTVStatus
        AcceptedAtUtc = $AcceptedAtUtc
        AcceptedStateHash = $null
    }
    $result.AcceptedStateHash = Get-ChannelForgeAcceptanceHash -Domain 'accepted-state/v2' -Projection $result -HashProperty AcceptedStateHash -Omit @('GenerationId','AcceptedAtUtc')
    return [pscustomobject]$result
}

function New-ChannelForgeAcceptedOutputManifest {
    param([Alias('GenerationSemanticId')][Parameter(Mandatory)][string]$GenerationId,[Parameter(Mandatory)][string]$ActiveM3UHash,[Parameter(Mandatory)][ValidateSet('Generated','NotGenerated')][string]$ActiveXMLTVStatus,[AllowNull()][object]$ActiveXMLTVHash,[Parameter(Mandatory)][string]$AcceptedStateHash)
    Assert-ChannelForgeAcceptanceGenerationId $GenerationId 'GenerationId'
    Assert-ChannelForgeAcceptanceHash $ActiveM3UHash 'ActiveM3UHash'
    Assert-ChannelForgeAcceptanceHash $AcceptedStateHash 'AcceptedStateHash'
    if ($ActiveXMLTVStatus -eq 'Generated') { Assert-ChannelForgeAcceptanceHash $ActiveXMLTVHash 'ActiveXMLTVHash' }
    elseif ($null -ne $ActiveXMLTVHash) { throw 'FAIL_CLOSED: invalid NotGenerated output.' }
    $result = [ordered]@{
        Version = $script:ChannelForgeAcceptanceVersion
        GenerationId = $GenerationId
        ActiveM3UHash = $ActiveM3UHash
        ActiveXMLTVStatus = $ActiveXMLTVStatus
        ActiveXMLTVHash = if ($ActiveXMLTVStatus -eq 'Generated') { [string]$ActiveXMLTVHash } else { $null }
        AcceptedStateHash = $AcceptedStateHash
        OutputManifestHash = $null
    }
    $result.OutputManifestHash = Get-ChannelForgeAcceptanceHash -Domain 'previous-output-manifest/v2' -Projection $result -HashProperty OutputManifestHash -Omit @('GenerationId','AcceptedStateHash')
    return [pscustomobject]$result
}

function New-ChannelForgeActiveM3U {
    param([Parameter(Mandatory)][string]$GenerationId,[Parameter(Mandatory)][string]$AcceptedStateHash,[Parameter(Mandatory)][string]$OutputManifestHash,[Parameter(Mandatory)][string]$ContentHash,[Parameter(Mandatory)][uint64]$ByteLength,[string]$RelativePath = 'merged.m3u')
    Assert-ChannelForgeAcceptanceGenerationId $GenerationId 'GenerationId'; Assert-ChannelForgeAcceptanceHash $AcceptedStateHash 'AcceptedStateHash'; Assert-ChannelForgeAcceptanceHash $OutputManifestHash 'OutputManifestHash'; Assert-ChannelForgeAcceptanceHash $ContentHash 'ContentHash'
    if ($RelativePath -cne 'merged.m3u' -or $ByteLength -eq 0) { throw 'FAIL_CLOSED: invalid active M3U descriptor.' }
    return [pscustomobject][ordered]@{ Version = $script:ChannelForgeAcceptanceVersion; GenerationId = $GenerationId; AcceptedStateHash = $AcceptedStateHash; OutputManifestHash = $OutputManifestHash; ContentHash = $ContentHash; ByteLength = $ByteLength; RelativePath = $RelativePath }
}

function New-ChannelForgeActiveXMLTV {
    param([Parameter(Mandatory)][string]$GenerationId,[Parameter(Mandatory)][string]$AcceptedStateHash,[Parameter(Mandatory)][string]$OutputManifestHash,[Parameter(Mandatory)][ValidateSet('Generated','NotGenerated')][string]$Status,[AllowNull()][object]$ContentHash,[Parameter(Mandatory)][uint64]$ByteLength,[AllowNull()][object]$RelativePath)
    Assert-ChannelForgeAcceptanceGenerationId $GenerationId 'GenerationId'; Assert-ChannelForgeAcceptanceHash $AcceptedStateHash 'AcceptedStateHash'; Assert-ChannelForgeAcceptanceHash $OutputManifestHash 'OutputManifestHash'
    if ($Status -eq 'Generated') {
        Assert-ChannelForgeAcceptanceHash $ContentHash 'ContentHash'
        if ($ByteLength -eq 0 -or [string]$RelativePath -cne 'merged.xml') { throw 'FAIL_CLOSED: invalid Generated XMLTV descriptor.' }
    }
    elseif ($null -ne $ContentHash -or $ByteLength -ne 0 -or $null -ne $RelativePath) { throw 'FAIL_CLOSED: invalid NotGenerated XMLTV descriptor.' }
    return [pscustomobject][ordered]@{ Version = $script:ChannelForgeAcceptanceVersion; GenerationId = $GenerationId; AcceptedStateHash = $AcceptedStateHash; OutputManifestHash = $OutputManifestHash; Status = $Status; ContentHash = if ($Status -eq 'Generated') { [string]$ContentHash } else { $null }; ByteLength = $ByteLength; RelativePath = if ($Status -eq 'Generated') { [string]$RelativePath } else { $null } }
}

function Get-ChannelForgeKeepAcceptedEntry {
    param([Parameter(Mandatory)]$PriorM3UDescriptor,[Parameter(Mandatory)][byte[]]$PriorM3UBytes,[Parameter(Mandatory)]$PriorAcceptedEntrySlice)
    $slice = if ($null -ne $PriorAcceptedEntrySlice.EntryOutputSlice) { $PriorAcceptedEntrySlice.EntryOutputSlice } else { $PriorAcceptedEntrySlice }
    if ($null -eq $slice -or $null -eq $PriorAcceptedEntrySlice.EntryId) { throw 'FAIL_CLOSED: exact prior accepted output slice unavailable.' }
    foreach ($name in @('RelativePath','ByteOffset','ByteLength','EntryContentHash')) { if ($null -eq $slice.PSObject.Properties[$name]) { throw "FAIL_CLOSED: missing prior slice field $name." } }
    if ([string]$slice.RelativePath -cne 'merged.m3u' -or [int64]$slice.ByteOffset -lt 0 -or [int64]$slice.ByteLength -le 0 -or ([int64]$slice.ByteOffset + [int64]$slice.ByteLength) -gt $PriorM3UBytes.Length) { throw 'FAIL_CLOSED: prior accepted output slice is out of bounds.' }
    if ([string]$PriorM3UDescriptor.RelativePath -cne 'merged.m3u' -or [int64]$PriorM3UDescriptor.ByteLength -ne $PriorM3UBytes.Length) { throw 'FAIL_CLOSED: prior accepted M3U evidence does not match descriptor.' }
    Assert-ChannelForgeAcceptanceHash $PriorM3UDescriptor.ContentHash 'PriorM3UDescriptor.ContentHash'
    if ((Get-ChannelForgeDomainHash -Domain 'active-m3u/v2' -Bytes $PriorM3UBytes) -cne [string]$PriorM3UDescriptor.ContentHash) { throw 'FAIL_CLOSED: prior accepted M3U bytes do not match descriptor hash.' }
    Assert-ChannelForgeAcceptanceHash $slice.EntryContentHash 'EntryContentHash'
    $bytes = [byte[]]::new([int]$slice.ByteLength)
    [Array]::Copy($PriorM3UBytes, [int]$slice.ByteOffset, $bytes, 0, [int]$slice.ByteLength)
    if ((Get-ChannelForgeDomainHash -Domain 'candidate-entry-content/v1' -Bytes $bytes) -cne [string]$slice.EntryContentHash) { throw 'FAIL_CLOSED: prior accepted entry slice hash mismatch.' }
    return [pscustomobject][ordered]@{ EntryId = [string]$PriorAcceptedEntrySlice.EntryId; OutputBytes = $bytes; EntryOutputSlice = $slice }
}

function New-ChannelForgePreviousM3U {
    param([Parameter(Mandatory)][string]$GenerationId,[Parameter(Mandatory)][string]$AcceptedStateHash,[Parameter(Mandatory)][string]$OutputManifestHash,[Parameter(Mandatory)][string]$ContentHash,[Parameter(Mandatory)][uint64]$ByteLength,[Parameter(Mandatory)][string]$PreviousGenerationId)
    Assert-ChannelForgeAcceptanceGenerationId $GenerationId 'GenerationId'; Assert-ChannelForgeAcceptanceHash $AcceptedStateHash 'AcceptedStateHash'; Assert-ChannelForgeAcceptanceHash $OutputManifestHash 'OutputManifestHash'; Assert-ChannelForgeAcceptanceHash $ContentHash 'ContentHash'; Assert-ChannelForgeAcceptanceGenerationId $PreviousGenerationId 'PreviousGenerationId'
    if ($GenerationId -ceq $PreviousGenerationId -or $ByteLength -eq 0) { throw 'FAIL_CLOSED: invalid previous M3U lineage.' }
    return [pscustomobject][ordered]@{ Version = $script:ChannelForgeAcceptanceVersion; GenerationId = $GenerationId; AcceptedStateHash = $AcceptedStateHash; OutputManifestHash = $OutputManifestHash; ContentHash = $ContentHash; ByteLength = $ByteLength; RelativePath = 'merged.m3u'; PreviousGenerationId = $PreviousGenerationId }
}
function New-ChannelForgePreviousXMLTV {
    param([Parameter(Mandatory)][string]$GenerationId,[Parameter(Mandatory)][string]$AcceptedStateHash,[Parameter(Mandatory)][string]$OutputManifestHash,[Parameter(Mandatory)][ValidateSet('Generated','NotGenerated')][string]$Status,[AllowNull()][object]$ContentHash,[Parameter(Mandatory)][uint64]$ByteLength,[AllowNull()][object]$RelativePath,[Parameter(Mandatory)][string]$PreviousGenerationId)
    Assert-ChannelForgeAcceptanceGenerationId $GenerationId 'GenerationId'
    Assert-ChannelForgeAcceptanceHash $AcceptedStateHash 'AcceptedStateHash'
    Assert-ChannelForgeAcceptanceHash $OutputManifestHash 'OutputManifestHash'
    Assert-ChannelForgeAcceptanceGenerationId $PreviousGenerationId 'PreviousGenerationId'
    if ($GenerationId -ceq $PreviousGenerationId) { throw 'FAIL_CLOSED: previous XMLTV owner equals current generation.' }
    if ($Status -eq 'Generated') {
        Assert-ChannelForgeAcceptanceHash $ContentHash 'ContentHash'
        if ($ByteLength -eq 0 -or [string]$RelativePath -cne 'merged.xml') { throw 'FAIL_CLOSED: invalid previous Generated XMLTV.' }
    }
    elseif ($null -ne $ContentHash -or $ByteLength -ne 0 -or $null -ne $RelativePath) {
        throw 'FAIL_CLOSED: invalid previous NotGenerated XMLTV.'
    }
    return [pscustomobject][ordered]@{
        Version = $script:ChannelForgeAcceptanceVersion
        GenerationId = $GenerationId
        AcceptedStateHash = $AcceptedStateHash
        OutputManifestHash = $OutputManifestHash
        Status = $Status
        ContentHash = if ($Status -eq 'Generated') { [string]$ContentHash } else { $null }
        ByteLength = $ByteLength
        RelativePath = if ($Status -eq 'Generated') { [string]$RelativePath } else { $null }
        PreviousGenerationId = $PreviousGenerationId
    }
}

function Test-ChannelForgeAcceptanceBinding {
    param([Parameter(Mandatory)]$DecisionManifest,[Parameter(Mandatory)]$AcceptedState,[Parameter(Mandatory)]$OutputManifest,[Parameter(Mandatory)][string]$CandidateManifestHash,[Parameter(Mandatory)][string]$BuildIdentity,[AllowNull()][string]$GenerationId = $null)
    Assert-ChannelForgeAcceptanceVersion $DecisionManifest 'DecisionManifest'
    Assert-ChannelForgeAcceptanceVersion $AcceptedState 'AcceptedState'
    Assert-ChannelForgeAcceptanceVersion $OutputManifest 'OutputManifest'
    if (-not (Test-ChannelForgeAcceptanceHashProperty $DecisionManifest 'decision-manifest/v2' 'DecisionManifestHash') -or $DecisionManifest.CandidateManifestHash -cne $CandidateManifestHash -or $DecisionManifest.BuildIdentity -cne $BuildIdentity) { throw 'FAIL_CLOSED: decision identity mismatch.' }
    if (-not (Test-ChannelForgeAcceptanceHashProperty $AcceptedState 'accepted-state/v2' 'AcceptedStateHash' -Omit @('GenerationId','AcceptedAtUtc'))) { throw 'FAIL_CLOSED: forged accepted state hash.' }
    if (-not (Test-ChannelForgeAcceptanceHashProperty $OutputManifest 'previous-output-manifest/v2' 'OutputManifestHash' -Omit @('GenerationId','AcceptedStateHash'))) { throw 'FAIL_CLOSED: forged output manifest hash.' }
    Assert-ChannelForgeAcceptanceGenerationId $AcceptedState.GenerationId 'AcceptedState.GenerationId'
    Assert-ChannelForgeAcceptanceGenerationId $OutputManifest.GenerationId 'OutputManifest.GenerationId'
    Assert-ChannelForgeAcceptanceUtc $AcceptedState.AcceptedAtUtc 'AcceptedAtUtc'
    if ($AcceptedState.CandidateManifestHash -cne $CandidateManifestHash -or $AcceptedState.BuildIdentity -cne $BuildIdentity -or $AcceptedState.DecisionManifestHash -cne $DecisionManifest.DecisionManifestHash) { throw 'FAIL_CLOSED: accepted state binding mismatch.' }
    if ($OutputManifest.GenerationId -cne $AcceptedState.GenerationId -or $OutputManifest.AcceptedStateHash -cne $AcceptedState.AcceptedStateHash -or $AcceptedState.AcceptedOutputManifestHash -cne $OutputManifest.OutputManifestHash -or $OutputManifest.ActiveXMLTVStatus -ne $AcceptedState.AcceptedXMLTVStatus) { throw 'FAIL_CLOSED: output binding mismatch.' }
    if ($null -ne $GenerationId -and $OutputManifest.GenerationId -cne $GenerationId) { throw 'FAIL_CLOSED: generation binding mismatch.' }
    return [pscustomobject][ordered]@{ CandidateManifestHash = $CandidateManifestHash; BuildIdentity = $BuildIdentity; GenerationId = $AcceptedState.GenerationId; DecisionManifestHash = $DecisionManifest.DecisionManifestHash; AcceptedStateHash = $AcceptedState.AcceptedStateHash; AcceptedOutputManifestHash = $OutputManifest.OutputManifestHash }
}


function Test-ChannelForgePreviousLineage {
    param([Parameter(Mandatory)]$AcceptedState,[AllowNull()]$GenerationManifest,[AllowNull()]$PreviousM3U,[AllowNull()]$PreviousXMLTV,[AllowNull()]$PriorState,[AllowNull()]$PriorOutput)
    $first = $null -eq $AcceptedState.PreviousStateHash
    if ($first) {
        if ($null -ne $GenerationManifest -or $null -ne $PreviousM3U -or $null -ne $PreviousXMLTV -or $null -ne $PriorState -or $null -ne $PriorOutput) { throw 'FAIL_CLOSED: first generation cannot have prior lineage.' }
        return [pscustomobject][ordered]@{ PreviousStateHash = $null; PreviousOutputManifestHash = $null; PreviousGenerationId = $null }
    }
    if ($null -eq $GenerationManifest -or $null -eq $PreviousM3U -or $null -eq $PreviousXMLTV -or $null -eq $PriorState -or $null -eq $PriorOutput) { throw 'FAIL_CLOSED: later generation requires complete prior lineage.' }
    if ($null -eq $GenerationManifest.PreviousOutputManifestHash -or $AcceptedState.PreviousStateHash -cne $PriorState.AcceptedStateHash -or $GenerationManifest.PreviousOutputManifestHash -cne $PriorOutput.OutputManifestHash -or $PreviousM3U.OutputManifestHash -cne $PriorOutput.OutputManifestHash -or $PreviousXMLTV.OutputManifestHash -cne $PriorOutput.OutputManifestHash -or $PreviousM3U.AcceptedStateHash -cne $PriorState.AcceptedStateHash -or $PreviousXMLTV.AcceptedStateHash -cne $PriorState.AcceptedStateHash -or $PreviousM3U.GenerationId -cne $AcceptedState.GenerationId -or $PreviousXMLTV.GenerationId -cne $AcceptedState.GenerationId -or $PreviousM3U.PreviousGenerationId -cne $PriorState.GenerationId -or $PreviousXMLTV.PreviousGenerationId -cne $PriorState.GenerationId) { throw 'FAIL_CLOSED: previous state/output lineage mismatch.' }
    if ($null -ne $GenerationManifest.GenerationId -and $GenerationManifest.GenerationId -cne $AcceptedState.GenerationId) { throw 'FAIL_CLOSED: generation manifest identity mismatch.' }
    return [pscustomobject][ordered]@{ PreviousStateHash = $AcceptedState.PreviousStateHash; PreviousOutputManifestHash = $PriorOutput.OutputManifestHash; PreviousGenerationId = $PriorState.GenerationId }
}

function Get-ChannelForgeAcceptanceDecisionRecords {
    param([Parameter(Mandatory)]$DecisionManifest,[AllowNull()][AllowEmptyCollection()][object[]]$DecisionRecords = @())
    $embedded = $DecisionManifest.PSObject.Properties['Decisions']
    if ($null -ne $embedded) {
        $decisions = @($embedded.Value)
        if (@($DecisionRecords).Count -gt 0 -and (($decisions | ForEach-Object DecisionId) -join ',' -cne (@($DecisionRecords) | ForEach-Object DecisionId) -join ',')) {
            throw 'FAIL_CLOSED: decision records disagree with the decision manifest.'
        }
        return $decisions
    }
    return @($DecisionRecords)
}

function Assert-ChannelForgeAcceptanceDecisionCoverage {
    param(
        [Parameter(Mandatory)]$CandidateManifest,
        [Parameter(Mandatory)]$DecisionManifest,
        [Parameter(Mandatory)]$M3UDecision,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$AcceptedParentEntries,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Decisions
    )
    if ($null -eq $AcceptedParentEntries) { $AcceptedParentEntries = @() }
    if ($null -eq $Decisions) { $Decisions = @() }
    Assert-ChannelForgeCandidateVersion $CandidateManifest 'CandidateManifest'
    Assert-ChannelForgeAcceptanceVersion $DecisionManifest 'DecisionManifest'
    Assert-ChannelForgeAcceptanceVersion $M3UDecision 'M3UDecision'
    if (-not (Test-ChannelForgeAcceptanceHashProperty $M3UDecision 'decision-m3u/v2' 'M3UDecisionHash')) { throw 'FAIL_CLOSED: forged M3U decision hash.' }
    if ([string]$M3UDecision.CandidateManifestHash -cne [string]$DecisionManifest.CandidateManifestHash -or [string]$M3UDecision.BuildIdentity -cne [string]$DecisionManifest.BuildIdentity) { throw 'FAIL_CLOSED: M3U decision binding mismatch.' }
    $candidateIds = @($CandidateManifest.Entries | ForEach-Object { [string]$_.EntryId } | Sort-Object)
    $acceptedIds = @($AcceptedParentEntries | ForEach-Object { [string]$_.EntryId } | Sort-Object)
    $bindingIds = @($CandidateManifest.BindingRecords | ForEach-Object { [string]$_.BindingId } | Sort-Object)
    Assert-ChannelForgeAcceptanceIds $candidateIds 'CandidateManifest.Entries'
    Assert-ChannelForgeAcceptanceIds $acceptedIds 'AcceptedParentEntries'
    Assert-ChannelForgeAcceptanceIds $bindingIds 'CandidateManifest.BindingRecords'
    if ($null -eq $DecisionManifest.PSObject.Properties['DecisionIds']) { throw 'FAIL_CLOSED: DecisionManifest.DecisionIds is required.' }
    $manifestDecisionIds = @($DecisionManifest.DecisionIds)
    Assert-ChannelForgeAcceptanceIds $manifestDecisionIds 'DecisionIds'
    Assert-ChannelForgeAcceptanceDecisionRecords $Decisions
    if (([string]::Join('|', $manifestDecisionIds)) -cne ([string]::Join('|', @($Decisions | ForEach-Object DecisionId)))) { throw 'FAIL_CLOSED: decision IDs do not match records.' }
    foreach ($name in @('IncludedCandidateEntryIds','ExcludedCandidateEntryIds')) {
        $property = $M3UDecision.PSObject.Properties[$name]
        if ($null -eq $property -or $null -eq $property.Value) { throw "FAIL_CLOSED: M3UDecision.$name is required." }
    }
    $includedIds = @($M3UDecision.IncludedCandidateEntryIds)
    $excludedIds = @($M3UDecision.ExcludedCandidateEntryIds)
    Assert-ChannelForgeAcceptanceIds $includedIds 'IncludedCandidateEntryIds'
    Assert-ChannelForgeAcceptanceIds $excludedIds 'ExcludedCandidateEntryIds'
    if (([string]::Join('|', $candidateIds)) -cne ([string]::Join('|', @($includedIds + $excludedIds | Sort-Object)))) { throw 'FAIL_CLOSED: decision entry partition is incomplete.' }
    $candidateById = @{}; foreach ($entry in @($CandidateManifest.Entries)) { $candidateById[[string]$entry.EntryId] = $entry }
    $acceptedById = @{}; foreach ($entry in @($AcceptedParentEntries)) { $acceptedById[[string]$entry.EntryId] = $entry }
    $bindingById = @{}; foreach ($binding in @($CandidateManifest.BindingRecords)) { $bindingById[[string]$binding.BindingId] = $binding }
    $coveredCandidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $coveredAccepted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $coveredBindings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $expectedGenerationId = $null
    foreach ($owner in @($CandidateManifest,$DecisionManifest)) {
        if ($null -ne $owner.PSObject.Properties['GenerationId']) { $expectedGenerationId = [string]$owner.GenerationId; Assert-ChannelForgeAcceptanceGenerationId $expectedGenerationId 'GenerationId'; break }
    }
    foreach ($decision in @($Decisions)) {
        $type = [string]$decision.DecisionType
        if ($null -ne $decision.PSObject.Properties['Version']) { Assert-ChannelForgeAcceptanceVersion $decision 'DecisionRecord' }
        if ($null -ne $decision.PSObject.Properties['GenerationId']) {
            Assert-ChannelForgeAcceptanceGenerationId $decision.GenerationId 'DecisionRecord.GenerationId'
            if ($null -ne $expectedGenerationId -and [string]$decision.GenerationId -cne $expectedGenerationId) { throw 'FAIL_CLOSED: stale decision generation.' }
        }
        foreach ($name in @('ReviewStatus','ResolutionStatus')) {
            if ($null -ne $decision.PSObject.Properties[$name] -and [string]$decision.$name -in @('Unresolved','ReviewNeeded','Pending','Ambiguous','Conflicting')) { throw 'FAIL_CLOSED: unresolved actionable review.' }
        }
        switch ($type) {
            'IncludeCandidateEntry' {
                $id = [string]$decision.CandidateEntryId
                if (-not $candidateById.ContainsKey($id) -or -not $includedIds.Contains($id) -or -not $coveredCandidates.Add($id)) { throw 'FAIL_CLOSED: invalid or conflicting included candidate decision.' }
            }
            'MapCandidateToAcceptedEntry' {
                $candidateId = [string]$decision.CandidateEntryId; $acceptedId = [string]$decision.AcceptedEntryId
                if (-not $candidateById.ContainsKey($candidateId) -or -not $acceptedById.ContainsKey($acceptedId) -or -not $includedIds.Contains($candidateId) -or -not $coveredCandidates.Add($candidateId)) { throw 'FAIL_CLOSED: invalid or conflicting candidate mapping.' }
                if (-not $coveredAccepted.Add($acceptedId)) { throw 'FAIL_CLOSED: conflicting accepted entry decision.' }
            }
            'ExcludeCandidateEntry' {
                $id = [string]$decision.CandidateEntryId
                if (-not $candidateById.ContainsKey($id) -or -not $excludedIds.Contains($id) -or -not $coveredCandidates.Add($id)) { throw 'FAIL_CLOSED: invalid or conflicting excluded candidate decision.' }
            }
            'KeepAcceptedEntry' {
                $id = [string]$decision.AcceptedEntryId
                if (-not $acceptedById.ContainsKey($id) -or -not $coveredAccepted.Add($id)) { throw 'FAIL_CLOSED: invalid or conflicting retained entry decision.' }
            }
            'AcceptGuideBinding' {
                $id = [string]$decision.BindingId
                if (-not $bindingById.ContainsKey($id) -or -not $coveredBindings.Add($id)) { throw 'FAIL_CLOSED: invalid or conflicting binding decision.' }
            }
            default { throw 'FAIL_CLOSED: unsupported decision type.' }
        }
    }
    foreach ($id in $candidateIds) { if (-not $coveredCandidates.Contains($id)) { throw 'FAIL_CLOSED: candidate entry lacks an explicit decision.' } }
    foreach ($id in $acceptedIds) {
        if ($candidateById.ContainsKey($id) -and $coveredCandidates.Contains($id)) { continue }
        if (-not $coveredAccepted.Contains($id)) { throw 'FAIL_CLOSED: accepted parent entry lacks an explicit decision.' }
    }
    foreach ($id in $includedIds) { if (-not $coveredCandidates.Contains($id)) { throw 'FAIL_CLOSED: included candidate lacks an explicit decision.' } }
}

function New-ChannelForgeAcceptedEntries {
    param([Parameter(Mandatory)]$CandidateManifest,[Parameter(Mandatory)]$DecisionManifest,[Parameter(Mandatory)]$M3UDecision,[AllowNull()][AllowEmptyCollection()][object[]]$AcceptedParentEntries = @(),[Alias('Decisions')][AllowNull()][AllowEmptyCollection()][object[]]$DecisionRecords = @())
    $decisions = @(Get-ChannelForgeAcceptanceDecisionRecords $DecisionManifest $DecisionRecords)
    Assert-ChannelForgeAcceptanceDecisionCoverage $CandidateManifest $DecisionManifest $M3UDecision $AcceptedParentEntries $decisions
    $candidateById = @{}; foreach ($entry in @($CandidateManifest.Entries)) { $candidateById[[string]$entry.EntryId] = $entry }
    $acceptedById = @{}; foreach ($entry in @($AcceptedParentEntries)) { $acceptedById[[string]$entry.EntryId] = $entry }
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($decision in $decisions) {
        $entryId = switch ([string]$decision.DecisionType) {
            'IncludeCandidateEntry' { [string]$decision.CandidateEntryId }
            'MapCandidateToAcceptedEntry' { [string]$decision.CandidateEntryId }
            'KeepAcceptedEntry' { [string]$decision.AcceptedEntryId }
            default { $null }
        }
        if ($null -eq $entryId) { continue }
        if ([string]$decision.DecisionType -eq 'KeepAcceptedEntry') { [void]$result.Add($acceptedById[$entryId]) }
        else { [void]$result.Add($candidateById[$entryId]) }
    }
    return @($result | Sort-Object -Property @{Expression={ [string]$_.EntryId }; Ascending=$true})
}
function New-ChannelForgeAcceptedBindings {
    param([Parameter(Mandatory)]$CandidateManifest,[Parameter(Mandatory)]$DecisionManifest,[Parameter(Mandatory)]$M3UDecision,[AllowNull()][AllowEmptyCollection()][object[]]$AcceptedParentEntries = @(),[Alias('Decisions')][AllowNull()][AllowEmptyCollection()][object[]]$DecisionRecords = @())
    $decisions = @(Get-ChannelForgeAcceptanceDecisionRecords $DecisionManifest $DecisionRecords)
    Assert-ChannelForgeAcceptanceDecisionCoverage $CandidateManifest $DecisionManifest $M3UDecision $AcceptedParentEntries $decisions
    if (([string]::Join('|', @($DecisionManifest.DecisionIds))) -cne ([string]::Join('|', @($decisions | ForEach-Object DecisionId)))) { throw 'FAIL_CLOSED: decision IDs do not match records.' }
    $byId = @{}; foreach ($binding in @($CandidateManifest.BindingRecords)) { $byId[[string]$binding.BindingId] = $binding }
    $result = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($decision in $decisions) {
        if ([string]$decision.DecisionType -eq 'AcceptGuideBinding') {
            $id = [string]$decision.BindingId
            if (-not $byId.ContainsKey($id) -or -not $seen.Add($id)) { throw 'FAIL_CLOSED: accepted binding is missing or conflicting.' }
            [void]$result.Add($byId[$id])
        }
    }
    return @($result | Sort-Object -Property @{Expression={ [string]$_.BindingId }; Ascending=$true})
}

function Compare-ChannelForgeCandidateToAccepted {
    param([Parameter(Mandatory)]$CandidateManifest,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AcceptedEntries,[AllowNull()][AllowEmptyCollection()][object[]]$AcceptedBindings = @())
    $candidateById = @{}; foreach ($entry in @($CandidateManifest.Entries)) { $candidateById[[string]$entry.EntryId] = $entry }
    $acceptedById = @{}; foreach ($entry in @($AcceptedEntries)) { $acceptedById[[string]$entry.EntryId] = $entry }
    $records = [System.Collections.Generic.List[object]]::new(); $reviews = [System.Collections.Generic.List[object]]::new(); $matchedAccepted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $makeRecord = {
        param($classification,$candidate,$accepted,$evidence,$reviewId)
        $projection = [ordered]@{ ChangeRecordId = $null; Classification = $classification; CandidateEntryId = if ($null -eq $candidate) { $null } else { [string]$candidate.EntryId }; AcceptedEntryId = if ($null -eq $accepted) { $null } else { [string]$accepted.EntryId }; CandidateEntryProjection = $candidate; AcceptedEntryProjection = $accepted; Evidence = @($evidence); ReviewId = $reviewId }
        $without = [ordered]@{}; foreach ($property in $projection.GetEnumerator()) { if ($property.Key -ne 'ChangeRecordId') { $without[$property.Key] = $property.Value } }
        $projection.ChangeRecordId = Get-ChannelForgeDomainHash -Domain 'change-record/v2' -InputObject $without
        [pscustomobject]$projection
    }
    foreach ($candidate in @($CandidateManifest.Entries | Sort-Object -Property @{Expression={ [string]$_.EntryId }; Ascending=$true})) {
        $candidateId = [string]$candidate.EntryId; $accepted = $null
        if ($acceptedById.ContainsKey($candidateId)) { $accepted = $acceptedById[$candidateId]; [void]$matchedAccepted.Add($candidateId) }
        else {
            $candidateHistory = [string]$candidate.HistoryKey
            $sameHistory = if ([string]::IsNullOrEmpty($candidateHistory)) { @() } else { @($AcceptedEntries | Where-Object { [string]$_.HistoryKey -ceq $candidateHistory }) }
            $candidateStable = [string]$candidate.HistoryIdentityStatus -in @('Unique','StableUnique')
            $acceptedStable = $sameHistory.Count -eq 1 -and [string]$sameHistory[0].HistoryIdentityStatus -in @('Unique','StableUnique')
            if ($sameHistory.Count -eq 1 -and $candidateStable -and $acceptedStable) { $accepted = $sameHistory[0]; [void]$matchedAccepted.Add([string]$accepted.EntryId) }
        }
        if ($null -eq $accepted) { [void]$records.Add((& $makeRecord 'Added' $candidate $null @([ordered]@{ EvidenceType = 'CandidateOnly'; Value = $candidateId; Ordinal = 0 }) $null)); continue }
        $streamSame = ([string]$candidate.StreamFingerprint -ceq [string]$accepted.StreamFingerprint)
        $presentationSame = ([string]$candidate.PresentationFingerprint -ceq [string]$accepted.PresentationFingerprint)
        $sameId = $candidateId -ceq [string]$accepted.EntryId
        $classification = if (-not $sameId -and $streamSame -and -not $presentationSame) { 'Renamed' } elseif (-not $sameId) { 'IdentityChanged' } elseif ($streamSame -and $presentationSame) { 'Unchanged' } elseif ($streamSame) { 'Renamed' } elseif (-not $presentationSame) { 'StreamAndPresentationChanged' } else { 'StreamChanged' }
        $reviewId = $null
        if ($classification -eq 'IdentityChanged' -or $classification -eq 'StreamAndPresentationChanged') {
            $review = New-ChannelForgeReviewRecord -ReviewCategory Actionable -Classification ReviewNeeded -ReasonCode $classification -CandidateEntryIds @($candidate.EntryId) -AcceptedEntryIds @($accepted.EntryId) -CandidateBindingIds @() -DecisionTypesAllowed @('MapCandidateToAcceptedEntry') -Evidence @([ordered]@{ EvidenceType = 'EntryComparison'; Value = $classification; Ordinal = 0 })
            [void]$reviews.Add($review); $reviewId = $review.ReviewId
        }
        [void]$records.Add((& $makeRecord $classification $candidate $accepted @([ordered]@{ EvidenceType = 'EntryComparison'; Value = $classification; Ordinal = 0 }) $reviewId))
    }
    foreach ($accepted in @($AcceptedEntries | Sort-Object -Property @{Expression={ [string]$_.EntryId }; Ascending=$true})) {
        if (-not $matchedAccepted.Contains([string]$accepted.EntryId)) { [void]$records.Add((& $makeRecord 'Removed' $null $accepted @([ordered]@{ EvidenceType = 'AcceptedOnly'; Value = [string]$accepted.EntryId; Ordinal = 0 }) $null)) }
    }
    return [pscustomobject][ordered]@{ ChangeRecords = @($records | Sort-Object -Property @{Expression={ [string]$_.ChangeRecordId }; Ascending=$true}); ReviewRecords = @($reviews | Sort-Object -Property @{Expression={ [string]$_.ReviewId }; Ascending=$true}); AcceptedBindings = @($AcceptedBindings | Sort-Object -Property @{Expression={ [string]$_.BindingId }; Ascending=$true}) }
}
