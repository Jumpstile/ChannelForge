function Get-ChannelForgeWebAcceptanceLimits {
    return [pscustomobject][ordered]@{ MaxRequestBodyBytes = 8KB; MaxJsonDepth = 4 }
}

function Get-ChannelForgeWebProposalStorageRoot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    return Join-Path (Get-ChannelForgeWebProposalStagingRoot -RepositoryRoot $RepositoryRoot) 'proposals'
}

function Assert-ChannelForgeWebProposalId {
    param([Parameter(Mandatory)][string]$ProposalId)
    if ($ProposalId -cnotmatch '^[0-9a-f]{32}$') { throw 'INVALID_PROPOSAL: The proposal could not be found.' }
}

function Get-ChannelForgeWebProposalDirectory {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProposalId)
    Assert-ChannelForgeWebProposalId -ProposalId $ProposalId
    return Join-Path (Get-ChannelForgeWebProposalStorageRoot -RepositoryRoot $RepositoryRoot) $ProposalId
}

function Get-ChannelForgeWebProposalSessionPath {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProposalId)
    return Join-Path (Get-ChannelForgeWebProposalDirectory -RepositoryRoot $RepositoryRoot -ProposalId $ProposalId) 'session.json'
}

function Get-ChannelForgeWebProposalSessionHash {
    param([Parameter(Mandatory)]$Session)
    $projection = [ordered]@{}
    foreach ($property in @($Session.PSObject.Properties)) {
        if ($property.Name -ne 'SessionHash') { $projection[$property.Name] = $property.Value }
    }
    return Get-ChannelForgeDomainHash -Domain 'guided-setup-review/v1' -InputObject $projection
}

function Write-ChannelForgeWebProposalSession {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Session,[switch]$Replace)
    $proposalId = [string]$Session.ProposalId
    Assert-ChannelForgeWebProposalId -ProposalId $proposalId
    $storageRoot = Get-ChannelForgeWebProposalStorageRoot -RepositoryRoot $RepositoryRoot
    $proposalDirectory = Get-ChannelForgeWebProposalDirectory -RepositoryRoot $RepositoryRoot -ProposalId $proposalId
    Assert-ChannelForgeWritePath -Path $storageRoot -AllowedRoot (Get-ChannelForgeWebProposalStagingRoot -RepositoryRoot $RepositoryRoot)
    Assert-ChannelForgeWritePath -Path $proposalDirectory -AllowedRoot $storageRoot
    New-Item -ItemType Directory -Force -Path $proposalDirectory | Out-Null
    $ordered = [ordered]@{}
    foreach ($property in @($Session.PSObject.Properties)) {
        if ($property.Name -ne 'SessionHash') { $ordered[$property.Name] = $property.Value }
    }
    $ordered.SessionHash = Get-ChannelForgeWebProposalSessionHash -Session ([pscustomobject]$ordered)
    $bytes = [Text.UTF8Encoding]::new($false,$true).GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $ordered))
    $path = Get-ChannelForgeWebProposalSessionPath -RepositoryRoot $RepositoryRoot -ProposalId $proposalId
    $temporary = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllBytes($temporary, $bytes)
    try {
        if ([IO.File]::Exists($path)) {
            if (-not $Replace) { throw 'FAIL_CLOSED: proposal session already exists.' }
            [IO.File]::Move($temporary, $path, $true)
        }
        else { [IO.File]::Move($temporary, $path) }
    }
    finally {
        if ([IO.File]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
    return [pscustomobject]$ordered
}

function Read-ChannelForgeWebProposalSession {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProposalId)
    $path = Get-ChannelForgeWebProposalSessionPath -RepositoryRoot $RepositoryRoot -ProposalId $ProposalId
    if (-not [IO.File]::Exists($path)) { throw 'NOT_FOUND: The reviewed proposal is no longer available.' }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'FAIL_CLOSED: proposal session is unsafe.' }
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    try {
        $bytes = [IO.File]::ReadAllBytes($path)
        $text = $utf8.GetString($bytes)
        $session = $text | ConvertFrom-Json -DateKind String -ErrorAction Stop
        if ($utf8.GetString($utf8.GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $session))) -cne $text) { throw 'non-canonical session' }
    }
    catch { throw 'FAIL_CLOSED: reviewed proposal metadata is invalid.' }
    Assert-ChannelForgeWebProposalId -ProposalId ([string]$session.ProposalId)
    if ([string]$session.ProposalId -cne $ProposalId -or [string]$session.Version -notin @('guided-setup/review/v1', 'guided-setup/review/v2') -or [string]$session.SessionHash -cne (Get-ChannelForgeWebProposalSessionHash -Session $session)) {
        throw 'FAIL_CLOSED: reviewed proposal metadata is not authentic.'
    }
    return $session
}

function Get-ChannelForgeWebCurrentAcceptedSnapshot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $null = Recover-ChannelForgeAcceptedStateCore -RepositoryRoot $RepositoryRoot
    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $RepositoryRoot
    return Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $RepositoryRoot -Paths $paths
}

function Get-ChannelForgeWebProposalCandidate {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)]$Session)
    $proposalDirectory = Get-ChannelForgeWebProposalDirectory -RepositoryRoot $RepositoryRoot -ProposalId ([string]$Session.ProposalId)
    $candidateDirectory = Join-Path $proposalDirectory ([string]$Session.CandidateDirectoryRelative -replace '/', '\')
    $candidateHash = [string]$Session.CandidateManifestHash
    if ($candidateDirectory -notlike "$(Get-ChannelForgeWebProposalStorageRoot -RepositoryRoot $RepositoryRoot)\*") { throw 'FAIL_CLOSED: proposal candidate path is invalid.' }
    if (-not (Test-ChannelForgeCandidateNamespace -Directory $candidateDirectory -ManifestHash $candidateHash)) { throw 'FAIL_CLOSED: reviewed candidate bytes failed verification.' }
    $manifestPath = Join-Path $candidateDirectory 'manifest.json'
    $manifest = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($manifestPath)) | ConvertFrom-Json -ErrorAction Stop
    $m3uBytes = [IO.File]::ReadAllBytes((Join-Path $candidateDirectory 'merged.m3u'))
    $xmltvPath = Join-Path $candidateDirectory 'merged.xml'
    $xmltvBytes = if ([IO.File]::Exists($xmltvPath)) { [IO.File]::ReadAllBytes($xmltvPath) } else { $null }
    if ([string]$manifest.BuildIdentity -cne [string]$Session.BuildIdentity) { throw 'FAIL_CLOSED: reviewed candidate identity changed.' }
    return [pscustomobject][ordered]@{ Directory = $candidateDirectory; Manifest = $manifest; M3UBytes = $m3uBytes; XMLTVBytes = $xmltvBytes }
}
function Get-ChannelForgeGuidedSetupSourceInputs {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Session
    )
    if ([string]$Session.SourceSetVersion -ceq 'source-set/v2') {
        return Get-ChannelForgeGuidedSetupSourceSetInputs -RepositoryRoot $RepositoryRoot -Session $Session
    }

    $proposalDirectory = Get-ChannelForgeWebProposalDirectory -RepositoryRoot $RepositoryRoot -ProposalId ([string]$Session.ProposalId)
    Assert-ChannelForgeSourceEnrollmentDirectory -Path $proposalDirectory | Out-Null
    $m3uRelative = [string]$Session.SourceM3URelative
    if ($m3uRelative -cne 'input.m3u') { throw 'FAIL_CLOSED: guided setup source reference is invalid.' }
    $m3uPath = Assert-ChannelForgeSourceEnrollmentPath -Path (Join-Path $proposalDirectory $m3uRelative) -AllowedRoot $proposalDirectory
    if (-not [IO.File]::Exists($m3uPath)) { throw 'FAIL_CLOSED: guided setup playlist bytes are unavailable.' }
    $xmltvPath = $null
    if ($null -ne $Session.SourceXMLTVRelative) {
        if ([string]$Session.SourceXMLTVRelative -cne 'guide.xml') { throw 'FAIL_CLOSED: guided setup guide reference is invalid.' }
        $xmltvPath = Assert-ChannelForgeSourceEnrollmentPath -Path (Join-Path $proposalDirectory ([string]$Session.SourceXMLTVRelative)) -AllowedRoot $proposalDirectory
        if (-not [IO.File]::Exists($xmltvPath)) { throw 'FAIL_CLOSED: guided setup guide bytes are unavailable.' }
    }
    return [pscustomobject][ordered]@{
        M3UBytes = [IO.File]::ReadAllBytes($m3uPath)
        XMLTVBytes = if ($null -eq $xmltvPath) { $null } else { [IO.File]::ReadAllBytes($xmltvPath) }
        M3UPath = $m3uPath
        XMLTVPath = $xmltvPath
    }
}

function ConvertFrom-ChannelForgeGuidedSetupAcceptanceRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$BodyBytes)
    $limits = Get-ChannelForgeWebAcceptanceLimits
    if ($BodyBytes.Length -gt $limits.MaxRequestBodyBytes) { throw [InvalidOperationException]::new('request-too-large') }
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($utf8.GetString($BodyBytes), [System.Text.Json.JsonDocumentOptions]@{ MaxDepth = $limits.MaxJsonDepth; CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow; AllowTrailingCommas = $false })
    }
    catch { throw [ArgumentException]::new('invalid-request') }
    try {
        $root = $document.RootElement
        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw [ArgumentException]::new('invalid-request') }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $schema = $null; $proposal = $null; $acknowledged = $null
        foreach ($property in $root.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) { throw [ArgumentException]::new('invalid-request') }
            switch ($property.Name) {
                'schemaVersion' { $schema = $property.Value }
                'proposalId' { $proposal = $property.Value }
                'acknowledged' { $acknowledged = $property.Value }
                default { throw [ArgumentException]::new('invalid-request') }
            }
        }
        $version = 0
        if ($null -eq $schema -or $schema.ValueKind -ne [Text.Json.JsonValueKind]::Number -or -not $schema.TryGetInt32([ref]$version) -or $version -ne 1 -or $null -eq $proposal -or $proposal.ValueKind -ne [Text.Json.JsonValueKind]::String -or $null -eq $acknowledged -or $acknowledged.ValueKind -ne [Text.Json.JsonValueKind]::True) { throw [ArgumentException]::new('invalid-request') }
        $proposalId = $proposal.GetString()
        Assert-ChannelForgeWebProposalId -ProposalId $proposalId
        return [pscustomobject][ordered]@{ SchemaVersion = 1; ProposalId = $proposalId; Acknowledged = $true }
    }
    finally { $document.Dispose() }
}

function New-ChannelForgeWebAcceptanceResponse {
    param([Parameter(Mandatory)][int]$StatusCode,[Parameter(Mandatory)][string]$ErrorCode,[Parameter(Mandatory)][string]$Message,[Parameter(Mandatory)][System.Collections.IDictionary]$Headers)
    return New-ChannelForgeWebProposalErrorResponse -StatusCode $StatusCode -ErrorCode $ErrorCode -Message $Message -Headers $Headers
}

function Get-ChannelForgeGuidedSetupAcceptanceResponse {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$BodyBytes,[Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][System.Collections.IDictionary]$Headers,[string]$ContentType = 'application/json')
    if ([string]::IsNullOrWhiteSpace($ContentType) -or $ContentType.Split(';',2)[0].Trim().ToLowerInvariant() -ne 'application/json') { return New-ChannelForgeWebAcceptanceResponse 415 'unsupported-content-type' 'The acceptance request must use application/json.' $Headers }
    try { $request = ConvertFrom-ChannelForgeGuidedSetupAcceptanceRequest -BodyBytes $BodyBytes }
    catch [InvalidOperationException] { return New-ChannelForgeWebAcceptanceResponse 413 'request-too-large' 'The acceptance request is too large.' $Headers }
    catch { return New-ChannelForgeWebAcceptanceResponse 400 'invalid-acceptance-request' 'The acceptance request is invalid.' $Headers }

    try {
        $session = Read-ChannelForgeWebProposalSession -RepositoryRoot $RepositoryRoot -ProposalId $request.ProposalId
        if ([string]$session.Status -ceq 'Accepted') { return New-ChannelForgeWebAcceptanceResponse 409 'already-accepted' 'This reviewed proposal has already been accepted and cannot be submitted again.' $Headers }
        if ([string]$session.Status -cne 'Ready') { return New-ChannelForgeWebAcceptanceResponse 409 'proposal-unavailable' 'This reviewed proposal is not available for acceptance.' $Headers }
        if (-not [bool]$session.CanAccept) { return New-ChannelForgeWebAcceptanceResponse 409 'proposal-blocked' 'This proposal has unresolved review blockers and cannot be accepted.' $Headers }

        $sourceInputs = Get-ChannelForgeGuidedSetupSourceInputs -RepositoryRoot $RepositoryRoot -Session $session
        $candidate = Get-ChannelForgeWebProposalCandidate -RepositoryRoot $RepositoryRoot -Session $session
        $bindings = @($candidate.Manifest.BindingRecords | Where-Object { [string]$_.BindingKind -eq 'M3U' })
        if (@($bindings | Where-Object { [string]$_.Status -eq 'ReviewNeeded' }).Count -gt 0) { return New-ChannelForgeWebAcceptanceResponse 409 'proposal-blocked' 'This proposal has unresolved review blockers and cannot be accepted.' $Headers }
        $current = Get-ChannelForgeWebCurrentAcceptedSnapshot -RepositoryRoot $RepositoryRoot
        $currentParent = if ($null -eq $current) { $null } else { [string]$current.Manifest.Object.GenerationManifestHash }
        $currentState = if ($null -eq $current) { $null } else { [string]$current.State.Object.AcceptedStateHash }
        $currentOutput = if ($null -eq $current) { $null } else { [string]$current.Output.Object.OutputManifestHash }
        $expectedParent = if ([string]::IsNullOrWhiteSpace([string]$session.ParentGenerationManifestHash)) { $null } else { [string]$session.ParentGenerationManifestHash }
        $expectedState = if ([string]::IsNullOrWhiteSpace([string]$session.ParentAcceptedStateHash)) { $null } else { [string]$session.ParentAcceptedStateHash }
        $expectedOutput = if ([string]::IsNullOrWhiteSpace([string]$session.ParentOutputManifestHash)) { $null } else { [string]$session.ParentOutputManifestHash }
        if ($currentParent -cne $expectedParent -or $currentState -cne $expectedState -or $currentOutput -cne $expectedOutput) { return New-ChannelForgeWebAcceptanceResponse 409 'stale-proposal' 'The accepted lineup changed after this review. Nothing was published; analyze the files again.' $Headers }

        $entryIds = @($candidate.Manifest.Entries | ForEach-Object EntryId | Sort-Object)
        $decisions = @($entryIds | ForEach-Object { New-ChannelForgeAcceptanceDecision -DecisionType 'IncludeCandidateEntry' -CandidateEntryId ([string]$_) -BindingId $null -ReasonCode 'GuidedSetupBrowserAccepted' } | Sort-Object DecisionId)
        $accepted = Publish-ChannelForgeReviewedCandidate `
            -RepositoryRoot $RepositoryRoot `
            -CandidateManifest $candidate.Manifest `
            -M3UBytes $candidate.M3UBytes `
            -XMLTVBytes $candidate.XMLTVBytes `
            -DecisionRecords $decisions `
            -IncludedEntryIds $entryIds `
            -ExcludedEntryIds @() `
            -ExpectedParentGenerationManifestHash $expectedParent
        $enrollmentStatus = 'REPAIR_REQUIRED'
        $enrollmentMessage = 'Lineup accepted, but saved sources need repair.'
        try {
            if ([string]$session.SourceSetVersion -ceq 'source-set/v2') {
                $enrollment = Write-ChannelForgeSourceEnrollment `
                    -RepositoryRoot $RepositoryRoot `
                    -PlaylistSources $sourceInputs.PlaylistSources `
                    -GuideSources $sourceInputs.GuideSources `
                    -Bindings $sourceInputs.Bindings `
                    -AcceptedGenerationManifestHash ([string]$accepted.GenerationManifest.GenerationManifestHash) `
                    -AcceptedStateHash ([string]$accepted.AcceptedState.AcceptedStateHash) `
                    -AcceptedOutputManifestHash ([string]$accepted.AcceptedOutputManifest.OutputManifestHash)
                foreach ($stagedPath in @($sourceInputs.StagedPaths)) {
                    Remove-Item -LiteralPath $stagedPath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                $enrollment = Write-ChannelForgeSourceEnrollment `
                    -RepositoryRoot $RepositoryRoot `
                    -M3UBytes $sourceInputs.M3UBytes `
                    -XMLTVBytes $sourceInputs.XMLTVBytes `
                    -AcceptedGenerationManifestHash ([string]$accepted.GenerationManifest.GenerationManifestHash) `
                    -AcceptedStateHash ([string]$accepted.AcceptedState.AcceptedStateHash) `
                    -AcceptedOutputManifestHash ([string]$accepted.AcceptedOutputManifest.OutputManifestHash)
                Remove-Item -LiteralPath $sourceInputs.M3UPath -Force -ErrorAction SilentlyContinue
                if ($null -ne $sourceInputs.XMLTVPath) { Remove-Item -LiteralPath $sourceInputs.XMLTVPath -Force -ErrorAction SilentlyContinue }
            }
            $enrollmentStatus = 'SAVED'
            $enrollmentMessage = 'Sources saved for restart-safe refresh.'
        }
        catch {
            $enrollment = $null
            $enrollmentMessage = 'Lineup accepted, but saved sources need repair before refresh.'
        }

        $acceptedSession = [ordered]@{}
        foreach ($property in @($session.PSObject.Properties)) { $acceptedSession[$property.Name] = $property.Value }
        $acceptedSession.Status = 'Accepted'
        $acceptedSession.EnrollmentStatus = $enrollmentStatus
        $acceptedSession.AcceptedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        $null = Write-ChannelForgeWebProposalSession -RepositoryRoot $RepositoryRoot -Session ([pscustomobject]$acceptedSession) -Replace
        $body = ([ordered]@{
            Version = if ([string]$session.Version -ceq 'guided-setup/review/v2') { 'guided-setup/acceptance/v2' } else { 'guided-setup/acceptance/v1' }
            Status = 'ACCEPTED'
            EnrollmentStatus = $enrollmentStatus
            Message = $enrollmentMessage
            Proposal = [ordered]@{
                ChannelCount = $entryIds.Count
                GuideStatus = if ([string]$session.Version -ceq 'guided-setup/review/v2') {
                    if (@($session.SourceSet.Guides).Count -eq 0) { 'NO_GUIDE_SELECTED' } elseif ([int]$session.UnboundGuideCount -gt 0) { 'XMLTV_ACCEPTED_WITH_UNBOUND' } else { 'XMLTV_ACCEPTED' }
                } elseif ($null -eq $candidate.XMLTVBytes) { 'NO_GUIDE_SELECTED' } else { 'XMLTV_ACCEPTED' }
            }
            Safety = [ordered]@{ AcceptedStateMutation = 'accepted-lineup'; ProviderMutation = 'none'; DownstreamMutation = 'none'; SchedulerMutation = 'none' }
        } | ConvertTo-Json -Depth 6 -Compress)
        return New-ChannelForgeWebResponse -StatusCode 200 -ContentType 'application/json; charset=utf-8' -Body $body -Headers $Headers
    }
    catch {
        $message = [string]$_.Exception.Message
        if ($message -like 'NOT_FOUND:*') { return New-ChannelForgeWebAcceptanceResponse 404 'proposal-not-found' 'The reviewed proposal is no longer available.' $Headers }
        if ($message -like 'STALE:*') { return New-ChannelForgeWebAcceptanceResponse 409 'stale-proposal' 'The accepted lineup changed after this review. Nothing was published; analyze the files again.' $Headers }
        if ($message -like 'FAIL_CLOSED:*') { return New-ChannelForgeWebAcceptanceResponse 422 'acceptance-unavailable' 'The reviewed proposal failed server verification. Nothing was published.' $Headers }
        return New-ChannelForgeWebAcceptanceResponse 422 'acceptance-unavailable' 'The reviewed proposal could not be accepted safely. Existing accepted state was preserved.' $Headers
    }
}
