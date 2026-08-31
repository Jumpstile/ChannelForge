function Read-ChannelForgeRemoteXmltvFetchCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CacheRoot,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$Url,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes,

        [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]::UtcNow)
    )

    $keyInfo = Get-ChannelForgeRemoteXmltvCacheKey `
        -SourceId $SourceId `
        -Url $Url `
        -CacheRoot $CacheRoot `
        -MaxDocumentBytes $MaxDocumentBytes

    $result = [ordered]@{
        Available        = $true
        Key              = $keyInfo.Key
        EntryRoot        = $keyInfo.EntryRoot
        MetadataPath     = $keyInfo.MetadataPath
        PayloadPath      = $null
        Metadata         = $null
        MetadataValid    = $false
        PayloadValid     = $false
        IsFresh          = $false
        CanConditional   = $false
        AgeSeconds       = $null
        InvalidReason    = 'MissingMetadata'
    }

    if (-not (Test-Path -LiteralPath $keyInfo.MetadataPath -PathType Leaf)) {
        return [pscustomobject]$result
    }

    $metadata = $null
    try {
        $metadata = Get-Content -LiteralPath $keyInfo.MetadataPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $result.InvalidReason = 'MalformedMetadata'
        return [pscustomobject]$result
    }

    $result.Metadata = $metadata
    $requiredMetadataFields = @('CacheFormatVersion','CacheVersion','KeyAlgorithm','KeyVersion','CacheKey','SourceId','Format','TransportContractVersion','ParserCacheVersion','MaxDecompressedBytes','ContentType','ContentEncodings','PayloadFile','PayloadByteCount','PayloadSha256','RawContentLength','ProgrammeCount','ChannelCount','FetchedAtUtc','ValidatedAtUtc','TtlSeconds','ETag','LastModified','SourceHttpStatusCode','LastValidationStatus','OperationalReason')
    foreach ($field in $requiredMetadataFields) {
        if ($null -eq $metadata.PSObject.Properties[$field]) {
            $result.InvalidReason = 'MetadataContractMismatch'
            return [pscustomobject]$result
        }
    }
    $unexpectedMetadataFields = @($metadata.PSObject.Properties.Name | Where-Object { $_ -notin $requiredMetadataFields })
    if ($unexpectedMetadataFields.Count -gt 0) {
        $result.InvalidReason = 'MetadataContractMismatch'
        return [pscustomobject]$result
    }

    $requiredMatches = @(
        @('CacheFormatVersion', 1),
        @('CacheVersion', 'remote-xmltv-cache-v1'),
        @('KeyVersion', 1),
        @('KeyAlgorithm', 'sha256'),
        @('ParserCacheVersion', 'xmltv-parser-cache-v1'),
        @('Format', 'xmltv'),
        @('TransportContractVersion', 5),
        @('TtlSeconds', 21600),
        @('MaxDecompressedBytes', [int64]$MaxDocumentBytes),
        @('CacheKey', $keyInfo.Key),
        @('SourceId', $SourceId.Trim()),
        @('SourceHttpStatusCode', 200)
    )

    foreach ($match in $requiredMatches) {
        $property = $metadata.PSObject.Properties[$match[0]]
        if ($null -eq $property -or [string]$property.Value -cne [string]$match[1]) {
            $result.InvalidReason = 'MetadataContractMismatch'
            return [pscustomobject]$result
        }
    }

    if ([string]$metadata.ContentType -notin @('application/xml', 'text/xml')) {
        $result.InvalidReason = 'MetadataContentTypeMismatch'
        return [pscustomobject]$result
    }

    $encodings = @($metadata.ContentEncodings | ForEach-Object {
        if ($null -eq $_) { '' } else { ([string]$_).Trim().ToLowerInvariant() }
    })
    foreach ($encoding in $encodings) {
        if ($encoding -ne '' -and $encoding -ne 'identity' -and
            $encoding -ne 'gzip' -and $encoding -ne 'x-gzip') {
            $result.InvalidReason = 'MetadataEncodingMismatch'
            return [pscustomobject]$result
        }
    }

    $payloadFile = [string]$metadata.PayloadFile
    if ($payloadFile -notmatch '^payload-[0-9a-f]{64}\.xml$') {
        $result.InvalidReason = 'UnsafePayloadReference'
        return [pscustomobject]$result
    }

    try {
        $entryFull = [System.IO.Path]::GetFullPath($keyInfo.EntryRoot)
        $payloadPath = [System.IO.Path]::GetFullPath((Join-Path $keyInfo.EntryRoot $payloadFile))
        $entryPrefix = $entryFull.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar) +
            [System.IO.Path]::DirectorySeparatorChar
        if (-not $payloadPath.StartsWith($entryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.InvalidReason = 'UnsafePayloadReference'
            return [pscustomobject]$result
        }
    }
    catch {
        $result.InvalidReason = 'UnsafePayloadReference'
        return [pscustomobject]$result
    }

    $result.PayloadPath = $payloadPath

    $fetchedAt = [datetimeoffset]::MinValue
    $validatedAt = [datetimeoffset]::MinValue
    $dateStyles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if (-not [datetimeoffset]::TryParse(
            [string]$metadata.FetchedAtUtc,
            [System.Globalization.CultureInfo]::InvariantCulture,
            $dateStyles,
            [ref]$fetchedAt) -or
        -not [datetimeoffset]::TryParse(
            [string]$metadata.ValidatedAtUtc,
            [System.Globalization.CultureInfo]::InvariantCulture,
            $dateStyles,
            [ref]$validatedAt)) {
        $result.InvalidReason = 'InvalidCacheTimestamp'
        return [pscustomobject]$result
    }

    $now = $EvaluationTimeUtc
    if ($fetchedAt -gt $now -or $validatedAt -gt $now -or
        $validatedAt -lt $fetchedAt) {
        $result.InvalidReason = 'InvalidCacheTimestamp'
        return [pscustomobject]$result
    }

    $lastStatus = 0
    if (-not [int]::TryParse([string]$metadata.LastValidationStatus, [ref]$lastStatus) -or
        $lastStatus -notin @(200, 304)) {
        $result.InvalidReason = 'InvalidValidationStatus'
        return [pscustomobject]$result
    }

    $payloadByteCount = 0L
    if (-not [long]::TryParse([string]$metadata.PayloadByteCount, [ref]$payloadByteCount) -or
        $payloadByteCount -lt 0) {
        $result.InvalidReason = 'InvalidPayloadLength'
        return [pscustomobject]$result
    }

    $payloadHash = [string]$metadata.PayloadSha256
    if ($payloadHash -notmatch '^[0-9a-f]{64}$') {
        $result.InvalidReason = 'InvalidPayloadHash'
        return [pscustomobject]$result
    }

    $etag = [string]$metadata.ETag
    if (-not [string]::IsNullOrWhiteSpace($etag)) {
        if ($etag.Trim().Length -gt 1024) {
            # Keep malformed cached validators out of the conditional request
            # path; the next acquisition must fall back to an unconditional
            # bounded fetch instead of failing on a corrupt cache entry.
            $result.InvalidReason = 'InvalidValidator'
            return [pscustomobject]$result
        }

        foreach ($character in $etag.Trim().ToCharArray()) {
            if ([char]::IsControl($character)) {
                $result.InvalidReason = 'InvalidValidator'
                return [pscustomobject]$result
            }
        }

        $parsedETag = $null
        if (-not [System.Net.Http.Headers.EntityTagHeaderValue]::TryParse(
                $etag.Trim(),
                [ref]$parsedETag)) {
            $result.InvalidReason = 'InvalidValidator'
            return [pscustomobject]$result
        }
    }

    if ($null -ne $metadata.LastModified -and
        -not [string]::IsNullOrWhiteSpace([string]$metadata.LastModified)) {
        $lastModified = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse(
                [string]$metadata.LastModified,
                [System.Globalization.CultureInfo]::InvariantCulture,
                $dateStyles,
                [ref]$lastModified)) {
            $result.InvalidReason = 'InvalidValidator'
            return [pscustomobject]$result
        }
    }

    $result.MetadataValid = $true
    $result.CanConditional = -not [string]::IsNullOrWhiteSpace($etag) -or
        ($null -ne $metadata.LastModified -and
        -not [string]::IsNullOrWhiteSpace([string]$metadata.LastModified))
    $result.AgeSeconds = ($now - $validatedAt).TotalSeconds
    $result.InvalidReason = $null

    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
        $result.InvalidReason = 'MissingPayload'
        return [pscustomobject]$result
    }

    try {
        $payloadInfo = Get-Item -LiteralPath $payloadPath -Force -ErrorAction Stop
        if ($payloadInfo.PSIsContainer -or $payloadInfo.Length -ne $payloadByteCount) {
            $result.InvalidReason = 'PayloadLengthMismatch'
            return [pscustomobject]$result
        }

        $hash = [System.Security.Cryptography.SHA256]::Create()
        try {
            $stream = [System.IO.FileStream]::new(
                $payloadPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read,
                81920,
                [System.IO.FileOptions]::SequentialScan)
            try {
                $buffer = [byte[]]::new(81920)
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    [void]$hash.TransformBlock($buffer, 0, $read, $buffer, 0)
                }
                [void]$hash.TransformFinalBlock([byte[]]::new(0), 0, 0)
                $actualHash = [Convert]::ToHexString($hash.Hash).ToLowerInvariant()
            }
            finally {
                $stream.Dispose()
            }
        }
        finally {
            $hash.Dispose()
        }

        if ($actualHash -cne $payloadHash) {
            $result.InvalidReason = 'PayloadHashMismatch'
            return [pscustomobject]$result
        }
    }
    catch {
        $result.InvalidReason = 'PayloadReadFailure'
        return [pscustomobject]$result
    }

    $result.PayloadValid = $true
    $result.IsFresh = $result.AgeSeconds -lt [double]$keyInfo.Policy.TtlSeconds
    return [pscustomobject]$result
}
