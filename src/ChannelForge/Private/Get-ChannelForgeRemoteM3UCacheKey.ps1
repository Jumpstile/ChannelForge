function Test-ChannelForgeRemoteM3UCacheIdentity {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or
        $Value.Length -gt 128 -or
        $Value -match '[\r\n\t/\\?@#]' -or
        $Value -match '://') {
        throw "$Name contains unsupported metadata characters."
    }
}

function Get-ChannelForgeRemoteM3UCacheKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProviderId,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$CacheRoot,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes
    )

    $policy = Get-ChannelForgeRemoteM3UCachePolicy -MaxDocumentBytes $MaxDocumentBytes
    Test-ChannelForgeRemoteM3UCacheIdentity -Value $ProviderId -Name 'ProviderId'
    Test-ChannelForgeRemoteM3UCacheIdentity -Value $SourceId -Name 'SourceId'

    if (-not (Test-ChannelForgeSourceUrl -Url $Url)) {
        throw 'The remote M3U endpoint is not an accepted HTTPS source.'
    }

    try {
        $uri = [System.Uri]$Url
    }
    catch {
        throw 'The remote M3U endpoint is not an accepted HTTPS source.'
    }

    $canonicalEndpoint = @(
        'https'
        $uri.Host.ToLowerInvariant()
        '443'
        $uri.AbsolutePath
        $uri.Query
    ) -join '|'
    $material = @(
        'cache-key-v1'
        $ProviderId.Trim()
        $SourceId.Trim()
        $canonicalEndpoint
        'm3u'
        'transport-v5'
        $policy.ParserCacheVersion
        [string]$policy.MaxDecompressedBytes
    ) -join '|'

    $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($material)
        $key = [Convert]::ToHexString($hashAlgorithm.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally {
        $hashAlgorithm.Dispose()
    }

    $versionRoot = Join-Path $CacheRoot $policy.RelativeVersionRoot
    $entryRoot = Join-Path $versionRoot $key
    $metadataPath = Join-Path $entryRoot 'metadata.json'
    $payloadPath = Join-Path $entryRoot 'payload.m3u'

    return [pscustomobject][ordered]@{
        Key          = $key
        VersionRoot  = $versionRoot
        EntryRoot    = $entryRoot
        MetadataPath = $metadataPath
        PayloadPath  = $payloadPath
        Policy       = $policy
    }
}
