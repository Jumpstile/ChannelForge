function Get-ChannelForgeRemoteXmltvCacheKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$CacheRoot,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes
    )

    $policy = Get-ChannelForgeRemoteXmltvCachePolicy -MaxDocumentBytes $MaxDocumentBytes
    if (-not (Test-ChannelForgeSourceUrl -Url $Url)) {
        throw 'The remote XMLTV endpoint is not an accepted HTTPS source.'
    }

    if ([string]::IsNullOrWhiteSpace($SourceId) -or
        $SourceId.Length -gt 128 -or
        $SourceId -match '[\r\n\t/\\?@#]' -or
        $SourceId -match '://') {
        throw 'SourceId contains unsupported metadata characters.'
    }

    try {
        $uri = [System.Uri]$Url
    }
    catch {
        throw 'The remote XMLTV endpoint is not an accepted HTTPS source.'
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
        $SourceId.Trim()
        $canonicalEndpoint
        'xmltv'
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
    $payloadPath = Join-Path $entryRoot 'payload.xml'

    return [pscustomobject][ordered]@{
        Key          = $key
        VersionRoot  = $versionRoot
        EntryRoot    = $entryRoot
        MetadataPath = $metadataPath
        PayloadPath  = $payloadPath
        Policy       = $policy
    }
}
