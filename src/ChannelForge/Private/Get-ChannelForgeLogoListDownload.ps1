function Get-ChannelForgeLogoListDownload {
    [CmdletBinding()]
    param(
        # UNVERIFIED address of the iptv-org logo list. Check it on the first dry run.
        [string]$Url = 'https://iptv-org.github.io/api/logos.json'
    )

    # One job: fetch the logo list as text. This is the ONLY network use of the
    # logo lookup feature. Owner-run refresh only; tests replace this function.
    # Reuses the pinned HTTPS transport (public hosts only, size limits).
    $limit = 64MB
    $payload = Invoke-ChannelForgePinnedHttpAcquisition `
        -SourceId 'logo-lookup' `
        -Url $Url `
        -AllowedContentTypes @('application/json', 'text/plain') `
        -MaxRawResponseBytes $limit

    $expanded = $null
    $reader = $null
    try {
        $expanded = Expand-ChannelForgePinnedHttpContentStream `
            -ContentEncodings @($payload.ContentEncodings | ForEach-Object { [string]$_ }) `
            -InnerStream $payload.ResponseStream `
            -Owner $payload `
            -MaxDecompressedBytes $limit
        $payload = $null
        $reader = [System.IO.StreamReader]::new($expanded, [System.Text.UTF8Encoding]::new($false, $true))
        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $expanded) { $expanded.Dispose() }
        if ($null -ne $payload) { $payload.Dispose() }
    }
}
