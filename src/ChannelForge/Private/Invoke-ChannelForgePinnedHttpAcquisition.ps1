function Get-ChannelForgePinnedHttpAcquisitionException {
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

function New-ChannelForgePinnedHttpAcquisitionFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception,

        [string]$FallbackCategory = 'AcquisitionFailure'
    )

    $inner = Get-ChannelForgePinnedHttpAcquisitionException -Exception $Exception
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
        "Pinned HTTPS acquisition failed [$category].")
    $failure.Data['ChannelForgeFailureCategory'] = $category
    $failure.Data['ChannelForgeFailurePhase'] = $phase
    if ($null -ne $statusCode) {
        $failure.Data['ChannelForgeFailureStatusCode'] = [int]$statusCode
    }

    return $failure
}

function Invoke-ChannelForgePinnedHttpAcquisition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceId,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$AllowedContentTypes,

        [switch]$AllowMissingContentType,

        [long]$MaxRawResponseBytes = 268435456,

        [AllowEmptyString()]
        [string]$IfNoneMatch = '',

        [Nullable[datetimeoffset]]$IfModifiedSince,

        [switch]$Allow304MetadataOnly
    )

    if (-not (Test-ChannelForgeSourceUrl -Url $Url)) {
        throw (New-ChannelForgePinnedHttpAcquisitionFailure `
            -Exception ([System.ArgumentException]::new('The remote endpoint is not an accepted HTTPS source.')) `
            -FallbackCategory 'InvalidEndpoint')
    }

    $transport = $null
    try {
        $transport = Initialize-ChannelForgePinnedHttpTransport
    }
    catch {
        throw (New-ChannelForgePinnedHttpAcquisitionFailure `
            -Exception $_.Exception `
            -FallbackCategory 'HelperInitializationFailure')
    }

    if ($null -eq $transport -or $transport.ContractVersion -ne 5 -or $null -eq $transport.Type) {
        throw (New-ChannelForgePinnedHttpAcquisitionFailure `
            -Exception ([System.InvalidOperationException]::new('The pinned HTTP transport contract is unavailable.')) `
            -FallbackCategory 'HelperInitializationFailure')
    }

    if ($MaxRawResponseBytes -le 0 -or
        $MaxRawResponseBytes -gt [BoundedDecompressionStream]::HardMaximumDecompressedBytes) {
        throw (New-ChannelForgePinnedHttpAcquisitionFailure `
            -Exception ([System.ArgumentOutOfRangeException]::new('MaxRawResponseBytes')) `
            -FallbackCategory 'ResponseTooLarge')
    }

    $normalizedAllowedTypes = @($AllowedContentTypes | ForEach-Object {
        if ($null -ne $_) { ([string]$_).Trim().ToLowerInvariant() }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $endpointMethod = $transport.Type.GetMethod(
        'ValidateEndpointAsync',
        [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static)
    $optionsType = $transport.Type.Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeHttpAcquisitionOptions',
        $false,
        $false)
    $conditionalRequestType = $transport.Type.Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeHttpConditionalRequest',
        $false,
        $false)
    $statusPolicyType = $transport.Type.Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeHttpStatusPolicy',
        $false,
        $false)

    if ($null -eq $endpointMethod -or
        $null -eq $optionsType -or
        $null -eq $conditionalRequestType -or
        $null -eq $statusPolicyType) {
        throw (New-ChannelForgePinnedHttpAcquisitionFailure `
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
            throw (New-ChannelForgePinnedHttpAcquisitionFailure `
                -Exception $_.Exception `
                -FallbackCategory 'EndpointValidationFailure')
        }

        try {
            $conditionalRequest = $null
            if (-not [string]::IsNullOrWhiteSpace($IfNoneMatch) -or $IfModifiedSince.HasValue) {
                $conditionalConstructor = $conditionalRequestType.GetConstructor([System.Type[]]@(
                    [string],
                    [Nullable[datetimeoffset]]
                ))
                if ($null -eq $conditionalConstructor) {
                    throw [System.InvalidOperationException]::new('The conditional request contract is incomplete.')
                }

                $conditionalRequest = $conditionalConstructor.Invoke([object[]]@(
                    $IfNoneMatch,
                    $(if ($IfModifiedSince.HasValue) {
                        [Nullable[datetimeoffset]]$IfModifiedSince.Value
                    }
                    else {
                        $null
                    })
                ))
            }

            $optionsConstructor = $optionsType.GetConstructor([System.Type[]]@(
                [string],
                [System.Collections.Generic.IEnumerable[string]],
                [bool],
                [long],
                $statusPolicyType,
                $conditionalRequestType
            ))
            if ($null -eq $optionsConstructor) {
                throw [System.InvalidOperationException]::new('The v5 acquisition options contract is incomplete.')
            }

            $statusName = if ($Allow304MetadataOnly) { 'Allow304MetadataOnly' } else { 'Require200' }
            $statusPolicy = [System.Enum]::Parse($statusPolicyType, $statusName)
            $options = $optionsConstructor.Invoke([object[]]@(
                $SourceId,
                [string[]]$normalizedAllowedTypes,
                [bool]$AllowMissingContentType,
                $MaxRawResponseBytes,
                $statusPolicy,
                $conditionalRequest
            ))
        }
        catch {
            throw (New-ChannelForgePinnedHttpAcquisitionFailure `
                -Exception $_.Exception `
                -FallbackCategory 'InvalidConditionalValidator')
        }

        try {
            $payloadTask = $transport.AcquisitionMethod.Invoke(
                $null,
                [object[]]@($endpoint, $options, [System.Threading.CancellationToken]::None))
            $payload = $payloadTask.GetAwaiter().GetResult()
        }
        catch {
            throw (New-ChannelForgePinnedHttpAcquisitionFailure `
                -Exception $_.Exception `
                -FallbackCategory 'AcquisitionFailure')
        }

        if ($null -eq $payload) {
            throw (New-ChannelForgePinnedHttpAcquisitionFailure `
                -Exception ([System.InvalidOperationException]::new('The remote response did not contain an authorized payload.')) `
                -FallbackCategory 'NonSuccessHttpStatus')
        }

        if ($payload.StatusCode -eq 304 -and
            -not $payload.HasPayload -and
            $Allow304MetadataOnly) {
            return $payload
        }

        if (-not $payload.HasPayload -or
            $payload.StatusCode -ne 200 -or
            $null -eq $payload.ResponseStream) {
            throw (New-ChannelForgePinnedHttpAcquisitionFailure `
                -Exception ([System.InvalidOperationException]::new('The remote response did not contain an authorized payload.')) `
                -FallbackCategory 'NonSuccessHttpStatus')
        }

        $contentType = if ($null -eq $payload.ContentType) { '' } else { ([string]$payload.ContentType).Trim().ToLowerInvariant() }
        if ([string]::IsNullOrWhiteSpace($contentType)) {
            if (-not $AllowMissingContentType) {
                throw (New-ChannelForgePinnedHttpAcquisitionFailure `
                    -Exception ([System.InvalidOperationException]::new('The remote response content type is missing.')) `
                    -FallbackCategory 'UnsupportedContentType')
            }
        }
        elseif ($contentType -notin $normalizedAllowedTypes) {
            throw (New-ChannelForgePinnedHttpAcquisitionFailure `
                -Exception ([System.InvalidOperationException]::new('The remote response content type is not permitted.')) `
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

        throw (New-ChannelForgePinnedHttpAcquisitionFailure `
            -Exception $_.Exception `
            -FallbackCategory 'AcquisitionFailure')
    }
}
