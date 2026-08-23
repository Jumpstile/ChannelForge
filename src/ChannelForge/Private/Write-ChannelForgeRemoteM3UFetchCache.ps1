function Write-ChannelForgeRemoteM3UFetchCacheJson {
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
            'The remote M3U cache metadata could not be committed.',
            $_.Exception)
        $exception.Data['ChannelForgeFailureCategory'] = 'CacheWriteFailure'
        throw $exception
    }
}

function Remove-ChannelForgeRemoteM3UFetchCacheEntry {
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

function Write-ChannelForgeRemoteM3UFetchCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$CacheWrite,

        [Parameter(Mandatory)]
        [object[]]$Channels,

        [Parameter(Mandatory)]
        [string]$ProviderId,

        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [long]$MaxDocumentBytes,

        [ValidateSet('FreshFetched', 'HashMatched200', 'InvalidatedThenFetched')]
        [string]$Reason = 'FreshFetched'
    )

    if ($null -eq $CacheWrite.Tee -or -not $CacheWrite.Tee.Disposed) {
        throw 'The remote M3U cache stream must be closed before commit.'
    }
    if ($CacheWrite.Tee.WriteFailed) {
        $exception = [System.InvalidOperationException]::new('The remote M3U cache payload could not be durably flushed.')
        $exception.Data['ChannelForgeFailureCategory'] = 'CacheWriteFailure'
        throw $exception
    }

    $policy = Get-ChannelForgeRemoteM3UCachePolicy -MaxDocumentBytes $MaxDocumentBytes
    $entryRoot = [string]$CacheWrite.EntryRoot
    $cacheRoot = [string]$CacheWrite.CacheRoot
    $temporaryPayload = [string]$CacheWrite.TempPayloadPath

    if (-not (Test-Path -LiteralPath $temporaryPayload -PathType Leaf)) {
        throw 'The remote M3U cache payload was not produced.'
    }

    $payloadHash = $CacheWrite.Tee.GetHashHex()
    if ($payloadHash -notmatch '^[0-9a-f]{64}$') {
        throw 'The remote M3U cache payload hash is invalid.'
    }

    $payloadFile = "payload-$payloadHash.m3u"
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

        $now = [datetimeoffset]::UtcNow.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        $metadata = [ordered]@{
            CacheFormatVersion       = $policy.CacheFormatVersion
            CacheVersion             = $policy.CacheVersion
            KeyAlgorithm             = $policy.KeyAlgorithm
            KeyVersion               = $policy.KeyVersion
            CacheKey                 = [string]$CacheWrite.Key
            ProviderId               = $ProviderId.Trim()
            SourceId                 = $SourceId.Trim()
            Format                   = $policy.Format
            TransportContractVersion = $policy.TransportContract
            ParserCacheVersion       = $policy.ParserCacheVersion
            MaxDecompressedBytes     = $policy.MaxDecompressedBytes
            ContentType              = if ([string]::IsNullOrWhiteSpace([string]$CacheWrite.ContentType)) { $null } else { [string]$CacheWrite.ContentType }
            ContentEncodings         = @($CacheWrite.ContentEncodings)
            PayloadFile              = $payloadFile
            PayloadByteCount         = [long]$CacheWrite.Tee.BytesRead
            PayloadSha256             = $payloadHash
            RawContentLength         = $CacheWrite.RawContentLength
            ChannelCount             = @($Channels).Count
            FetchedAtUtc             = $now
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

        Write-ChannelForgeRemoteM3UFetchCacheJson `
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
            'The remote M3U cache entry could not be committed.',
            $_.Exception)
        $exception.Data['ChannelForgeFailureCategory'] = 'CacheWriteFailure'
        throw $exception
    }
}

function Update-ChannelForgeRemoteM3UFetchCacheValidation {
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

    $allowedRoot = Split-Path -Parent (Split-Path -Parent $CacheEntry.MetadataPath)
    Write-ChannelForgeRemoteM3UFetchCacheJson `
        -Path $CacheEntry.MetadataPath `
        -Value $updated `
        -AllowedRoot $allowedRoot

    return [pscustomobject]$updated
}
