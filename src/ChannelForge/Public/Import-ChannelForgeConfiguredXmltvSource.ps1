function Import-ChannelForgeConfiguredXmltvSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [psobject]$Source,

        [long]$MaxDocumentBytes = 268435456,

        [long]$MaxRawResponseBytes = 268435456,

        [AllowEmptyString()]
        [string]$CacheRoot = '',

        [System.Collections.IDictionary]$AcquisitionStatus
    )

    if ($null -eq $Source) {
        throw 'A normalized EPG source record is required.'
    }

    $propertyNames = @($Source.PSObject.Properties.Name)
    $rawFormat = if ($propertyNames -contains 'Format') { [string]$Source.Format } else { '' }
    $format = if ([string]::IsNullOrWhiteSpace($rawFormat)) { 'xmltv' } else { $rawFormat.Trim().ToLowerInvariant() }

    if ($format -ne 'xmltv') {
        throw "Configured EPG source has unsupported format '$($rawFormat.Trim())'; only xmltv is supported."
    }

    $supported = if ($propertyNames -contains 'Supported') { [bool]$Source.Supported } else { $true }
    $rawUrl = if ($propertyNames -contains 'Url') { [string]$Source.Url } else { '' }
    $rawPath = if ($propertyNames -contains 'Path') { [string]$Source.Path } else { '' }
    $sourceKind = if ($propertyNames -contains 'SourceKind' -and
        -not [string]::IsNullOrWhiteSpace([string]$Source.SourceKind)) {
        ([string]$Source.SourceKind).Trim().ToLowerInvariant()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($rawUrl)) {
        'remote'
    }
    else {
        'local'
    }

    $sourceId = if ($propertyNames -contains 'Name') { [string]$Source.Name } else { '' }
    $isRemote = $sourceKind -eq 'remote' -or -not [string]::IsNullOrWhiteSpace($rawUrl)

    if ($isRemote) {
        if (-not $supported) {
            throw 'Configured EPG source is unsupported.'
        }

        $useCache = -not [string]::IsNullOrWhiteSpace($CacheRoot)
        $cacheRetryUsed = $false
        $forceUnconditional = $false

        while ($true) {
            $opened = $null
            $hashingStream = $null
            $hasher = $null
            $parserCompleted = $false
            try {
                if ($useCache) {
                    $opened = Open-ChannelForgeRemoteXmltvSourceStreamWithCache `
                        -Source $Source `
                        -CacheRoot $CacheRoot `
                        -MaxDocumentBytes $MaxDocumentBytes `
                        -MaxRawResponseBytes $MaxRawResponseBytes `
                        -ForceUnconditional:$forceUnconditional
                }
                else {
                    $opened = Open-ChannelForgeRemoteXmltvSourceStream `
                        -Source $Source `
                        -MaxDocumentBytes $MaxDocumentBytes `
                        -MaxRawResponseBytes $MaxRawResponseBytes
                }

                $hasher = [System.Security.Cryptography.SHA256]::Create()
                $prefix = [System.Text.Encoding]::ASCII.GetBytes("input-xmltv/v2$([char]0)")
                [void]$hasher.TransformBlock($prefix, 0, $prefix.Length, $prefix, 0)
                $hashingStream = [System.Security.Cryptography.CryptoStream]::new(
                    $opened.Stream, $hasher, [System.Security.Cryptography.CryptoStreamMode]::Read, $true)
                $programmes = @(Read-ChannelForgeXmltvDocument `
                    -Stream $hashingStream `
                    -SourceId $sourceId `
                    -SourcePath '' `
                    -SourceKind 'remote' `
                    -SourceReference $opened.SourceReference `
                    -Compression $opened.Compression `
                    -TransportContractVersion $opened.TransportContract `
                    -HttpStatusCode $opened.StatusCode `
                    -ContentType $opened.ContentType `
                    -ContentEncodings $opened.ContentEncodings `
                    -RawContentLength $opened.RawContentLength `
                    -MaxDocumentBytes $MaxDocumentBytes)
                $hashingStream.Dispose()
                $hashingStream = $null
                $inputArtifactHash = ([BitConverter]::ToString($hasher.Hash)).Replace('-', '').ToLowerInvariant()
                $parserCompleted = $true

                if ($null -ne $opened.Stream) {
                    $opened.Stream.Dispose()
                }

                if ($null -ne $opened.CacheWrite) {
                    $reason = [string]$opened.CacheReason
                    $payloadHash = $opened.CacheWrite.Tee.GetHashHex()
                    if (-not [string]::IsNullOrWhiteSpace([string]$opened.CacheWrite.PreviousPayloadHash) -and
                        $opened.CacheWrite.PreviousPayloadHash -ceq $payloadHash) {
                        $reason = 'HashMatched200'
                    }
                    $opened.CacheReason = $reason
                    Write-ChannelForgeRemoteXmltvFetchCache `
                        -CacheWrite $opened.CacheWrite `
                        -Programmes $programmes `
                        -SourceId $sourceId `
                        -MaxDocumentBytes $MaxDocumentBytes `
                        -Reason $reason | Out-Null
                }
                elseif ($null -ne $opened.CacheValidation) {
                    Update-ChannelForgeRemoteXmltvFetchCacheValidation `
                        -CacheEntry $opened.CacheEntry `
                        -ETag ([string]$opened.CacheValidation.ETag) `
                        -LastModified $opened.CacheValidation.LastModified `
                        -StatusCode 304 | Out-Null
                }

                if ($null -ne $AcquisitionStatus) {
                    $AcquisitionStatus.Clear()
                    $AcquisitionStatus['Outcome'] = if ($opened.PSObject.Properties.Name -contains 'CacheOutcome') {
                        [string]$opened.CacheOutcome
                    }
                    else {
                        'Fetched'
                    }
                    $AcquisitionStatus['Reason'] = if ($opened.PSObject.Properties.Name -contains 'CacheReason') {
                        [string]$opened.CacheReason
                    }
                    else {
                        'FreshFetched'
                    }
                    $AcquisitionStatus['CacheKey'] = if ($opened.PSObject.Properties.Name -contains 'CacheKey') {
                        [string]$opened.CacheKey
                    }
                    else {
                        $null
                    }
                    $AcquisitionStatus['InputArtifactHash'] = $inputArtifactHash
                }

                return $programmes
            }
            catch {
                if (-not $parserCompleted -and
                    $useCache -and
                    -not $cacheRetryUsed -and
                    $null -ne $opened -and
                    $opened.PSObject.Properties.Name -contains 'CacheOutcome' -and
                    [string]$opened.CacheOutcome -eq 'CacheHit') {
                    $cacheRetryUsed = $true
                    if ($null -ne $opened.CacheEntry) {
                        if ($null -ne $opened.Stream) {
                            try { $opened.Stream.Dispose() } catch { }
                            $opened.Stream = $null
                        }
                        Remove-ChannelForgeRemoteXmltvFetchCacheEntry -CacheEntry $opened.CacheEntry
                    }
                    $forceUnconditional = $true
                    continue
                }

                throw
            }
            finally {
                if ($null -ne $hashingStream) {
                    try { $hashingStream.Dispose() } catch { }
                }
                if ($null -ne $hasher) {
                    try { $hasher.Dispose() } catch { }
                }
                if ($null -ne $opened) {
                    if ($null -ne $opened.Stream) {
                        try { $opened.Stream.Dispose() } catch { }
                    }

                    foreach ($resource in @($opened.Resources)) {
                        try { $resource.Dispose() } catch { }
                    }
                }
            }
        }
    }

    if (-not $supported) {
        throw 'Configured EPG source is unsupported.'
    }

    if ([string]::IsNullOrWhiteSpace($rawPath)) {
        throw 'Configured EPG source has no local path.'
    }

    if ($rawPath -match '^[a-z][a-z0-9+.-]*://') {
        throw 'Configured XMLTV source accepts local file paths only; URL or network sources are not supported.'
    }

    return @(Import-ChannelForgeXmltvSource `
        -Path $rawPath.Trim() `
        -SourceId $sourceId `
        -MaxDocumentBytes $MaxDocumentBytes `
        -AcquisitionStatus $AcquisitionStatus)
}
