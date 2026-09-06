function Get-ChannelForgeRemoteXmltvException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $current = $Exception
    while (($current -is [System.Reflection.TargetInvocationException] -or
            $current -is [System.Management.Automation.MethodInvocationException]) -and
        $null -ne $current.InnerException) {
        $current = $current.InnerException
    }

    return $current
}

function New-ChannelForgeRemoteXmltvAcquisitionFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception,

        [string]$FallbackCategory = 'AcquisitionFailure'
    )

    $inner = Get-ChannelForgeRemoteXmltvException -Exception $Exception
    $category = if ($null -ne $inner.PSObject.Properties['Category'] -and
        -not [string]::IsNullOrWhiteSpace([string]$inner.Category)) {
        [string]$inner.Category
    }
    elseif ($null -ne $inner.Data['ChannelForgeFailureCategory'] -and
        -not [string]::IsNullOrWhiteSpace([string]$inner.Data['ChannelForgeFailureCategory'])) {
        [string]$inner.Data['ChannelForgeFailureCategory']
    }
    elseif ($inner -is [System.ArgumentException]) {
        'InvalidEndpoint'
    }
    else {
        $FallbackCategory
    }

    $phase = if ($null -ne $inner.PSObject.Properties['Phase'] -and
        -not [string]::IsNullOrWhiteSpace([string]$inner.Phase)) {
        [string]$inner.Phase
    }
    elseif ($null -ne $inner.Data['ChannelForgeFailurePhase'] -and
        -not [string]::IsNullOrWhiteSpace([string]$inner.Data['ChannelForgeFailurePhase'])) {
        [string]$inner.Data['ChannelForgeFailurePhase']
    }
    else {
        'Acquisition'
    }

    $statusCode = if ($null -ne $inner.PSObject.Properties['StatusCode']) {
        $inner.StatusCode
    }
    else {
        $null
    }

    $failure = [System.InvalidOperationException]::new(
        "Remote XMLTV acquisition failed [$category].")
    $failure.Data['ChannelForgeFailureCategory'] = $category
    $failure.Data['ChannelForgeFailurePhase'] = $phase
    if ($null -ne $statusCode) {
        $failure.Data['ChannelForgeFailureStatusCode'] = [int]$statusCode
    }

    return $failure
}

function Invoke-ChannelForgePinnedHttpXmltvAcquisition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$Url,

        [long]$MaxRawResponseBytes = 268435456,

        [AllowEmptyString()]
        [string]$IfNoneMatch = '',

        [Nullable[datetimeoffset]]$IfModifiedSince,

        [switch]$Allow304MetadataOnly
    )

    return Invoke-ChannelForgePinnedHttpAcquisition `
        -SourceId $SourceId `
        -Url $Url `
        -AllowedContentTypes @('application/xml', 'text/xml') `
        -MaxRawResponseBytes $MaxRawResponseBytes `
        -IfNoneMatch $IfNoneMatch `
        -IfModifiedSince $IfModifiedSince `
        -Allow304MetadataOnly:$Allow304MetadataOnly
}

function Open-ChannelForgeRemoteXmltvSourceStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Source,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes,

        [long]$MaxRawResponseBytes = 268435456
    )

    if ($null -eq $Source) {
        throw 'Remote XMLTV source cannot be empty.'
    }

    $propertyNames = @($Source.PSObject.Properties.Name)
    $sourceId = if ($propertyNames -contains 'Name') { [string]$Source.Name } else { '' }
    $url = if ($propertyNames -contains 'Url') { [string]$Source.Url } else { '' }

    if ([string]::IsNullOrWhiteSpace($sourceId)) {
        throw 'Remote XMLTV source requires a non-empty source name.'
    }

    if ([string]::IsNullOrWhiteSpace($url)) {
        throw 'Remote XMLTV source requires a URL.'
    }

    if ($MaxDocumentBytes -le 0 -or
        $MaxDocumentBytes -gt [BoundedDecompressionStream]::HardMaximumDecompressedBytes) {
        throw 'MaxDocumentBytes must be greater than zero and no greater than the transport hard maximum.'
    }

    $payload = $null
    $expanded = $null
    try {
        $payload = Invoke-ChannelForgePinnedHttpXmltvAcquisition `
            -SourceId $sourceId `
            -Url $url `
            -MaxRawResponseBytes $MaxRawResponseBytes

        $contentEncodings = [System.Collections.Generic.List[string]]::new()
        foreach ($encoding in $payload.ContentEncodings) {
            if ($null -ne $encoding) {
                [void]$contentEncodings.Add(([string]$encoding).Trim())
            }
        }
        $contentEncodingArray = $contentEncodings.ToArray()

        $expanded = Expand-ChannelForgePinnedHttpContentStream `
            -ContentEncodings $contentEncodingArray `
            -InnerStream $payload.ResponseStream `
            -Owner $payload `
            -MaxDecompressedBytes $MaxDocumentBytes

        $compression = if (@($contentEncodingArray | Where-Object {
                    $_ -and $_.Trim().ToLowerInvariant() -in @('gzip', 'x-gzip')
                }).Count -gt 0) {
            'gzip'
        }
        else {
            'none'
        }

        $opened = [pscustomobject][ordered]@{
            Stream               = $expanded
            SourceKind           = 'remote'
            SourcePath           = ''
            SourceReference      = $sourceId
            Compression          = $compression
            Resources            = @()
            TransportContract    = 5
            StatusCode           = [int]$payload.StatusCode
            ContentType          = [string]$payload.ContentType
            ContentEncodings     = $contentEncodingArray
            RawContentLength     = $payload.ContentLength
        }

        # Ownership is now held by the BoundedDecompressionStream. It owns the
        # GZipStream layer(s), response stream, and ChannelForgeHttpsPayload.
        $payload = $null
        $expanded = $null
        return $opened
    }
    catch {
        if ($null -ne $expanded) {
            try { $expanded.Dispose() } catch { }
        }

        if ($null -ne $payload) {
            try { $payload.Dispose() } catch { }
        }

        throw
    }
}

function New-ChannelForgeRemoteXmltvCacheOpenedFromPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Payload,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [psobject]$KeyInfo,

        [Parameter(Mandatory)]
        [string]$CacheRoot,

        [long]$MaxDocumentBytes,

        [ValidateSet('FreshFetched', 'HashMatched200', 'InvalidatedThenFetched')]
        [string]$Reason = 'FreshFetched',

        [AllowEmptyString()]
        [string]$PreviousPayloadHash = ''
    )

    $expanded = $null
    $tee = $null
    $payloadOwner = $Payload
    try {
        $contentEncodings = [System.Collections.Generic.List[string]]::new()
        foreach ($encoding in @($Payload.ContentEncodings)) {
            if ($null -ne $encoding) {
                [void]$contentEncodings.Add(([string]$encoding).Trim())
            }
        }
        $contentEncodingArray = $contentEncodings.ToArray()

        $expanded = Expand-ChannelForgePinnedHttpContentStream `
            -ContentEncodings $contentEncodingArray `
            -InnerStream $Payload.ResponseStream `
            -Owner $Payload `
            -MaxDecompressedBytes $MaxDocumentBytes

        New-Item -ItemType Directory -Force -Path $KeyInfo.EntryRoot | Out-Null
        $temporaryPayload = Join-Path $KeyInfo.EntryRoot (
            "payload-$([guid]::NewGuid().ToString('N')).tmp")
        Assert-ChannelForgeWritePath -Path $temporaryPayload -AllowedRoot $CacheRoot
        $tee = [ChannelForgeRemoteXmltvCacheTeeStream]::new(
            $expanded.Source,
            $temporaryPayload)

        # The decompression boundary remains the outer stream and the only
        # decompressed-byte limit. The tee observes bytes after decoding without
        # introducing another bounded wrapper or taking ownership of the payload.
        $expanded.Source = $tee
        $expanded.OwnedStreams = [System.IO.Stream[]](@($tee) + @($expanded.OwnedStreams))

        $opened = [pscustomobject][ordered]@{
            Stream          = $expanded
            SourceKind      = 'remote'
            SourcePath      = ''
            SourceReference = $SourceId
            Compression     = if (@($contentEncodingArray | Where-Object {
                    $_ -and $_.Trim().ToLowerInvariant() -in @('gzip', 'x-gzip')
                }).Count -gt 0) { 'gzip' } else { 'none' }
            Resources       = @()
            TransportContract = 5
            StatusCode       = [int]$Payload.StatusCode
            ContentType     = [string]$Payload.ContentType
            ContentEncodings = $contentEncodingArray
            RawContentLength = $Payload.ContentLength
            CacheOutcome    = 'Fetched'
            CacheReason     = $Reason
            CacheKey        = [string]$KeyInfo.Key
            CacheEntry      = $null
            CacheValidation = $null
            CacheWrite      = [pscustomobject][ordered]@{
                CacheRoot       = $CacheRoot
                EntryRoot       = $KeyInfo.EntryRoot
                MetadataPath    = $KeyInfo.MetadataPath
                Key             = $KeyInfo.Key
                TempPayloadPath = $temporaryPayload
                Tee             = $tee
                StatusCode      = [int]$Payload.StatusCode
                ContentType     = [string]$Payload.ContentType
                ContentEncodings = $contentEncodingArray
                RawContentLength = $Payload.ContentLength
                ETag            = if ($Payload.PSObject.Properties.Name -contains 'ETag') {
                    [string]$Payload.ETag
                }
                LastModified   = if ($Payload.PSObject.Properties.Name -contains 'LastModified') {
                    $Payload.LastModified
                }
                PreviousPayloadHash = $PreviousPayloadHash
            }
        }

        $payloadOwner = $null
        $expanded = $null
        $tee = $null
        return $opened
    }
    catch {
        if ($null -ne $expanded) {
            try { $expanded.Dispose() } catch { }
        }
        elseif ($null -ne $tee) {
            try { $tee.Dispose() } catch { }
        }

        if ($null -ne $payloadOwner) {
            try { $payloadOwner.Dispose() } catch { }
        }

        throw
    }
}

function New-ChannelForgeRemoteXmltvCacheHit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$CacheEntry,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [ValidateSet('FreshWithinTtl', 'Validated304')]
        [string]$Reason
    )

    $fileStream = $null
    $bounded = $null
    try {
        $fileStream = [System.IO.FileStream]::new(
            $CacheEntry.PayloadPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read,
            81920,
            [System.IO.FileOptions]::SequentialScan)
        $bounded = [BoundedStream]::new(
            $fileStream,
            [long]$CacheEntry.Metadata.MaxDecompressedBytes)

        $encodings = @($CacheEntry.Metadata.ContentEncodings | ForEach-Object {
            if ($null -eq $_) { '' } else { ([string]$_).Trim() }
        })
        $compression = if (@($encodings | Where-Object {
                $_ -and $_.ToLowerInvariant() -in @('gzip', 'x-gzip')
            }).Count -gt 0) { 'gzip' } else { 'none' }

        $opened = [pscustomobject][ordered]@{
            Stream           = $bounded
            SourceKind       = 'remote'
            SourcePath       = ''
            SourceReference  = $SourceId
            Compression      = $compression
            Resources        = @()
            TransportContract = 5
            StatusCode       = [int]$CacheEntry.Metadata.SourceHttpStatusCode
            ContentType      = [string]$CacheEntry.Metadata.ContentType
            ContentEncodings  = [string[]]$encodings
            RawContentLength  = $CacheEntry.Metadata.RawContentLength
            CacheOutcome     = 'CacheHit'
            CacheReason      = $Reason
            CacheKey         = [string]$CacheEntry.Key
            CacheEntry       = $CacheEntry
            CacheValidation  = $null
            CacheWrite       = $null
        }

        $fileStream = $null
        $bounded = $null
        return $opened
    }
    catch {
        if ($null -ne $bounded) {
            try { $bounded.Dispose() } catch { }
        }
        if ($null -ne $fileStream) {
            try { $fileStream.Dispose() } catch { }
        }
        throw
    }
}

function Open-ChannelForgeRemoteXmltvSourceStreamWithCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Source,

        [Parameter(Mandatory)]
        [string]$CacheRoot,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes,

        [long]$MaxRawResponseBytes = 268435456,

        [datetimeoffset]$EvaluationTimeUtc = ([datetimeoffset]::UtcNow),

        [switch]$ForceUnconditional
    )

    if ($null -eq $Source) {
        throw 'Remote XMLTV source cannot be empty.'
    }

    $propertyNames = @($Source.PSObject.Properties.Name)
    $sourceId = if ($propertyNames -contains 'Name') { [string]$Source.Name } else { '' }
    $url = if ($propertyNames -contains 'Url') { [string]$Source.Url } else { '' }

    if ([string]::IsNullOrWhiteSpace($sourceId) -or
        [string]::IsNullOrWhiteSpace($url)) {
        throw 'Remote XMLTV source requires a source name and URL.'
    }

    $keyInfo = Get-ChannelForgeRemoteXmltvCacheKey `
        -SourceId $sourceId `
        -Url $url `
        -CacheRoot $CacheRoot `
        -MaxDocumentBytes $MaxDocumentBytes
    $candidate = if ($ForceUnconditional) {
        $null
    }
    else {
        Read-ChannelForgeRemoteXmltvFetchCache `
            -CacheRoot $CacheRoot `
            -SourceId $sourceId `
            -Url $url `
            -MaxDocumentBytes $MaxDocumentBytes `
            -EvaluationTimeUtc $EvaluationTimeUtc
    }

    if ($null -ne $candidate -and
        $candidate.MetadataValid -and
        $candidate.PayloadValid -and
        $candidate.IsFresh) {
        return New-ChannelForgeRemoteXmltvCacheHit `
            -CacheEntry $candidate `
            -SourceId $sourceId `
            -Reason 'FreshWithinTtl'
    }

    $invokeParameters = @{
        SourceId = $sourceId
        Url = $url
        MaxRawResponseBytes = $MaxRawResponseBytes
    }
    $conditional = $false
    if ($null -ne $candidate -and
        $candidate.MetadataValid -and
        $candidate.CanConditional) {
        $etag = [string]$candidate.Metadata.ETag
        if (-not [string]::IsNullOrWhiteSpace($etag)) {
            $invokeParameters.IfNoneMatch = $etag
            $conditional = $true
        }
        elseif ($null -ne $candidate.Metadata.LastModified -and
            -not [string]::IsNullOrWhiteSpace([string]$candidate.Metadata.LastModified)) {
            $lastModified = [datetimeoffset]::MinValue
            $parsed = [datetimeoffset]::TryParse(
                [string]$candidate.Metadata.LastModified,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$lastModified)
            if ($parsed) {
                $invokeParameters.IfModifiedSince = $lastModified
                $conditional = $true
            }
        }
    }

    $payload = $null
    try {
        if ($conditional) {
            $payload = Invoke-ChannelForgePinnedHttpXmltvAcquisition `
                @invokeParameters `
                -Allow304MetadataOnly

            if ($payload.StatusCode -eq 304) {
                $responseETag = if ($payload.PSObject.Properties.Name -contains 'ETag') {
                    [string]$payload.ETag
                }
                else { '' }
                $responseLastModified = if ($payload.PSObject.Properties.Name -contains 'LastModified') {
                    $payload.LastModified
                }
                else { $null }
                $payload.Dispose()
                $payload = $null

                if ($null -ne $candidate -and
                    $candidate.MetadataValid -and
                    $candidate.PayloadValid) {
                    $opened = New-ChannelForgeRemoteXmltvCacheHit `
                        -CacheEntry $candidate `
                        -SourceId $sourceId `
                        -Reason 'Validated304'
                    $opened.CacheValidation = [pscustomobject]@{
                        ETag = $responseETag
                        LastModified = $responseLastModified
                    }
                    return $opened
                }

                # A metadata-only response cannot publish without a complete
                # local payload. This is the one explicit repair fetch allowed
                # by the cache policy.
                $payload = Invoke-ChannelForgePinnedHttpXmltvAcquisition `
                    -SourceId $sourceId `
                    -Url $url `
                    -MaxRawResponseBytes $MaxRawResponseBytes
                return New-ChannelForgeRemoteXmltvCacheOpenedFromPayload `
                    -Payload $payload `
                    -SourceId $sourceId `
                    -KeyInfo $keyInfo `
                    -CacheRoot $CacheRoot `
                    -MaxDocumentBytes $MaxDocumentBytes `
                    -Reason 'InvalidatedThenFetched'
            }

            return New-ChannelForgeRemoteXmltvCacheOpenedFromPayload `
                -Payload $payload `
                -SourceId $sourceId `
                -KeyInfo $keyInfo `
                -CacheRoot $CacheRoot `
                -MaxDocumentBytes $MaxDocumentBytes `
                -Reason 'FreshFetched' `
                -PreviousPayloadHash $(if ($null -ne $candidate.Metadata) {
                    [string]$candidate.Metadata.PayloadSha256
                }
                else {
                    ''
                })
        }

        $payload = Invoke-ChannelForgePinnedHttpXmltvAcquisition `
            -SourceId $sourceId `
            -Url $url `
            -MaxRawResponseBytes $MaxRawResponseBytes
        return New-ChannelForgeRemoteXmltvCacheOpenedFromPayload `
            -Payload $payload `
            -SourceId $sourceId `
            -KeyInfo $keyInfo `
            -CacheRoot $CacheRoot `
            -MaxDocumentBytes $MaxDocumentBytes `
            -Reason $(if ($ForceUnconditional) { 'InvalidatedThenFetched' } else { 'FreshFetched' }) `
            -PreviousPayloadHash $(if ($null -ne $candidate.Metadata) {
                [string]$candidate.Metadata.PayloadSha256
            }
            else {
                ''
            })
    }
    catch {
        if ($null -ne $payload) {
            try { $payload.Dispose() } catch { }
        }
        throw
    }
}
