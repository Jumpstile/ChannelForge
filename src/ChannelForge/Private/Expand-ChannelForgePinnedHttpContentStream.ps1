function New-ChannelForgeDecompressionFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Detail
    )

    $exception = [System.InvalidOperationException]::new(
        "ChannelForge bounded decompression failed [$Category]. $Detail")
    $exception.Data['ChannelForgeFailureCategory'] = $Category
    return $exception
}

function Expand-ChannelForgePinnedHttpContentStream {
    <#
        Undoes only registered HTTP Content-Encoding tokens (identity, gzip,
        x-gzip). This function has no knowledge of ZIP or any other
        payload/container format -- it never inspects content type, never
        sniffs file signatures, and never seeks or buffers the underlying
        stream. ZIP is a payload/container format, not an HTTP content coding,
        and remains entirely an adapter-level decision outside this function.

        Content-Encoding values are listed in the order they were applied
        (RFC 9110 8.4.1), so they must be undone in the reverse order: the
        last-listed encoding is removed first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ContentEncodings,

        [Parameter(Mandatory)]
        [System.IO.Stream]$InnerStream,

        [Parameter(Mandatory)]
        [System.IDisposable]$Owner,

        [long]$MaxDecompressedBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes
    )

    if ($MaxDecompressedBytes -le 0 -or
        $MaxDecompressedBytes -gt [BoundedDecompressionStream]::HardMaximumDecompressedBytes) {
        try { $Owner.Dispose() } catch { }
        throw (New-ChannelForgeDecompressionFailure `
            -Category 'DecompressionFailed' `
            -Detail 'the requested decompressed-byte limit is invalid or exceeds the hard maximum.')
    }

    $normalized = @(
        foreach ($token in $ContentEncodings) {
            if ($null -eq $token) { '' } else { $token.Trim().ToLowerInvariant() }
        }
    )

    foreach ($token in $normalized) {
        if ($token -ne '' -and $token -ne 'identity' -and $token -ne 'gzip' -and $token -ne 'x-gzip') {
            try { $Owner.Dispose() } catch { }
            throw (New-ChannelForgeDecompressionFailure `
                -Category 'UnsupportedContentEncoding' `
                -Detail 'the response declared a content coding that is not supported.')
        }
    }

    $wrapped = [System.Collections.Generic.List[System.IO.Stream]]::new()
    $current = $InnerStream

    try {
        for ($i = $normalized.Count - 1; $i -ge 0; $i--) {
            $token = $normalized[$i]
            if ($token -eq '' -or $token -eq 'identity') {
                continue
            }

            # token is 'gzip' or 'x-gzip' at this point; leaveOpen so this layer
            # never independently cascades disposal into the layer beneath it.
            $decoded = [System.IO.Compression.GZipStream]::new(
                $current,
                [System.IO.Compression.CompressionMode]::Decompress,
                $true)
            [void]$wrapped.Add($decoded)
            $current = $decoded
        }

        return [BoundedDecompressionStream]::new(
            $current,
            $wrapped.ToArray(),
            $Owner,
            $MaxDecompressedBytes)
    }
    catch {
        for ($i = $wrapped.Count - 1; $i -ge 0; $i--) {
            try { $wrapped[$i].Dispose() } catch { }
        }

        try { $Owner.Dispose() } catch { }
        throw
    }
}
