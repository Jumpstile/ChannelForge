function Import-ChannelForgeConfiguredM3USource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [psobject]$Source,

        [string]$Provider = '',

        [long]$MaxDocumentBytes = 268435456,

        [long]$MaxRawResponseBytes = 268435456,

        [AllowEmptyString()]
        [string]$CacheRoot = '',

        [System.Collections.IDictionary]$AcquisitionStatus
    )

    if ($null -eq $Source) {
        throw 'A configured provider M3U source record is required.'
    }

    $propertyNames = @($Source.PSObject.Properties.Name)
    $sourceId = if ($propertyNames -contains 'Name') { [string]$Source.Name } else { '' }
    $rawUrl = if ($propertyNames -contains 'Url') { [string]$Source.Url } else { '' }
    $providerId = if ($propertyNames -contains 'ProviderId' -and
        -not [string]::IsNullOrWhiteSpace([string]$Source.ProviderId)) {
        [string]$Source.ProviderId
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Provider)) {
        $Provider
    }
    else {
        ''
    }

    if ([string]::IsNullOrWhiteSpace($sourceId) -or
        [string]::IsNullOrWhiteSpace($rawUrl)) {
        throw 'Configured provider M3U source requires a source name and supported remote URL.'
    }

    if ($MaxDocumentBytes -le 0 -or
        $MaxDocumentBytes -gt [BoundedDecompressionStream]::HardMaximumDecompressedBytes) {
        throw 'MaxDocumentBytes must be greater than zero and no greater than the transport hard maximum.'
    }

    $useCache = -not [string]::IsNullOrWhiteSpace($CacheRoot)
    $cacheRetryUsed = $false
    $forceUnconditional = $false

    while ($true) {
        $opened = $null
        $reader = $null
        $hashingStream = $null
        $hasher = $null
        $parserCompleted = $false
        $cacheWriteToRemove = $null
        try {
            if ($useCache) {
                $opened = Open-ChannelForgeRemoteM3USourceStreamWithCache `
                    -Source ([pscustomobject]@{
                        Name       = $sourceId
                        Url        = $rawUrl
                        ProviderId = $providerId
                    }) `
                    -CacheRoot $CacheRoot `
                    -MaxDocumentBytes $MaxDocumentBytes `
                    -MaxRawResponseBytes $MaxRawResponseBytes `
                    -ForceUnconditional:$forceUnconditional
            }
            else {
                $opened = Open-ChannelForgeRemoteM3USourceStream `
                    -Source ([pscustomobject]@{
                        Name       = $sourceId
                        Url        = $rawUrl
                        ProviderId = $providerId
                    }) `
                    -MaxDocumentBytes $MaxDocumentBytes `
                    -MaxRawResponseBytes $MaxRawResponseBytes
            }

            $hasher = [System.Security.Cryptography.SHA256]::Create()
            $prefix = [System.Text.Encoding]::ASCII.GetBytes("input-m3u/v2$([char]0)")
            [void]$hasher.TransformBlock($prefix, 0, $prefix.Length, $prefix, 0)
            $hashingStream = [System.Security.Cryptography.CryptoStream]::new(
                $opened.Stream, $hasher, [System.Security.Cryptography.CryptoStreamMode]::Read, $true)
            $reader = [System.IO.StreamReader]::new(
                $hashingStream,
                [System.Text.UTF8Encoding]::new($false, $true),
                $true,
                8192,
                $false)
            $channels = @(Read-ChannelForgeM3UReader `
                -Reader $reader `
                -Provider $(if ($Provider) { $Provider } else { $providerId }) `
                -Playlist $sourceId)
            $parserCompleted = $true

            $reader.Dispose()
            $reader = $null
            $hashingStream = $null
            $inputArtifactHash = ([BitConverter]::ToString($hasher.Hash)).Replace('-', '').ToLowerInvariant()

            if ($null -ne $opened.CacheWrite) {
                $reason = [string]$opened.CacheReason
                $payloadHash = $opened.CacheWrite.Tee.GetHashHex()
                if (-not [string]::IsNullOrWhiteSpace([string]$opened.CacheWrite.PreviousPayloadHash) -and
                    $opened.CacheWrite.PreviousPayloadHash -ceq $payloadHash) {
                    $reason = 'HashMatched200'
                }
                $opened.CacheReason = $reason
                Write-ChannelForgeRemoteM3UFetchCache `
                    -CacheWrite $opened.CacheWrite `
                    -Channels $channels `
                    -ProviderId $providerId `
                    -SourceId $sourceId `
                    -MaxDocumentBytes $MaxDocumentBytes `
                    -Reason $reason | Out-Null
            }
            elseif ($null -ne $opened.CacheValidation) {
                Update-ChannelForgeRemoteM3UFetchCacheValidation `
                    -CacheEntry $opened.CacheEntry `
                    -ETag ([string]$opened.CacheValidation.ETag) `
                    -LastModified $opened.CacheValidation.LastModified `
                    -StatusCode 304 | Out-Null
            }

            if ($null -ne $AcquisitionStatus) {
                $AcquisitionStatus.Clear()
                $AcquisitionStatus['ProviderId'] = $providerId
                $AcquisitionStatus['SourceId'] = $sourceId
                $AcquisitionStatus['Outcome'] = [string]$opened.CacheOutcome
                $AcquisitionStatus['Reason'] = [string]$opened.CacheReason
                $AcquisitionStatus['CacheKey'] = if ($useCache) { [string]$opened.CacheKey } else { $null }
                $AcquisitionStatus['StatusCode'] = [int]$opened.StatusCode
                $AcquisitionStatus['ContentType'] = [string]$opened.ContentType
                $AcquisitionStatus['ContentEncodings'] = @($opened.ContentEncodings)
                $AcquisitionStatus['RawContentLength'] = $opened.RawContentLength
                $AcquisitionStatus['DecompressedBytes'] = [long]$opened.Stream.BytesRead
                $AcquisitionStatus['InputArtifactHash'] = $inputArtifactHash
                $AcquisitionStatus['ChannelCount'] = @($channels).Count
                $AcquisitionStatus['HasETag'] = if ($null -ne $opened.CacheWrite) {
                    -not [string]::IsNullOrWhiteSpace([string]$opened.CacheWrite.ETag)
                }
                elseif ($null -ne $opened.CacheEntry) {
                    -not [string]::IsNullOrWhiteSpace([string]$opened.CacheEntry.Metadata.ETag)
                }
                else { $false }
                $AcquisitionStatus['HasLastModified'] = if ($null -ne $opened.CacheWrite) {
                    $null -ne $opened.CacheWrite.LastModified
                }
                elseif ($null -ne $opened.CacheEntry) {
                    $null -ne $opened.CacheEntry.Metadata.LastModified -and
                    -not [string]::IsNullOrWhiteSpace([string]$opened.CacheEntry.Metadata.LastModified)
                }
                else { $false }
            }

            return @($channels)
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
                    Remove-ChannelForgeRemoteM3UFetchCacheEntry -CacheEntry $opened.CacheEntry
                }
                $forceUnconditional = $true
                continue
            }

            if ($null -ne $opened -and $null -ne $opened.CacheWrite) {
                $cacheWriteToRemove = $opened.CacheWrite
            }

            throw
        }
        finally {
            if ($null -ne $reader) {
                try { $reader.Dispose() } catch { }
            }
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
            if ($null -ne $cacheWriteToRemove) {
                Remove-ChannelForgeRemoteM3UFetchCacheEntry -CacheEntry $cacheWriteToRemove
            }
        }
    }
}
