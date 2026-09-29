$script:ChannelForgeOneGuideAcceptedProjectionCache = $null

function Get-ChannelForgeWebOneGuideCatalogue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $RepositoryRoot
    if (-not [IO.File]::Exists($paths.Current)) {
        $script:ChannelForgeOneGuideAcceptedProjectionCache = $null
        return @()
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
        return @($script:ChannelForgeOneGuideAcceptedProjectionCache.Items)
    }

    $snapshot = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $RepositoryRoot -Paths $paths
    if ($null -eq $snapshot) {
        $script:ChannelForgeOneGuideAcceptedProjectionCache = $null
        return @()
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

    $programmes = @()
    if ($null -ne $snapshot.XMLTV) {
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
    }
    $minimumEvaluationTimeUtc = [datetimeoffset]::MinValue
    $catalogue = @(Get-ChannelForgeOneGuide -Query LiveNow -Programmes $programmes -EvaluationTimeUtc $minimumEvaluationTimeUtc -ReturnCatalogue)
    $itemsById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $catalogue) { $itemsById[[string]$item.ItemId] = $item }
    $script:ChannelForgeOneGuideAcceptedProjectionCache = [pscustomobject]@{
        Key = $cacheKey
        Items = $catalogue
        ItemsById = $itemsById
    }
    return $catalogue
}

function Get-ChannelForgeWebOneGuidePaging {
    param([AllowEmptyString()][string]$QueryString = '')

    if ($QueryString.Length -gt 128) { throw 'One Guide query is too long.' }
    $maximumItems = 100
    $offset = 0
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrEmpty($QueryString)) {
        foreach ($part in $QueryString.Split('&')) {
            $pair = $part.Split('=', 2)
            if ($pair.Length -ne 2 -or [string]::IsNullOrWhiteSpace($pair[0]) -or -not $seen.Add($pair[0])) {
                throw 'One Guide query parameters are invalid.'
            }
            $value = 0
            if (-not [int]::TryParse($pair[1], [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
                throw 'One Guide query values must be decimal integers.'
            }
            switch ($pair[0].ToLowerInvariant()) {
                'limit' {
                    if ($value -lt 1 -or $value -gt 100) { throw 'One Guide limit is outside the supported range.' }
                    $maximumItems = $value
                }
                'offset' { $offset = $value }
                default { throw 'One Guide query parameters are unsupported.' }
            }
        }
    }
    return [pscustomobject][ordered]@{ MaximumItems = $maximumItems; Offset = $offset }
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
        [ValidateRange(0, 2147483647)][int]$Offset = 0
    )

    try {
        if ($Query -eq 'Details' -and $Offset -ne 0) {
            return New-ChannelForgeWebResponse -StatusCode 400 -ContentType $ContentType -Body (@{ Error = 'invalid-query'; Message = 'Item detail does not support an offset.' } | ConvertTo-Json -Compress) -Headers $Headers
        }
        $catalogue = Get-ChannelForgeWebOneGuideCatalogue -RepositoryRoot $RepositoryRoot
        $arguments = @{
            Query = $Query
            Programmes = @()
            Catalogue = $catalogue
            UseCatalogue = $true
            EvaluationTimeUtc = [datetimeoffset]::UtcNow
            MaximumItems = $MaximumItems
            Offset = $Offset
        }
        if ($Query -eq 'Details') { $arguments.CatalogueById = $script:ChannelForgeOneGuideAcceptedProjectionCache.ItemsById }
        if (-not [string]::IsNullOrWhiteSpace($CategoryKey)) { $arguments.CategoryKey = $CategoryKey }
        if (-not [string]::IsNullOrWhiteSpace($ItemId)) { $arguments.ItemId = $ItemId }
        $projection = Get-ChannelForgeOneGuide @arguments
        if ($Query -eq 'Details' -and $projection.TotalCount -eq 0) {
            return New-ChannelForgeWebResponse -StatusCode 404 -ContentType $ContentType -Body (@{ Error = 'not-found'; Message = 'Guide item not found.' } | ConvertTo-Json -Compress) -Headers $Headers
        }
        $body = ConvertTo-Json -InputObject $projection -Depth 10 -Compress
        return New-ChannelForgeWebResponse -StatusCode 200 -ContentType $ContentType -Body $body -Headers $Headers
    }
    catch {
        return New-ChannelForgeWebResponse -StatusCode 503 -ContentType $ContentType -Body (@{
            Error = 'one-guide-unavailable'
            Message = 'The accepted guide is temporarily unavailable.'
        } | ConvertTo-Json -Compress) -Headers $Headers
    }
}
