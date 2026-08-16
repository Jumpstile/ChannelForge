$script:ChannelForgePinnedHttpTransportInitializationLock = [System.Object]::new()
$script:ChannelForgePinnedHttpTransportInitializationResult = $null

function New-ChannelForgePinnedHttpTransportFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Category,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Detail,

        [Parameter()]
        [System.Exception]$InnerException
    )

    $message = "ChannelForgePinnedHttpTransport initialization failed [$Category]. $Detail"
    if ($null -eq $InnerException) {
        $exception = [System.InvalidOperationException]::new($message)
    }
    else {
        $exception = [System.InvalidOperationException]::new($message, $InnerException)
    }

    $exception.Data['ChannelForgeFailureCategory'] = $Category
    return $exception
}

function ConvertTo-ChannelForgePinnedHttpTransportDiagnosticText {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Records,

        [Parameter()]
        [AllowEmptyString()]
        [string]$SourcePath
    )

    $messages = @(
        foreach ($record in @($Records)) {
            if ($null -eq $record) {
                continue
            }

            $message = [string]$record
            if (-not [string]::IsNullOrEmpty($SourcePath)) {
                $message = [System.Text.RegularExpressions.Regex]::Replace(
                    $message,
                    [System.Text.RegularExpressions.Regex]::Escape($SourcePath),
                    '<module-source>',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            }

            if (-not [string]::IsNullOrWhiteSpace($message)) {
                $message.Trim()
            }
        }
    )

    if ($messages.Count -eq 0) {
        return 'no compiler diagnostics were returned.'
    }

    return [string]::Join([Environment]::NewLine, $messages)
}

function Test-ChannelForgePinnedHttpTransportRuntimeCapability {
    [CmdletBinding()]
    param()

    if ($null -eq $PSVersionTable -or $PSVersionTable.PSEdition -ne 'Core') {
        return $false
    }

    try {
        if ([version]$PSVersionTable.PSVersion -lt [version]'7.6') {
            return $false
        }

        if ([version][System.Environment]::Version -lt [version]'10.0') {
            return $false
        }

        $handlerType = [System.Type]::GetType(
            'System.Net.Http.SocketsHttpHandler, System.Net.Http',
            $false,
            $false)

        if ($null -eq $handlerType) {
            return $false
        }

        $callbackProperty = $handlerType.GetProperty(
            'ConnectCallback',
            [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::Public)

        return $null -ne $callbackProperty
    }
    catch {
        return $false
    }
}

function Get-ChannelForgePinnedHttpTransportLoadedType {
    [CmdletBinding()]
    param()

    $typeName = 'ChannelForge.Private.Transport.ChannelForgePinnedHttpTransport'
    $loadedMatches = [System.Collections.Generic.List[System.Type]]::new()

    foreach ($assembly in @([System.AppDomain]::CurrentDomain.GetAssemblies())) {
        try {
            $type = $assembly.GetType($typeName, $false, $false)
            if ($null -ne $type) {
                $loadedMatches.Add($type)
            }
        }
        catch {
            # An unrelated, partially loadable assembly must not prevent an
            # exact lookup in the remaining loaded assemblies.
            continue
        }
    }

    return @($loadedMatches)
}

function Get-ChannelForgePinnedHttpTransportContractState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Type]$Type
    )

    $flags = [System.Reflection.BindingFlags]::Public -bor
        [System.Reflection.BindingFlags]::Static -bor
        [System.Reflection.BindingFlags]::DeclaredOnly

    $nameField = $Type.GetField('ContractName', $flags)
    $versionField = $Type.GetField('ContractVersion', $flags)

    if ($null -eq $nameField -or
        -not $nameField.IsLiteral -or
        $nameField.FieldType -ne [string]) {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ContractMismatch'
            Detail = 'the loaded helper does not expose the required ContractName constant.'
        }
    }

    if ($null -eq $versionField -or
        -not $versionField.IsLiteral -or
        $versionField.FieldType -ne [int]) {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ContractMismatch'
            Detail = 'the loaded helper does not expose the required ContractVersion constant.'
        }
    }

    try {
        $contractName = [string]$nameField.GetRawConstantValue()
        $contractVersion = [int]$versionField.GetRawConstantValue()
    }
    catch {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ContractMismatch'
            Detail = 'the loaded helper contract constants could not be read.'
        }
    }

    if ($contractVersion -ne 2) {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ConflictingContract'
            Detail = "the loaded helper contract version '$contractVersion' is not the expected version '2'."
        }
    }

    if ($contractName -cne 'ChannelForgePinnedHttpTransport') {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ContractMismatch'
            Detail = 'the loaded helper ContractName does not match the required contract.'
        }
    }

    $endpointResultType = $Type.Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeValidatedEndpoint',
        $false,
        $false)
    if ($null -eq $endpointResultType -or
        -not $endpointResultType.IsPublic -or
        -not $endpointResultType.IsClass) {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ContractMismatch'
            Detail = 'the loaded helper does not expose the required validated endpoint type.'
        }
    }

    $endpointMethods = @(
        $Type.GetMethods($flags) | Where-Object {
            $parameters = $_.GetParameters()
            $parameters.Count -eq 2 -and
                $_.Name -ceq 'ValidateEndpointAsync' -and
                $parameters[0].ParameterType -eq [string] -and
                $parameters[1].ParameterType -eq [System.Threading.CancellationToken]
        }
    )
    if ($endpointMethods.Count -ne 1) {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ContractMismatch'
            Detail = 'the loaded helper does not expose exactly one endpoint validation method.'
        }
    }

    $endpointReturnType = $endpointMethods[0].ReturnType
    if (-not $endpointReturnType.IsGenericType -or
        $endpointReturnType.GetGenericTypeDefinition().FullName -cne ('System.Threading.Tasks.Task' + [char]96 + '1') -or
        $endpointReturnType.GetGenericArguments()[0] -ne $endpointResultType) {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ContractMismatch'
            Detail = 'the loaded helper endpoint validation method has the wrong return type.'
        }
    }

    $capabilityMethods = @(
        $Type.GetMethods($flags) | Where-Object {
            $_.Name -ceq 'HasRequiredCapabilities' -and
            $_.GetParameters().Count -eq 0
        }
    )

    if ($capabilityMethods.Count -ne 1 -or $capabilityMethods[0].ReturnType -ne [bool]) {
        return [pscustomobject]@{
            Valid = $false
            Category = 'ContractMismatch'
            Detail = 'the loaded helper does not expose the required capability contract.'
        }
    }

    return [pscustomobject]@{
        Valid = $true
        Category = $null
        Detail = $null
        ContractName = $contractName
        ContractVersion = $contractVersion
        EndpointMethod = $endpointMethods[0]
        EndpointResultType = $endpointResultType
        CapabilityMethod = $capabilityMethods[0]
    }
}

function Test-ChannelForgePinnedHttpTransportLoadedCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Reflection.MethodInfo]$CapabilityMethod
    )

    try {
        return [bool]$CapabilityMethod.Invoke($null, @())
    }
    catch {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'CapabilityUnavailable' `
            -Detail 'the loaded helper capability check could not be completed.' `
            -InnerException $_.Exception)
    }
}

function Get-ChannelForgePinnedHttpTransportSource {
    [CmdletBinding()]
    param()

    $module = $ExecutionContext.SessionState.Module
    $moduleBase = if ($null -ne $module) { [string]$module.ModuleBase } else { '' }
    if ([string]::IsNullOrWhiteSpace($moduleBase)) {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceIntegrityFailure' `
            -Detail 'the installed module base could not be established.')
    }

    try {
        $transportDirectory = [System.IO.Path]::GetFullPath(
            (Join-Path -Path $moduleBase -ChildPath 'Private\Transport'))
    }
    catch {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceIntegrityFailure' `
            -Detail 'the fixed transport directory could not be canonicalized.' `
            -InnerException $_.Exception)
    }

    $transportInfo = $null
    try {
        $transportInfo = Get-Item -LiteralPath $transportDirectory -Force -ErrorAction Stop
    }
    catch {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceMissing' `
            -Detail 'the fixed transport directory is not available.')
    }

    if (-not $transportInfo.PSIsContainer) {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceIntegrityFailure' `
            -Detail 'the fixed transport directory is not a directory.')
    }

    try {
        $sourcePath = [System.IO.Path]::GetFullPath(
            (Join-Path -Path $transportDirectory -ChildPath 'ChannelForgePinnedHttpTransport.cs'))
        $transportRoot = $transportDirectory.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar) +
            [System.IO.Path]::DirectorySeparatorChar

        if (-not $sourcePath.StartsWith($transportRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw (New-ChannelForgePinnedHttpTransportFailure `
                -Category 'SourceIntegrityFailure' `
                -Detail 'the fixed helper source is outside the expected transport directory.')
        }
    }
    catch {
        if ($null -ne $_.Exception.Data['ChannelForgeFailureCategory']) {
            throw
        }

        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceIntegrityFailure' `
            -Detail 'the fixed helper source path could not be canonicalized.' `
            -InnerException $_.Exception)
    }

    $sourceInfo = $null
    try {
        $sourceInfo = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
    }
    catch {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceMissing' `
            -Detail 'the fixed helper source is not available.')
    }

    if ($sourceInfo.PSIsContainer) {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceIntegrityFailure' `
            -Detail 'the fixed helper source is not a regular file.')
    }

    if (($sourceInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceIntegrityFailure' `
            -Detail 'the fixed helper source may not be a reparse point or symbolic link.')
    }

    try {
        $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $sourceText = $utf8.GetString($sourceBytes)
    }
    catch [System.Text.DecoderFallbackException] {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'InvalidSourceEncoding' `
            -Detail 'the fixed helper source is not valid strict UTF-8.' `
            -InnerException $_.Exception)
    }
    catch {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceIntegrityFailure' `
            -Detail 'the fixed helper source could not be read.' `
            -InnerException $_.Exception)
    }

    if ([string]::IsNullOrWhiteSpace($sourceText)) {
        throw (New-ChannelForgePinnedHttpTransportFailure `
            -Category 'SourceIntegrityFailure' `
            -Detail 'the fixed helper source is empty.')
    }

    return [pscustomobject]@{
        Path = $sourcePath
        Text = $sourceText
    }
}

function New-ChannelForgePinnedHttpTransportResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Type]$Type,

        [Parameter(Mandatory)]
        [ValidateSet('Compiled', 'Reused')]
        [string]$LoadMode,

        [Parameter()]
        [string[]]$CompilerWarnings = @()
    )

    return [pscustomobject]@{
        Type = $Type
        ContractVersion = 2
        LoadMode = $LoadMode
        CompilerWarnings = @($CompilerWarnings)
    }
}

function Initialize-ChannelForgePinnedHttpTransport {
    [CmdletBinding()]
    param()

    $lockTaken = $false
    [System.Threading.Monitor]::Enter($script:ChannelForgePinnedHttpTransportInitializationLock, [ref]$lockTaken)

    try {
        $loadedTypes = @(Get-ChannelForgePinnedHttpTransportLoadedType)
        if ($loadedTypes.Count -gt 1) {
            throw (New-ChannelForgePinnedHttpTransportFailure `
                -Category 'ConflictingContract' `
                -Detail 'multiple loaded helper definitions share the required fully-qualified type name.')
        }

        if ($loadedTypes.Count -eq 1) {
            $state = Get-ChannelForgePinnedHttpTransportContractState -Type $loadedTypes[0]
            if (-not $state.Valid) {
                throw (New-ChannelForgePinnedHttpTransportFailure `
                    -Category $state.Category `
                    -Detail $state.Detail)
            }

            if (-not (Test-ChannelForgePinnedHttpTransportLoadedCapability -CapabilityMethod $state.CapabilityMethod)) {
                throw (New-ChannelForgePinnedHttpTransportFailure `
                    -Category 'CapabilityUnavailable' `
                    -Detail 'the loaded helper reports that the required runtime capability is unavailable.')
            }

            $script:ChannelForgePinnedHttpTransportInitializationResult = New-ChannelForgePinnedHttpTransportResult `
                -Type $loadedTypes[0] `
                -LoadMode 'Reused' `
                -CompilerWarnings @()

            return $script:ChannelForgePinnedHttpTransportInitializationResult
        }

        if (-not (Test-ChannelForgePinnedHttpTransportRuntimeCapability)) {
            throw (New-ChannelForgePinnedHttpTransportFailure `
                -Category 'RuntimeUnsupported' `
                -Detail 'the current PowerShell/.NET runtime does not provide the required transport capability.')
        }

        $source = Get-ChannelForgePinnedHttpTransportSource
        $compilerWarnings = @()
        $compilerErrors = @()

        try {
            $null = @(Add-Type `
                -TypeDefinition $source.Text `
                -Language CSharp `
                -PassThru `
                -WarningVariable compilerWarnings `
                -ErrorVariable compilerErrors `
                -ErrorAction Stop)
        }
        catch {
            $diagnostics = ConvertTo-ChannelForgePinnedHttpTransportDiagnosticText `
                -Records (@($compilerWarnings) + @($compilerErrors) + @($_)) `
                -SourcePath $source.Path

            throw (New-ChannelForgePinnedHttpTransportFailure `
                -Category 'CompilationFailed' `
                -Detail $diagnostics `
                -InnerException $_.Exception)
        }

        $warningText = @(
            ConvertTo-ChannelForgePinnedHttpTransportDiagnosticText `
                -Records $compilerWarnings `
                -SourcePath $source.Path
        )
        if ($warningText.Count -eq 1 -and $warningText[0] -eq 'no compiler diagnostics were returned.') {
            $warningText = @()
        }
        elseif ($warningText.Count -gt 0) {
            foreach ($warning in $warningText) {
                Write-Warning "ChannelForgePinnedHttpTransport compiler warning: $warning"
            }
        }

        $loadedTypes = @(Get-ChannelForgePinnedHttpTransportLoadedType)
        if ($loadedTypes.Count -ne 1) {
            throw (New-ChannelForgePinnedHttpTransportFailure `
                -Category 'CompilationFailed' `
                -Detail 'compilation did not produce exactly one discoverable helper type.')
        }

        $state = Get-ChannelForgePinnedHttpTransportContractState -Type $loadedTypes[0]
        if (-not $state.Valid) {
            throw (New-ChannelForgePinnedHttpTransportFailure `
                -Category $state.Category `
                -Detail $state.Detail)
        }

        if (-not (Test-ChannelForgePinnedHttpTransportLoadedCapability -CapabilityMethod $state.CapabilityMethod)) {
            throw (New-ChannelForgePinnedHttpTransportFailure `
                -Category 'CapabilityUnavailable' `
                -Detail 'the compiled helper reports that the required runtime capability is unavailable.')
        }

        $script:ChannelForgePinnedHttpTransportInitializationResult = New-ChannelForgePinnedHttpTransportResult `
            -Type $loadedTypes[0] `
            -LoadMode 'Compiled' `
            -CompilerWarnings $warningText

        return $script:ChannelForgePinnedHttpTransportInitializationResult
    }
    finally {
        if ($lockTaken) {
            [System.Threading.Monitor]::Exit($script:ChannelForgePinnedHttpTransportInitializationLock)
        }
    }
}
