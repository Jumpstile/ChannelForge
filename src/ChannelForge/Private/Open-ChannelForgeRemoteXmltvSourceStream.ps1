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

        [long]$MaxRawResponseBytes = 268435456
    )

    if (-not (Test-ChannelForgeSourceUrl -Url $Url)) {
        throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
            -Exception ([System.ArgumentException]::new('The remote XMLTV endpoint is not an accepted HTTPS source.')) `
            -FallbackCategory 'InvalidEndpoint')
    }

    $transport = $null
    try {
        $transport = Initialize-ChannelForgePinnedHttpTransport
    }
    catch {
        throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
            -Exception $_.Exception `
            -FallbackCategory 'HelperInitializationFailure')
    }

    if ($null -eq $transport -or $transport.ContractVersion -ne 4 -or $null -eq $transport.Type) {
        throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
            -Exception ([System.InvalidOperationException]::new('The pinned HTTP transport contract is unavailable.')) `
            -FallbackCategory 'HelperInitializationFailure')
    }

    if ($MaxRawResponseBytes -le 0 -or
        $MaxRawResponseBytes -gt [BoundedDecompressionStream]::HardMaximumDecompressedBytes) {
        throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
            -Exception ([System.ArgumentOutOfRangeException]::new('MaxRawResponseBytes')) `
            -FallbackCategory 'ResponseTooLarge')
    }

    $endpointMethod = $transport.Type.GetMethod(
        'ValidateEndpointAsync',
        [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static)
    $optionsType = $transport.Type.Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeHttpAcquisitionOptions',
        $false,
        $false)
    $statusPolicyType = $transport.Type.Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeHttpStatusPolicy',
        $false,
        $false)

    if ($null -eq $endpointMethod -or $null -eq $optionsType -or $null -eq $statusPolicyType) {
        throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
            -Exception ([System.InvalidOperationException]::new('The pinned HTTP transport acquisition contract is incomplete.')) `
            -FallbackCategory 'ContractMismatch')
    }

    $payload = $null
    try {
        try {
            $endpointTask = $endpointMethod.Invoke(
                $null,
                [object[]]@($Url, [System.Threading.CancellationToken]::None))
            $endpoint = $endpointTask.GetAwaiter().GetResult()
        }
        catch {
            throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
                -Exception $_.Exception `
                -FallbackCategory 'EndpointValidationFailure')
        }

        try {
            $optionsConstructor = $optionsType.GetConstructor([System.Type[]]@(
                [string],
                [System.Collections.Generic.IEnumerable[string]],
                [bool],
                [long],
                $statusPolicyType
            ))
            $require200 = [System.Enum]::Parse($statusPolicyType, 'Require200')
            $options = $optionsConstructor.Invoke([object[]]@(
                $SourceId,
                [string[]]@('application/xml', 'text/xml'),
                $false,
                $MaxRawResponseBytes,
                $require200
            ))
        }
        catch {
            throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
                -Exception $_.Exception `
                -FallbackCategory 'InvalidEndpoint')
        }

        try {
            $payloadTask = $transport.AcquisitionMethod.Invoke(
                $null,
                [object[]]@($endpoint, $options, [System.Threading.CancellationToken]::None))
            $payload = $payloadTask.GetAwaiter().GetResult()
        }
        catch {
            throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
                -Exception $_.Exception `
                -FallbackCategory 'AcquisitionFailure')
        }

        if ($null -eq $payload -or
            -not $payload.HasPayload -or
            $payload.StatusCode -ne 200 -or
            $null -eq $payload.ResponseStream) {
            throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
                -Exception ([System.InvalidOperationException]::new('The remote XMLTV response did not contain an authorized payload.')) `
                -FallbackCategory 'NonSuccessHttpStatus')
        }

        if ([string]$payload.ContentType -notin @('application/xml', 'text/xml')) {
            throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
                -Exception ([System.InvalidOperationException]::new('The remote XMLTV response content type is not permitted.')) `
                -FallbackCategory 'UnsupportedContentType')
        }

        return $payload
    }
    catch {
        if ($null -ne $payload) {
            try { $payload.Dispose() } catch { }
        }

        if ($_.Exception.Data['ChannelForgeFailureCategory']) {
            throw
        }

        throw (New-ChannelForgeRemoteXmltvAcquisitionFailure `
            -Exception $_.Exception `
            -FallbackCategory 'AcquisitionFailure')
    }
}

function Open-ChannelForgeRemoteXmltvSourceStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Source,

        [long]$MaxDocumentBytes = [BoundedDecompressionStream]::HardMaximumDecompressedBytes
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
            -MaxRawResponseBytes $MaxDocumentBytes

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
            TransportContract    = 4
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
