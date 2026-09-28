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
        $paths = Get-ChannelForgeGenerationPaths -RepositoryRoot $RepositoryRoot
        # Read the validated immutable generation directly. The recovery wrapper
        # is intentionally not used because it may repair durable state.
        $snapshot = Get-ChannelForgeGenerationCurrentSnapshot -RepositoryRoot $RepositoryRoot -Paths $paths
        $programmes = @()
        if ($null -ne $snapshot -and $null -ne $snapshot.XMLTV) {
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
        $arguments = @{
            Query = $Query
            Programmes = $programmes
            EvaluationTimeUtc = [datetimeoffset]::UtcNow
            MaximumItems = $MaximumItems
            Offset = $Offset
        }
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
