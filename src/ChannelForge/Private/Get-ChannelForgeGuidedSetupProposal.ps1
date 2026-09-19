function Get-ChannelForgeWebProposalLimits {
    return [pscustomobject][ordered]@{
        MaxRequestBodyBytes = 24MB
        MaxM3UBytes = 4MB
        MaxXMLTVBytes = 12MB
        MaxJsonDepth = 8
    }
}

function New-ChannelForgeWebProposalErrorResponse {
    param(
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][string]$ErrorCode,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers
    )

    return New-ChannelForgeWebResponse -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8' -Body (@{
        Error = $ErrorCode
        Message = $Message
    } | ConvertTo-Json -Compress) -Headers $Headers
}

function ConvertFrom-ChannelForgeGuidedSetupProposalRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$BodyBytes
    )

    $limits = Get-ChannelForgeWebProposalLimits
    if ($BodyBytes.Length -gt $limits.MaxRequestBodyBytes) {
        throw [System.ArgumentException]::new('The proposal request is too large.')
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $json = $utf8.GetString($BodyBytes)
        $document = [System.Text.Json.JsonDocument]::Parse(
            $json,
            [System.Text.Json.JsonDocumentOptions]@{ MaxDepth = $limits.MaxJsonDepth; CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow; AllowTrailingCommas = $false }
        )
    }
    catch {
        throw [System.ArgumentException]::new('The proposal request is not valid JSON.')
    }

    try {
        $root = $document.RootElement
        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw [System.ArgumentException]::new('The proposal request must be a JSON object.') }
        $schemaValue = 0
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $schemaVersion = $null
        $m3uElement = $null
        $xmltvElement = $null
        foreach ($property in $root.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) { throw [System.ArgumentException]::new('The proposal request contains duplicate properties.') }
            switch ($property.Name) {
                'schemaVersion' { $schemaVersion = $property.Value }
                'm3u' { $m3uElement = $property.Value }
                'xmltv' { $xmltvElement = $property.Value }
                default { throw [System.ArgumentException]::new('The proposal request contains an unsupported property.') }
            }
        }
        if ($null -eq $schemaVersion -or $schemaVersion.ValueKind -ne [System.Text.Json.JsonValueKind]::Number -or -not $schemaVersion.TryGetInt32([ref]$schemaValue) -or $schemaValue -ne 1) {
            throw [System.ArgumentException]::new('The proposal request schema is not supported.')
        }
        if ($null -eq $m3uElement -or $m3uElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw [System.ArgumentException]::new('Exactly one M3U playlist is required.')
        }

        $readFile = {
            param([System.Text.Json.JsonElement]$element, [int]$maxBytes, [string]$label)
            $fileSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $content = $null
            foreach ($property in $element.EnumerateObject()) {
                if (-not $fileSeen.Add($property.Name)) { throw [System.ArgumentException]::new("The $label contains duplicate properties.") }
                if ($property.Name -cne 'contentBase64') { throw [System.ArgumentException]::new("The $label contains an unsupported property.") }
                if ($property.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) { throw [System.ArgumentException]::new("The $label content is invalid.") }
                $content = $property.Value.GetString()
            }
            if ($null -eq $content -or [string]::IsNullOrWhiteSpace($content)) { throw [System.ArgumentException]::new("The $label content is required.") }
            try { $decoded = [Convert]::FromBase64String($content) } catch { throw [System.ArgumentException]::new("The $label content is invalid.") }
            if ($decoded.Length -eq 0) { throw [System.ArgumentException]::new("The $label content is empty.") }
            if ($decoded.Length -gt $maxBytes) { throw [System.InvalidOperationException]::new("The $label content is too large.") }
            return [byte[]]$decoded
        }

        $m3u = & $readFile $m3uElement $limits.MaxM3UBytes 'M3U playlist'
        $xmltv = $null
        if ($null -ne $xmltvElement) {
            if ($xmltvElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw [System.ArgumentException]::new('The XMLTV guide is invalid.') }
            $xmltv = & $readFile $xmltvElement $limits.MaxXMLTVBytes 'XMLTV guide'
        }
        return [pscustomobject][ordered]@{ M3UBytes = $m3u; XMLTVBytes = $xmltv }
    }
    finally {
        $document.Dispose()
    }
}

function Get-ChannelForgeWebProposalStagingRoot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    return Join-Path ([System.IO.Path]::GetFullPath($RepositoryRoot)) 'output\.web-guided-setup'
}

function Get-ChannelForgeGuidedSetupProposalResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$BodyBytes,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [string]$ContentType = 'application/json'
    )

    $limits = Get-ChannelForgeWebProposalLimits
    if ([string]::IsNullOrWhiteSpace($ContentType) -or $ContentType.Split(';', 2)[0].Trim().ToLowerInvariant() -ne 'application/json') {
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 415 -ErrorCode 'unsupported-content-type' -Message 'The proposal request must use application/json.' -Headers $Headers
    }
    if ($BodyBytes.Length -gt $limits.MaxRequestBodyBytes) {
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 413 -ErrorCode 'request-too-large' -Message 'The proposal request is too large.' -Headers $Headers
    }

    $request = $null
    $requestRoot = $null
    $retainProposal = $false
    try {
        try { $request = ConvertFrom-ChannelForgeGuidedSetupProposalRequest -BodyBytes $BodyBytes }
        catch [System.InvalidOperationException] { return New-ChannelForgeWebProposalErrorResponse -StatusCode 413 -ErrorCode 'file-too-large' -Message 'The selected file is too large.' -Headers $Headers }
        catch { return New-ChannelForgeWebProposalErrorResponse -StatusCode 400 -ErrorCode 'invalid-proposal-request' -Message 'The proposal request is invalid.' -Headers $Headers }

        $storageRoot = Get-ChannelForgeWebProposalStorageRoot -RepositoryRoot $RepositoryRoot
        New-Item -ItemType Directory -Force -Path $storageRoot | Out-Null
        $proposalId = [guid]::NewGuid().ToString('N').ToLowerInvariant()
        $requestRoot = Join-Path $storageRoot $proposalId
        $candidateRoot = Join-Path $requestRoot 'candidate-output'
        New-Item -ItemType Directory -Force -Path $candidateRoot | Out-Null
        $m3uPath = Join-Path $requestRoot 'input.m3u'
        $xmltvPath = Join-Path $requestRoot 'guide.xml'
        [IO.File]::WriteAllBytes($m3uPath, [byte[]]$request.M3UBytes)
        if ($null -ne $request.XMLTVBytes) { [IO.File]::WriteAllBytes($xmltvPath, [byte[]]$request.XMLTVBytes) }
        $xmltvInputPath = if ($null -ne $request.XMLTVBytes) { $xmltvPath } else { $null }

        $candidate = New-ChannelForgeCandidateProposal -Root $RepositoryRoot -M3UPath $m3uPath -XMLTVPath $xmltvInputPath -OutputRoot $candidateRoot -CandidateContractVersion 'blocker-2-contract/v8'
        $manifest = $candidate.Manifest
        if (@($manifest.Entries).Count -eq 0) { throw [System.ArgumentException]::new('No channels were found in the playlist.') }
        $bindings = @($manifest.BindingRecords | Where-Object { [string]$_.BindingKind -eq 'M3U' })
        $exact = @($bindings | Where-Object { [string]$_.Status -eq 'ExactBound' }).Count
        $review = @($bindings | Where-Object { [string]$_.Status -eq 'ReviewNeeded' }).Count
        $unbound = @($bindings | Where-Object { [string]$_.Status -eq 'Unbound' }).Count
        $guideOnly = @($manifest.BindingRecords | Where-Object { [string]$_.BindingKind -eq 'XMLTVOnly' }).Count
        $guideStatus = if ($null -eq $request.XMLTVBytes) { 'NO_GUIDE_SELECTED' } else { 'XMLTV_SELECTED' }
        $warnings = [System.Collections.Generic.List[object]]::new()
        if ($review -gt 0) { [void]$warnings.Add([pscustomobject][ordered]@{ Code = 'ambiguous-guide-match'; Message = 'Some guide identities need review before a guide can be trusted.' }) }
        if ($unbound -gt 0) { [void]$warnings.Add([pscustomobject][ordered]@{ Code = 'unmatched-playlist-entry'; Message = 'Some playlist entries have no exact guide match.' }) }
        if ($guideOnly -gt 0) { [void]$warnings.Add([pscustomobject][ordered]@{ Code = 'guide-only-record'; Message = 'The guide contains records not present in the playlist.' }) }
        $current = Get-ChannelForgeWebCurrentAcceptedSnapshot -RepositoryRoot $RepositoryRoot
        $parentManifestHash = if ($null -eq $current) { $null } else { [string]$current.Manifest.Object.GenerationManifestHash }
        $parentStateHash = if ($null -eq $current) { $null } else { [string]$current.State.Object.AcceptedStateHash }
        $parentOutputHash = if ($null -eq $current) { $null } else { [string]$current.Output.Object.OutputManifestHash }
        $blockingReasons = @()
        if ($review -gt 0) { $blockingReasons += 'ambiguous-guide-match' }
        $canAccept = @($manifest.Entries).Count -gt 0 -and $blockingReasons.Count -eq 0
        $session = [pscustomobject][ordered]@{
            Version = 'guided-setup/review/v1'
            ProposalId = $proposalId
            Status = 'Ready'
            CreatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            CandidateManifestHash = [string]$candidate.CandidateManifestHash
            BuildIdentity = [string]$candidate.BuildIdentity
            CandidateDirectoryRelative = "candidate-output/candidates/$($candidate.CandidateManifestHash)"
            ParentGenerationManifestHash = $parentManifestHash
            ParentAcceptedStateHash = $parentStateHash
            ParentOutputManifestHash = $parentOutputHash
            ChannelCount = @($manifest.Entries).Count
            ExactGuideMatchCount = $exact
            AmbiguityCount = $review
            UnmatchedPlaylistCount = $unbound
            GuideOnlyCount = $guideOnly
            GuideStatus = $guideStatus
            CanAccept = $canAccept
            BlockingReasons = @($blockingReasons)
        }
        Remove-Item -LiteralPath $m3uPath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $xmltvPath -PathType Leaf) { Remove-Item -LiteralPath $xmltvPath -Force -ErrorAction SilentlyContinue }
        $null = Write-ChannelForgeWebProposalSession -RepositoryRoot $RepositoryRoot -Session $session
        $retainProposal = $true
        $projection = [ordered]@{
            Version = 'guided-setup/proposal/v1'
            Status = 'PROPOSAL_READY'
            Proposal = [ordered]@{
                ProposalId = $proposalId
                ChannelCount = [int]$session.ChannelCount
                ExactGuideMatchCount = $exact
                AmbiguityCount = $review
                UnmatchedPlaylistCount = $unbound
                GuideOnlyCount = $guideOnly
                GuideStatus = $guideStatus
                CanAccept = $canAccept
                BlockingReasons = @($blockingReasons)
            }
            Warnings = @($warnings | Sort-Object Code)
            Safety = [ordered]@{
                PublicationState = 'CandidateOnly'
                AcceptedStateMutation = 'none'
                ProviderMutation = 'none'
                DownstreamMutation = 'none'
                GuidePublication = 'none'
                CanPublish = $false
                CanAccept = $canAccept
            }
        }
        $body = $projection | ConvertTo-Json -Depth 8 -Compress
        return New-ChannelForgeWebResponse -StatusCode 200 -ContentType 'application/json; charset=utf-8' -Body $body -Headers $Headers
    }
    catch {
        return New-ChannelForgeWebProposalErrorResponse -StatusCode 422 -ErrorCode 'proposal-unavailable' -Message 'The playlist or guide could not be analyzed safely.' -Headers $Headers
    }
    finally {
        if (-not $retainProposal -and $null -ne $requestRoot -and (Test-Path -LiteralPath $requestRoot)) {
            Remove-Item -LiteralPath $requestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
