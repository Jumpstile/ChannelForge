function Get-ChannelForgeRemoteM3UContentTypes {
    return @(
        'application/vnd.apple.mpegurl'
        'video/vnd.mpegurl'
        'audio/mpegurl'
        'application/x-mpegurl'
        'audio/x-mpegurl'
        'text/plain'
        'application/octet-stream'
    )
}

function Invoke-ChannelForgePinnedHttpM3UAcquisition {
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
        -AllowedContentTypes (Get-ChannelForgeRemoteM3UContentTypes) `
        -AllowMissingContentType `
        -MaxRawResponseBytes $MaxRawResponseBytes `
        -IfNoneMatch $IfNoneMatch `
        -IfModifiedSince $IfModifiedSince `
        -Allow304MetadataOnly:$Allow304MetadataOnly
}

function New-ChannelForgeRemoteM3UCacheOpenedFromPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Payload,

        [Parameter(Mandatory)]
        [string]$ProviderId,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [psobject]$KeyInfo,

        [Parameter(Mandatory)]
        [string]$CacheRoot,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes,

        [ValidateSet('FreshFetched', 'HashMatched200', 'InvalidatedThenFetched')]
        [string]$Reason = 'FreshFetched',

        [AllowEmptyString()]
        [string]$PreviousPayloadHash = ''
    )

    $payloadOwner = $Payload
    $expanded = $null
    $tee = $null
    try {
        $payloadContentType = if ($null -eq $Payload.ContentType) { '' } else { ([string]$Payload.ContentType).Trim().ToLowerInvariant() }
        if (-not [string]::IsNullOrWhiteSpace($payloadContentType) -and
            $payloadContentType -notin (Get-ChannelForgeRemoteM3UContentTypes)) {
            $exception = [System.InvalidOperationException]::new('The remote M3U response content type is not permitted.')
            $exception.Data['ChannelForgeFailureCategory'] = 'UnsupportedContentType'
            throw $exception
        }

        $contentEncodingArray = @($Payload.ContentEncodings | ForEach-Object {
            if ($null -ne $_) { ([string]$_).Trim() }
        })

        $expanded = Expand-ChannelForgePinnedHttpContentStream `
            -ContentEncodings $contentEncodingArray `
            -InnerStream $Payload.ResponseStream `
            -Owner $Payload `
            -MaxDecompressedBytes $MaxDocumentBytes

        New-Item -ItemType Directory -Force -Path $KeyInfo.EntryRoot | Out-Null
        $temporaryPayload = Join-Path $KeyInfo.EntryRoot (
            "payload-$([guid]::NewGuid().ToString('N')).tmp")
        Assert-ChannelForgeWritePath -Path $temporaryPayload -AllowedRoot $CacheRoot
        $tee = [ChannelForgeRemoteM3UCacheTeeStream]::new(
            $expanded.Source,
            $temporaryPayload)

        # The decompression stream remains the only decompressed-byte boundary
        # and owns the decoder layers, tee, response stream, and transport owner.
        $expanded.Source = $tee
        $expanded.OwnedStreams = [System.IO.Stream[]](@($tee) + @($expanded.OwnedStreams))

        $contentType = if ($null -eq $Payload.ContentType) { '' } else { [string]$Payload.ContentType }
        $opened = [pscustomobject][ordered]@{
            Stream               = $expanded
            SourceKind           = 'remote'
            SourcePath           = ''
            SourceReference      = $SourceId
            Compression          = if (@($contentEncodingArray | Where-Object {
                    $_ -and $_.Trim().ToLowerInvariant() -in @('gzip', 'x-gzip')
                }).Count -gt 0) { 'gzip' } else { 'none' }
            Resources            = @()
            TransportContract    = 5
            StatusCode           = [int]$Payload.StatusCode
            ContentType          = $contentType
            ContentEncodings     = $contentEncodingArray
            RawContentLength     = $Payload.ContentLength
            ProviderId           = $ProviderId
            CacheOutcome         = 'Fetched'
            CacheReason          = $Reason
            CacheKey             = [string]$KeyInfo.Key
            CacheEntry           = $null
            CacheValidation      = $null
            CacheWrite           = [pscustomobject][ordered]@{
                CacheRoot        = $CacheRoot
                EntryRoot        = $KeyInfo.EntryRoot
                MetadataPath     = $KeyInfo.MetadataPath
                Key              = $KeyInfo.Key
                TempPayloadPath  = $temporaryPayload
                Tee              = $tee
                StatusCode       = [int]$Payload.StatusCode
                ContentType      = $contentType
                ContentEncodings = $contentEncodingArray
                RawContentLength = $Payload.ContentLength
                ETag             = if ($Payload.PSObject.Properties.Name -contains 'ETag') { [string]$Payload.ETag } else { '' }
                LastModified     = if ($Payload.PSObject.Properties.Name -contains 'LastModified') { $Payload.LastModified } else { $null }
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

function New-ChannelForgeRemoteM3UCacheHit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$CacheEntry,

        [Parameter(Mandatory)]
        [string]$ProviderId,

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
        $contentType = if ($null -eq $CacheEntry.Metadata.ContentType) { '' } else { [string]$CacheEntry.Metadata.ContentType }
        $opened = [pscustomobject][ordered]@{
            Stream               = $bounded
            SourceKind           = 'remote'
            SourcePath           = ''
            SourceReference      = $SourceId
            Compression          = if (@($encodings | Where-Object {
                    $_ -and $_.ToLowerInvariant() -in @('gzip', 'x-gzip')
                }).Count -gt 0) { 'gzip' } else { 'none' }
            Resources            = @()
            TransportContract    = 5
            StatusCode           = [int]$CacheEntry.Metadata.SourceHttpStatusCode
            ContentType          = $contentType
            ContentEncodings     = [string[]]$encodings
            RawContentLength     = $CacheEntry.Metadata.RawContentLength
            ProviderId           = $ProviderId
            CacheOutcome         = 'CacheHit'
            CacheReason          = $Reason
            CacheKey             = [string]$CacheEntry.Key
            CacheEntry           = $CacheEntry
            CacheValidation      = $null
            CacheWrite           = $null
        }

        $fileStream = $null
        $bounded = $null
        return $opened
    }
    catch {
        if ($null -ne $bounded) { try { $bounded.Dispose() } catch { } }
        if ($null -ne $fileStream) { try { $fileStream.Dispose() } catch { } }
        throw
    }
}

function Open-ChannelForgeRemoteM3USourceStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Source,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes,

        [long]$MaxRawResponseBytes = 268435456
    )

    $propertyNames = @($Source.PSObject.Properties.Name)
    $sourceId = if ($propertyNames -contains 'Name') { [string]$Source.Name } else { '' }
    $providerId = if ($propertyNames -contains 'ProviderId') { [string]$Source.ProviderId } elseif ($propertyNames -contains 'Provider') { [string]$Source.Provider } else { '' }
    $url = if ($propertyNames -contains 'Url') { [string]$Source.Url } else { '' }

    if ([string]::IsNullOrWhiteSpace($sourceId) -or [string]::IsNullOrWhiteSpace($url)) {
        throw 'Remote M3U source requires a source name and URL.'
    }

    $payload = $null
    $expanded = $null
    try {
        $payload = Invoke-ChannelForgePinnedHttpM3UAcquisition `
            -SourceId $sourceId `
            -Url $url `
            -MaxRawResponseBytes $MaxRawResponseBytes

        $payloadContentType = if ($null -eq $payload.ContentType) { '' } else { ([string]$payload.ContentType).Trim().ToLowerInvariant() }
        if (-not [string]::IsNullOrWhiteSpace($payloadContentType) -and
            $payloadContentType -notin (Get-ChannelForgeRemoteM3UContentTypes)) {
            $exception = [System.InvalidOperationException]::new('The remote M3U response content type is not permitted.')
            $exception.Data['ChannelForgeFailureCategory'] = 'UnsupportedContentType'
            throw $exception
        }

        $contentEncodingArray = @($Payload.ContentEncodings | ForEach-Object {
            if ($null -ne $_) { ([string]$_).Trim() }
        })
        $expanded = Expand-ChannelForgePinnedHttpContentStream `
            -ContentEncodings $contentEncodingArray `
            -InnerStream $payload.ResponseStream `
            -Owner $payload `
            -MaxDecompressedBytes $MaxDocumentBytes

        $opened = [pscustomobject][ordered]@{
            Stream               = $expanded
            SourceKind           = 'remote'
            SourcePath           = ''
            SourceReference      = $sourceId
            Compression          = if (@($contentEncodingArray | Where-Object {
                    $_ -and $_.Trim().ToLowerInvariant() -in @('gzip', 'x-gzip')
                }).Count -gt 0) { 'gzip' } else { 'none' }
            Resources            = @()
            TransportContract    = 5
            StatusCode           = [int]$payload.StatusCode
            ContentType          = if ($null -eq $payload.ContentType) { '' } else { [string]$payload.ContentType }
            ContentEncodings     = $contentEncodingArray
            RawContentLength     = $payload.ContentLength
            ProviderId           = $providerId
            CacheOutcome         = 'Fetched'
            CacheReason          = 'FreshFetched'
            CacheKey             = $null
            CacheEntry           = $null
            CacheValidation      = $null
            CacheWrite           = $null
        }

        $payload = $null
        $expanded = $null
        return $opened
    }
    catch {
        if ($null -ne $expanded) { try { $expanded.Dispose() } catch { } }
        if ($null -ne $payload) { try { $payload.Dispose() } catch { } }
        throw
    }
}

function Open-ChannelForgeRemoteM3USourceStreamWithCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Source,

        [Parameter(Mandatory)]
        [string]$CacheRoot,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes,

        [long]$MaxRawResponseBytes = 268435456,

        [switch]$ForceUnconditional
    )

    $propertyNames = @($Source.PSObject.Properties.Name)
    $sourceId = if ($propertyNames -contains 'Name') { [string]$Source.Name } else { '' }
    $providerId = if ($propertyNames -contains 'ProviderId') { [string]$Source.ProviderId } elseif ($propertyNames -contains 'Provider') { [string]$Source.Provider } else { '' }
    $url = if ($propertyNames -contains 'Url') { [string]$Source.Url } else { '' }

    if ([string]::IsNullOrWhiteSpace($sourceId) -or
        [string]::IsNullOrWhiteSpace($providerId) -or
        [string]::IsNullOrWhiteSpace($url)) {
        throw 'Remote M3U source requires a provider, source name, and URL.'
    }

    $keyInfo = Get-ChannelForgeRemoteM3UCacheKey `
        -ProviderId $providerId `
        -SourceId $sourceId `
        -Url $url `
        -CacheRoot $CacheRoot `
        -MaxDocumentBytes $MaxDocumentBytes
    $candidate = if ($ForceUnconditional) { $null } else {
        Read-ChannelForgeRemoteM3UFetchCache `
            -CacheRoot $CacheRoot `
            -ProviderId $providerId `
            -SourceId $sourceId `
            -Url $url `
            -MaxDocumentBytes $MaxDocumentBytes
    }

    if ($null -ne $candidate -and $candidate.MetadataValid -and
        $candidate.PayloadValid -and $candidate.IsFresh) {
        return New-ChannelForgeRemoteM3UCacheHit `
            -CacheEntry $candidate `
            -ProviderId $providerId `
            -SourceId $sourceId `
            -Reason 'FreshWithinTtl'
    }

    $invokeParameters = @{
        SourceId = $sourceId
        Url = $url
        MaxRawResponseBytes = $MaxRawResponseBytes
    }
    $conditional = $false
    if ($null -ne $candidate -and $candidate.MetadataValid -and $candidate.CanConditional) {
        $etag = [string]$candidate.Metadata.ETag
        if (-not [string]::IsNullOrWhiteSpace($etag)) {
            $invokeParameters.IfNoneMatch = $etag
            $conditional = $true
        }
        elseif ($null -ne $candidate.Metadata.LastModified -and
            -not [string]::IsNullOrWhiteSpace([string]$candidate.Metadata.LastModified)) {
            $lastModified = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse(
                    [string]$candidate.Metadata.LastModified,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind,
                    [ref]$lastModified)) {
                $invokeParameters.IfModifiedSince = $lastModified
                $conditional = $true
            }
        }
    }

    $payload = $null
    try {
        if ($conditional) {
            $payload = Invoke-ChannelForgePinnedHttpM3UAcquisition `
                @invokeParameters `
                -Allow304MetadataOnly

            if ($payload.StatusCode -eq 304) {
                $responseETag = if ($payload.PSObject.Properties.Name -contains 'ETag') { [string]$payload.ETag } else { '' }
                $responseLastModified = if ($payload.PSObject.Properties.Name -contains 'LastModified') { $payload.LastModified } else { $null }
                $payload.Dispose()
                $payload = $null

                if ($null -ne $candidate -and $candidate.MetadataValid -and $candidate.PayloadValid) {
                    $opened = New-ChannelForgeRemoteM3UCacheHit `
                        -CacheEntry $candidate `
                        -ProviderId $providerId `
                        -SourceId $sourceId `
                        -Reason 'Validated304'
                    $opened.CacheValidation = [pscustomobject]@{
                        ETag = $responseETag
                        LastModified = $responseLastModified
                    }
                    return $opened
                }

                # 304 cannot publish without a complete local payload. This is
                # the single authorized unconditional repair fetch.
                $payload = Invoke-ChannelForgePinnedHttpM3UAcquisition `
                    -SourceId $sourceId `
                    -Url $url `
                    -MaxRawResponseBytes $MaxRawResponseBytes
                return New-ChannelForgeRemoteM3UCacheOpenedFromPayload `
                    -Payload $payload `
                    -ProviderId $providerId `
                    -SourceId $sourceId `
                    -KeyInfo $keyInfo `
                    -CacheRoot $CacheRoot `
                    -MaxDocumentBytes $MaxDocumentBytes `
                    -Reason 'InvalidatedThenFetched'
            }

            return New-ChannelForgeRemoteM3UCacheOpenedFromPayload `
                -Payload $payload `
                -ProviderId $providerId `
                -SourceId $sourceId `
                -KeyInfo $keyInfo `
                -CacheRoot $CacheRoot `
                -MaxDocumentBytes $MaxDocumentBytes `
                -Reason 'FreshFetched' `
                -PreviousPayloadHash $(if ($null -ne $candidate.Metadata) { [string]$candidate.Metadata.PayloadSha256 } else { '' })
        }

        $payload = Invoke-ChannelForgePinnedHttpM3UAcquisition `
            -SourceId $sourceId `
            -Url $url `
            -MaxRawResponseBytes $MaxRawResponseBytes
        return New-ChannelForgeRemoteM3UCacheOpenedFromPayload `
            -Payload $payload `
            -ProviderId $providerId `
            -SourceId $sourceId `
            -KeyInfo $keyInfo `
            -CacheRoot $CacheRoot `
            -MaxDocumentBytes $MaxDocumentBytes `
            -Reason $(if ($ForceUnconditional) { 'InvalidatedThenFetched' } else { 'FreshFetched' }) `
            -PreviousPayloadHash $(if ($null -ne $candidate.Metadata) { [string]$candidate.Metadata.PayloadSha256 } else { '' })
    }
    catch {
        if ($null -ne $payload) { try { $payload.Dispose() } catch { } }
        throw
    }
}
