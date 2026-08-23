function Write-ChannelForgeRemoteXmltvFetchCacheJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$AllowedRoot
    )

    Assert-ChannelForgeWritePath -Path $Path -AllowedRoot $AllowedRoot
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    Assert-ChannelForgeWritePath -Path $temporaryPath -AllowedRoot $AllowedRoot
    try {
        $json = $Value | ConvertTo-Json -Depth 12 -Compress
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
        $stream = [System.IO.FileStream]::new(
            $temporaryPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            81920,
            [System.IO.FileOptions]::SequentialScan)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $backupPath = "$Path.$([guid]::NewGuid().ToString('N')).bak"
            Assert-ChannelForgeWritePath -Path $backupPath -AllowedRoot $AllowedRoot
            try {
                [System.IO.File]::Replace($temporaryPath, $Path, $backupPath, $true)
            }
            finally {
                if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        else {
            [System.IO.File]::Move($temporaryPath, $Path)
        }
    }
    catch {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }

        $exception = [System.InvalidOperationException]::new(
            'The remote XMLTV cache metadata could not be committed.',
            $_.Exception)
        $exception.Data['ChannelForgeFailureCategory'] = 'CacheWriteFailure'
        throw $exception
    }
}

function Remove-ChannelForgeRemoteXmltvFetchCacheEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$CacheEntry
    )

    foreach ($path in @(
        $CacheEntry.MetadataPath
        $CacheEntry.PayloadPath
        $CacheEntry.TempPayloadPath
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path) -and
            (Test-Path -LiteralPath $path -PathType Leaf)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$CacheEntry.EntryRoot) -and
        (Test-Path -LiteralPath $CacheEntry.EntryRoot -PathType Container)) {
        foreach ($temporary in @(Get-ChildItem -LiteralPath $CacheEntry.EntryRoot -Filter '*.tmp' -File -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $temporary.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-ChannelForgeRemoteXmltvFetchCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$CacheWrite,

        [Parameter(Mandatory)]
        [object[]]$Programmes,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [long]$MaxDocumentBytes,

        [ValidateSet('FreshFetched', 'HashMatched200', 'InvalidatedThenFetched')]
        [string]$Reason = 'FreshFetched'
    )

    if ($null -eq $CacheWrite.Tee -or
        -not $CacheWrite.Tee.Disposed) {
        throw 'The remote XMLTV cache stream must be closed before commit.'
    }
    if ($CacheWrite.Tee.WriteFailed) {
        $exception = [System.InvalidOperationException]::new('The remote XMLTV cache payload could not be durably flushed.')
        $exception.Data['ChannelForgeFailureCategory'] = 'CacheWriteFailure'
        throw $exception
    }

    $policy = Get-ChannelForgeRemoteXmltvCachePolicy -MaxDocumentBytes $MaxDocumentBytes
    $entryRoot = [string]$CacheWrite.EntryRoot
    $cacheRoot = [string]$CacheWrite.CacheRoot
    $temporaryPayload = [string]$CacheWrite.TempPayloadPath

    if (-not (Test-Path -LiteralPath $temporaryPayload -PathType Leaf)) {
        throw 'The remote XMLTV cache payload was not produced.'
    }

    $payloadHash = $CacheWrite.Tee.GetHashHex()
    if ($payloadHash -notmatch '^[0-9a-f]{64}$') {
        throw 'The remote XMLTV cache payload hash is invalid.'
    }

    $payloadFile = "payload-$payloadHash.xml"
    $payloadPath = Join-Path $entryRoot $payloadFile
    $metadataPath = Join-Path $entryRoot 'metadata.json'
    Assert-ChannelForgeWritePath -Path $payloadPath -AllowedRoot $cacheRoot
    Assert-ChannelForgeWritePath -Path $metadataPath -AllowedRoot $cacheRoot
    New-Item -ItemType Directory -Force -Path $entryRoot | Out-Null

    try {
        if (Test-Path -LiteralPath $payloadPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPayload -Force -ErrorAction Stop
        }
        else {
            [System.IO.File]::Move($temporaryPayload, $payloadPath)
        }

        $evidence = if (@($Programmes).Count -gt 0) {
            @($Programmes)[0].Evidence
        }
        else {
            $null
        }
        $channelCount = if ($null -ne $evidence -and $null -ne $evidence.ChannelCount) {
            [int]$evidence.ChannelCount
        }
        else {
            0
        }

        $now = [datetimeoffset]::UtcNow.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        $metadata = [ordered]@{
            CacheFormatVersion       = $policy.CacheFormatVersion
            CacheVersion             = $policy.CacheVersion
            KeyAlgorithm             = $policy.KeyAlgorithm
            KeyVersion               = $policy.KeyVersion
            CacheKey                 = [string]$CacheWrite.Key
            SourceId                 = $SourceId.Trim()
            Format                   = $policy.Format
            TransportContractVersion = $policy.TransportContract
            ParserCacheVersion       = $policy.ParserCacheVersion
            MaxDecompressedBytes     = $policy.MaxDecompressedBytes
            ContentType              = [string]$CacheWrite.ContentType
            ContentEncodings         = @($CacheWrite.ContentEncodings)
            PayloadFile              = $payloadFile
            PayloadByteCount         = [long]$CacheWrite.Tee.BytesRead
            PayloadSha256             = $payloadHash
            RawContentLength          = $CacheWrite.RawContentLength
            ProgrammeCount            = @($Programmes).Count
            ChannelCount             = $channelCount
            FetchedAtUtc              = $now
            ValidatedAtUtc            = $now
            TtlSeconds               = $policy.TtlSeconds
            ETag                     = $CacheWrite.ETag
            LastModified             = if ($null -ne $CacheWrite.LastModified) {
                ([datetimeoffset]$CacheWrite.LastModified).ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            else {
                $null
            }
            SourceHttpStatusCode     = [int]$CacheWrite.StatusCode
            LastValidationStatus     = [int]$CacheWrite.StatusCode
            OperationalReason        = $Reason
        }

        Write-ChannelForgeRemoteXmltvFetchCacheJson `
            -Path $metadataPath `
            -Value $metadata `
            -AllowedRoot $cacheRoot

        return [pscustomobject][ordered]@{
            Key          = [string]$CacheWrite.Key
            EntryRoot    = $entryRoot
            MetadataPath = $metadataPath
            PayloadPath  = $payloadPath
            Metadata     = [pscustomobject]$metadata
        }
    }
    catch {
        if (Test-Path -LiteralPath $temporaryPayload -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPayload -Force -ErrorAction SilentlyContinue
        }

        if ($_.Exception.Data['ChannelForgeFailureCategory']) {
            throw
        }

        $exception = [System.InvalidOperationException]::new(
            'The remote XMLTV cache entry could not be committed.',
            $_.Exception)
        $exception.Data['ChannelForgeFailureCategory'] = 'CacheWriteFailure'
        throw $exception
    }
}

function Update-ChannelForgeRemoteXmltvFetchCacheValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$CacheEntry,

        [AllowEmptyString()]
        [string]$ETag = '',

        [Nullable[datetimeoffset]]$LastModified,

        [int]$StatusCode = 304
    )

    if (-not $CacheEntry.MetadataValid -or -not $CacheEntry.PayloadValid) {
        throw 'A cache validation update requires a fully validated local entry.'
    }

    $updated = [ordered]@{}
    foreach ($property in $CacheEntry.Metadata.PSObject.Properties) {
        $updated[$property.Name] = $property.Value
    }

    $updated.ValidatedAtUtc = [datetimeoffset]::UtcNow.ToString(
        'o',
        [System.Globalization.CultureInfo]::InvariantCulture)
    $updated.LastValidationStatus = $StatusCode
    $updated.OperationalReason = 'Validated304'
    if (-not [string]::IsNullOrWhiteSpace($ETag)) {
        $updated.ETag = $ETag.Trim()
    }
    if ($LastModified.HasValue) {
        $updated.LastModified = $LastModified.Value.ToUniversalTime().ToString(
            'o',
            [System.Globalization.CultureInfo]::InvariantCulture)
    }

    Write-ChannelForgeRemoteXmltvFetchCacheJson `
        -Path $CacheEntry.MetadataPath `
        -Value $updated `
        -AllowedRoot (Split-Path -Parent (Split-Path -Parent $CacheEntry.MetadataPath))

    return [pscustomobject]$updated
}
