$script:ChannelForgeOneGuideAcceptedProjectionCache = $null

function Get-ChannelForgeWebOneGuideCatalogue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $RepositoryRoot
    if (-not [IO.File]::Exists($paths.Current)) {
        $script:ChannelForgeOneGuideAcceptedProjectionCache = $null
        throw 'Accepted guide is unavailable because no accepted generation exists.'
    }
    $pointer = Read-ChannelForgeGenerationDocument -RepositoryRoot $RepositoryRoot -Path $paths.Current -Domain 'pointer/v2'
    Assert-ChannelForgeGenerationPropertySequence $pointer.Object @('Version', 'GenerationId', 'GenerationManifestHash', 'AcceptedStateHash', 'AcceptedOutputManifestHash', 'PointerHash') 'Pointer'
    Assert-ChannelForgeGenerationHash $pointer.Object.PointerHash 'PointerHash'
    Assert-ChannelForgeGenerationId ([string]$pointer.Object.GenerationId)
    if (-not (Test-ChannelForgeGenerationProjectionHash $pointer.Object 'pointer/v2' 'PointerHash')) { throw 'FAIL_CLOSED: current pointer hash is invalid.' }
    $repositoryRootKey = [IO.Path]::GetFullPath($RepositoryRoot)
    $cacheKey = @(
        $repositoryRootKey,
        [string]$pointer.Object.GenerationId,
        [string]$pointer.Object.GenerationManifestHash,
        [string]$pointer.Object.AcceptedStateHash,
        [string]$pointer.Object.AcceptedOutputManifestHash,
        [string]$pointer.Object.PointerHash
    ) -join '|'
    if ($null -ne $script:ChannelForgeOneGuideAcceptedProjectionCache -and
        [string]$script:ChannelForgeOneGuideAcceptedProjectionCache.Key -ceq $cacheKey) {
        return $script:ChannelForgeOneGuideAcceptedProjectionCache
    }

    $snapshot = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $RepositoryRoot -Paths $paths
    if ($null -eq $snapshot) {
        $script:ChannelForgeOneGuideAcceptedProjectionCache = $null
        throw 'Accepted guide is unavailable because the accepted generation could not be loaded.'
    }
    $snapshotPointer = $snapshot.Pointer.Object
    $snapshotKey = @(
        $repositoryRootKey,
        [string]$snapshotPointer.GenerationId,
        [string]$snapshotPointer.GenerationManifestHash,
        [string]$snapshotPointer.AcceptedStateHash,
        [string]$snapshotPointer.AcceptedOutputManifestHash,
        [string]$snapshotPointer.PointerHash
    ) -join '|'
    if ($snapshotKey -cne $cacheKey) { throw 'Accepted generation changed while the One Guide projection was loading.' }

    if ($null -eq $snapshot.XMLTV) {
        throw 'Accepted guide is unavailable because accepted XMLTV was not generated.'
    }
    $programmes = @()
    $bytes = [byte[]]$snapshot.XMLTV.Bytes
    if ($bytes.Length -gt 268435456) { throw 'Accepted guide exceeds the read projection limit.' }
    $stream = [System.IO.MemoryStream]::new($bytes, $false)
    try {
        $programmes = @(Read-ChannelForgeXmltvDocument `
            -Stream $stream `
            -SourceId 'accepted-guide' `
            -SourcePath $snapshot.XMLTV.Path `
            -SourceKind local `
            -MaxDocumentBytes 268435456 `
            -CandidateContractVersion 'blocker-2-contract/v8')
    }
    finally { $stream.Dispose() }
    $minimumEvaluationTimeUtc = [datetimeoffset]::MinValue
    $catalogue = @(Get-ChannelForgeOneGuide -Query LiveNow -Programmes $programmes -EvaluationTimeUtc $minimumEvaluationTimeUtc -ReturnCatalogue)
    $itemsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $catalogue) { $itemsById[[string]$item.ItemId] = $item }
    $projectionCache = [pscustomobject]@{
        Key = $cacheKey
        # Opaque snapshot token for paging pins; derived so the accepted pointer hash itself is never exposed.
        GenerationToken = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes("one-guide-page-snapshot/v1|$cacheKey"))).ToLowerInvariant()
        Items = $catalogue
        ItemsById = $itemsById
    }
    $script:ChannelForgeOneGuideAcceptedProjectionCache = $projectionCache
    return $projectionCache
}

function Get-ChannelForgeWebOneGuidePaging {
    param([AllowEmptyString()][string]$QueryString = '')

    if ($QueryString.Length -gt 160) { throw 'One Guide query is too long.' }
    $maximumItems = 100
    $offset = 0
    $evaluationTimeUtc = $null
    $generation = $null
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrEmpty($QueryString)) {
        foreach ($part in $QueryString.Split('&')) {
            $pair = $part.Split('=', 2)
            if ($pair.Length -ne 2 -or [string]::IsNullOrWhiteSpace($pair[0]) -or -not $seen.Add($pair[0])) {
                throw 'One Guide query parameters are invalid.'
            }
            $name = $pair[0].ToLowerInvariant()
            if ($name -ceq 'generation') {
                if ($pair[1] -cnotmatch '^[a-f0-9]{64}$') { throw 'One Guide generation is invalid.' }
                $generation = $pair[1]
                continue
            }
            $value = [long]0
            if (-not [long]::TryParse($pair[1], [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
                throw 'One Guide query values must be decimal integers.'
            }
            switch ($name) {
                'limit' {
                    if ($value -lt 1 -or $value -gt 100) { throw 'One Guide limit is outside the supported range.' }
                    $maximumItems = [int]$value
                }
                'offset' {
                    if ($value -gt [int]::MaxValue) { throw 'One Guide offset is outside the supported range.' }
                    $offset = [int]$value
                }
                'at' {
                    if ($value -gt 253402300799999) { throw 'One Guide evaluation time is outside the supported range.' }
                    $evaluationTimeUtc = [datetimeoffset]::FromUnixTimeMilliseconds($value)
                }
                default { throw 'One Guide query parameters are unsupported.' }
            }
        }
    }
    if ($offset -gt 0 -and ($null -eq $evaluationTimeUtc -or $null -eq $generation)) {
        throw 'One Guide pages after the first require the at and generation snapshot cursor.'
    }
    return [pscustomobject][ordered]@{ MaximumItems = $maximumItems; Offset = $offset; EvaluationTimeUtc = $evaluationTimeUtc; Generation = $generation }
}

function Get-ChannelForgeWebOneGuideResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [Parameter(Mandatory)][string]$ContentType,
        [Parameter(Mandatory)][ValidateSet('LiveNow', 'StartingSoon', 'Category', 'Details')][string]$Query,
        [AllowNull()][string]$CategoryKey,
        [AllowNull()][string]$ItemId,
        [ValidateRange(1, 100)][int]$MaximumItems = 100,
        [ValidateRange(0, 2147483647)][int]$Offset = 0,
        [AllowNull()][Nullable[datetimeoffset]]$EvaluationTimeUtc,
        [AllowNull()][string]$Generation
    )

    try {
        if ($Query -eq 'Details' -and $Offset -ne 0) {
            return New-ChannelForgeWebResponse -StatusCode 400 -ContentType $ContentType -Body (@{ Error = 'invalid-query'; Message = 'Item detail does not support an offset.' } | ConvertTo-Json -Compress) -Headers $Headers
        }
        $projectionCache = Get-ChannelForgeWebOneGuideCatalogue -RepositoryRoot $RepositoryRoot
        if (-not [string]::IsNullOrEmpty($Generation) -and $Generation -cne $projectionCache.GenerationToken) {
            return New-ChannelForgeWebResponse -StatusCode 409 -ContentType $ContentType -Body (@{ Error = 'generation-changed'; Message = 'The accepted guide changed; reload from the first page.' } | ConvertTo-Json -Compress) -Headers $Headers
        }
        # One evaluation instant at millisecond precision so clients can echo it exactly via ?at= on later pages.
        $evaluation = if ($null -ne $EvaluationTimeUtc) { [datetimeoffset]$EvaluationTimeUtc } else { [datetimeoffset]::FromUnixTimeMilliseconds([datetimeoffset]::UtcNow.ToUnixTimeMilliseconds()) }
        $arguments = @{
            Query = $Query
            Programmes = @()
            Catalogue = @($projectionCache.Items)
            UseCatalogue = $true
            EvaluationTimeUtc = $evaluation
            MaximumItems = $MaximumItems
            Offset = $Offset
        }
        if ($Query -eq 'Details') { $arguments.CatalogueById = $projectionCache.ItemsById }
        if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) { $arguments.CategoryKey = $CategoryKey }
        if (-not [string]::IsNullOrWhiteSpace($ItemId)) { $arguments.ItemId = $ItemId }
        $projection = Get-ChannelForgeOneGuide @arguments
        if ($Query -eq 'Details' -and $projection.TotalCount -eq 0) {
            return New-ChannelForgeWebResponse -StatusCode 404 -ContentType $ContentType -Body (@{ Error = 'not-found'; Message = 'Guide item not found.' } | ConvertTo-Json -Compress) -Headers $Headers
        }
        $body = ConvertTo-Json -InputObject $projection -Depth 10 -Compress
        $responseHeaders = [ordered]@{}
        foreach ($key in $Headers.Keys) { $responseHeaders[$key] = $Headers[$key] }
        $responseHeaders['X-ChannelForge-Generation'] = [string]$projectionCache.GenerationToken
        return New-ChannelForgeWebResponse -StatusCode 200 -ContentType $ContentType -Body $body -Headers $responseHeaders
    }
    catch {
        return New-ChannelForgeWebResponse -StatusCode 503 -ContentType $ContentType -Body (@{
            Error = 'one-guide-unavailable'
            Message = 'The accepted guide is temporarily unavailable.'
        } | ConvertTo-Json -Compress) -Headers $Headers
    }
}
