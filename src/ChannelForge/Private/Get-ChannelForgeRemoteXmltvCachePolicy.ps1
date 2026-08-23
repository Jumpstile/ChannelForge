function Get-ChannelForgeRemoteXmltvCachePolicy {
    [CmdletBinding()]
    param(
        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes
    )

    if ($MaxDocumentBytes -le 0 -or
        $MaxDocumentBytes -gt [BoundedDecompressionStream]::HardMaximumDecompressedBytes) {
        throw 'MaxDocumentBytes must be greater than zero and no greater than the transport hard maximum.'
    }

    return [pscustomobject][ordered]@{
        CacheFormatVersion   = 1
        KeyVersion           = 1
        KeyAlgorithm         = 'sha256'
        CacheVersion         = 'remote-xmltv-cache-v1'
        ParserCacheVersion   = 'xmltv-parser-cache-v1'
        Format               = 'xmltv'
        TransportContract    = 5
        TtlSeconds           = 21600
        MaxDecompressedBytes = $MaxDocumentBytes
        RelativeVersionRoot  = 'v1'
    }
}
