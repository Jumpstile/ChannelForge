BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    $script:ModuleSourceRoot = Join-Path $RepoRoot 'src\ChannelForge'
    $script:PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'

    if (-not (Test-Path -LiteralPath $script:PowerShellExecutable -PathType Leaf)) {
        $script:PowerShellExecutable = (Get-Command pwsh -ErrorAction Stop).Source
    }

    $script:ChildScriptPath = Join-Path $TestDrive 'Invoke-PinnedHttpTransportConnectionChild.ps1'
    @'
param(
    [Parameter(Mandatory)]
    [string]$ModulePath,

    [Parameter(Mandatory)]
    [ValidateSet('handler-policy', 'ordering', 'all-fail', 'host-mismatch', 'port-mismatch', 'cancelled', 'timeout', 'tls-match', 'tls-mismatch', 'loopback-policy', 'production-loopback', 'public-surface')]
    [string]$Scenario
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $ModulePath 'ChannelForge.psd1'

function Write-ChildResult {
    param([Parameter(Mandatory)][object]$Value)
    $Value | ConvertTo-Json -Compress -Depth 10
}

function Get-ExceptionDetails {
    param([Parameter(Mandatory)][System.Exception]$Exception)

    $exception = $Exception
    while (($exception -is [System.Reflection.TargetInvocationException] -or
            $exception -is [System.Management.Automation.MethodInvocationException] -or
            $exception -is [System.AggregateException]) -and
        $null -ne $exception.InnerException) {
        $exception = $exception.InnerException
    }

    $category = $null
    if ($null -ne $exception.PSObject.Properties['Category']) {
        $category = [string]$exception.Category
    }

    return [pscustomobject]@{
        Category = $category
        Message = [string]$exception.Message
    }
}

function Get-HelperType {
    $module = Get-Module -Name ChannelForge
    $initialization = & $module { Initialize-ChannelForgePinnedHttpTransport }
    return $initialization.Type
}

function New-SyntheticEndpoint {
    param(
        [string[]]$CandidateText = @('127.0.0.2'),
        [string]$HostName = 'transport.test.invalid'
    )

    $endpointType = $script:HelperType.Assembly.GetType(
        'ChannelForge.Private.Transport.ChannelForgeValidatedEndpoint',
        $true,
        $false)
    $constructor = @(
        $endpointType.GetConstructors(
            [System.Reflection.BindingFlags]::Instance -bor
                [System.Reflection.BindingFlags]::NonPublic) |
            Where-Object { $_.GetParameters().Count -eq 5 }
    )[0]

    $candidates = [System.Collections.Generic.List[System.Net.IPAddress]]::new()
    foreach ($candidate in $CandidateText) {
        $candidates.Add([System.Net.IPAddress]::Parse($candidate)) | Out-Null
    }

    return $constructor.Invoke([object[]]@(
        [Uri]("https://$HostName/"),
        $HostName,
        443,
        $false,
        $candidates))
}

function ConvertTo-Connector {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    return [System.Func[System.Net.IPAddress, System.Threading.CancellationToken, System.Threading.Tasks.ValueTask[System.IO.Stream]]]$ScriptBlock
}

function Invoke-ConnectCore {
    param(
        [Parameter(Mandatory)]$Endpoint,
        [Parameter(Mandatory)][string]$ContextHost,
        [Parameter(Mandatory)][int]$ContextPort,
        [Parameter(Mandatory)][System.Threading.CancellationToken]$CancellationToken,
        [Parameter(Mandatory)][TimeSpan]$ConnectionTimeout,
        [Parameter(Mandatory)]$Connector
    )

    $method = $script:HelperType.GetMethod(
        'ConnectPinnedForTest',
        [System.Reflection.BindingFlags]::Static -bor
            [System.Reflection.BindingFlags]::NonPublic)
    $operation = $method.Invoke($null, [object[]]@(
        $Endpoint,
        $ContextHost,
        $ContextPort,
        $CancellationToken,
        $ConnectionTimeout,
        $Connector))
    return $operation.AsTask().GetAwaiter().GetResult()
}

function Invoke-HandlerFactory {
    param([Parameter(Mandatory)]$Endpoint)

    $method = $script:HelperType.GetMethod(
        'CreatePinnedHandlerForTest',
        [System.Reflection.BindingFlags]::Static -bor
            [System.Reflection.BindingFlags]::NonPublic)
    return $method.Invoke($null, [object[]]@($Endpoint))
}

function Invoke-ProductionHandlerFactory {
    param([Parameter(Mandatory)]$Endpoint)

    $method = $script:HelperType.GetMethod(
        'CreatePinnedHandler',
        [System.Reflection.BindingFlags]::Static -bor
            [System.Reflection.BindingFlags]::NonPublic)
    return $method.Invoke($null, [object[]]@($Endpoint))
}

function New-TestCertificateChain {
    param([Parameter(Mandatory)][string]$ServerName)

    $notBefore = [DateTimeOffset]::UtcNow.AddMinutes(-5)
    $notAfter = [DateTimeOffset]::UtcNow.AddMinutes(30)
    $rootKey = [System.Security.Cryptography.RSA]::Create(2048)
    $rootRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=ChannelForge Test Root',
        $rootKey,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $rootRequest.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $false, 0, $true)) | Out-Null
    $rootRequest.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509SubjectKeyIdentifierExtension]::new($rootRequest.PublicKey, $false)) | Out-Null
    $rootCertificate = $rootRequest.CreateSelfSigned($notBefore, $notAfter)

    $serverKey = [System.Security.Cryptography.RSA]::Create(2048)
    $serverRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        "CN=$ServerName",
        $serverKey,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $san = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
    $san.AddDnsName($ServerName) | Out-Null
    $serverRequest.CertificateExtensions.Add($san.Build($false)) | Out-Null
    $serverRequest.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
            $false)) | Out-Null
    $serverEku = [System.Security.Cryptography.OidCollection]::new()
    $serverEku.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1')) | Out-Null
    $serverRequest.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
            $serverEku,
            $false)) | Out-Null
    $serverUnsigned = $serverRequest.Create(
        $rootCertificate,
        $notBefore,
        $notAfter,
        [byte[]](1, 2, 3, 4, 5, 6, 7, 8))
    $certificatePem = "-----BEGIN CERTIFICATE-----`n" +
        [Convert]::ToBase64String($serverUnsigned.RawData, [Base64FormattingOptions]::InsertLineBreaks) +
        "`n-----END CERTIFICATE-----"
    $serverCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem($certificatePem, $serverKey.ExportPkcs8PrivateKeyPem())
    $pfxPassword = 'ChannelForge-test-certificate'
    $pfxBytes = $serverCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $pfxPassword)
    $serverCertificate.Dispose()
    $serverCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $pfxBytes,
        $pfxPassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet -bor
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet)
    return [pscustomobject]@{
        Root = $rootCertificate
        Server = $serverCertificate
        RootKey = $rootKey
        ServerKey = $serverKey
        ServerUnsigned = $serverUnsigned
    }
}

function Invoke-TlsScenario {
    param([Parameter(Mandatory)][bool]$MatchingCertificate)

    $hostName = 'transport.test.invalid'
    $certificateName = if ($MatchingCertificate) { $hostName } else { 'other.test.invalid' }
    $chain = New-TestCertificateChain -ServerName $certificateName
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Parse('127.0.0.2'),
        443)
    $listener.Start()
    $acceptTask = $listener.AcceptTcpClientAsync()
    $endpoint = New-SyntheticEndpoint -CandidateText @('127.0.0.3', '127.0.0.2') -HostName $hostName
    $handler = Invoke-HandlerFactory -Endpoint $endpoint
    $productionChainPolicyWasNull = $null -eq $handler.SslOptions.CertificateChainPolicy
    $productionValidationCallbackWasNull = $null -eq $handler.SslOptions.RemoteCertificateValidationCallback

    $testPolicy = [System.Security.Cryptography.X509Certificates.X509ChainPolicy]::new()
    $testPolicy.TrustMode = [System.Security.Cryptography.X509Certificates.X509ChainTrustMode]::CustomRootTrust
    $testPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
    $testPolicy.CustomTrustStore.Add($chain.Root) | Out-Null
    $handler.SslOptions.CertificateChainPolicy = $testPolicy
    $client = [System.Net.Http.HttpClient]::new($handler)
    $accepted = $null
    $serverStream = $null
    $observedSni = $null
    $serverDestination = $null
    $serverError = $null
    $requestTask = $null
    $requestCancellation = [System.Threading.CancellationTokenSource]::new()

    try {
        $requestCancellation.CancelAfter(5000)
        $getAsync = [System.Net.Http.HttpClient].GetMethod('GetAsync', [Type[]]@([Uri], [System.Threading.CancellationToken]))
        $requestTask = [System.Threading.Tasks.Task[System.Net.Http.HttpResponseMessage]]$getAsync.Invoke($client, [object[]]@([Uri]'https://transport.test.invalid/', $requestCancellation.Token))
        if ($null -eq $requestTask) {
            return [pscustomobject]@{ Success = $false; Failure = 'NoRequestTask'; GetAsyncMethod = $null -ne $getAsync }
        }
        if (-not ($requestTask -is [System.Threading.Tasks.Task])) {
            return [pscustomobject]@{ Success = $false; Failure = 'RequestTaskNotTask'; RequestType = $requestTask.GetType().FullName }
        }
        if (-not $acceptTask.Wait(5000)) {
            try { $null = $requestTask.Result }
            catch {
                return [pscustomobject]@{ Success = $false; Failure = 'ConnectionFailure'; Message = [string]$_.Exception.Message }
            }

            return [pscustomobject]@{ Success = $false; Failure = 'ConnectionFailure' }
        }

        $accepted = $acceptTask.GetAwaiter().GetResult()
        $serverDestination = [string]$accepted.Client.LocalEndPoint.Address
        $serverStream = [System.Net.Security.SslStream]::new($accepted.GetStream(), $false)
        $certificate = $chain.Server
        $options = [System.Net.Security.SslServerAuthenticationOptions]::new()
        $sniHolder = [pscustomobject]@{ Name = $null }
        $options.ServerCertificateSelectionCallback = [System.Net.Security.ServerCertificateSelectionCallback]{
            param($sender, $serverName)
            $sniHolder.Name = [string]$serverName
            return $certificate
        }.GetNewClosure()

        try {
            $serverStream.AuthenticateAsServerAsync($options).GetAwaiter().GetResult()
            $observedSni = $sniHolder.Name
            if ($MatchingCertificate) {
                $buffer = New-Object byte[] 4096
                $null = $serverStream.Read($buffer, 0, $buffer.Length)
                $response = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 2`r`nConnection: close`r`n`r`nOK")
                $serverStream.Write($response, 0, $response.Length)
                $serverStream.Flush()
            }
        }
        catch {
            $observedSni = $sniHolder.Name
            $serverError = [string]$_.Exception.Message
        }

        if ($MatchingCertificate) {
            if ($null -ne $serverError) {
                return [pscustomobject]@{ Success = $false; Failure = 'ServerTlsFailure'; Error = $serverError; RequestError = if ($requestTask.IsFaulted) { [string]$requestTask.Exception } else { $null }; Sni = $observedSni }
            }
            if ($requestTask.IsFaulted) {
                return [pscustomobject]@{ Success = $false; Failure = 'RequestFailed'; Error = [string]$requestTask.Exception }
            }
            if ($requestTask.IsCanceled) {
                return [pscustomobject]@{ Success = $false; Failure = 'RequestCancelled' }
            }
            $null = $requestTask.Wait()
            $response = $requestTask.GetType().GetProperty('Result').GetValue($requestTask)
            return [pscustomobject]@{
                Success = $true
                StatusCode = [int]$response.StatusCode
                ServerDestination = $serverDestination
                Sni = $observedSni
                ProductionChainPolicyWasNull = $productionChainPolicyWasNull
                ProductionValidationCallbackWasNull = $productionValidationCallbackWasNull
            }
        }

        try {
            $null = $requestTask.Wait()
            return [pscustomobject]@{ Success = $false; UnexpectedSuccess = $true; Sni = $observedSni }
        }
        catch {
            return [pscustomobject]@{
                Success = $false
                Failure = 'TlsFailure'
                Sni = $observedSni
                ServerDestination = $serverDestination
                ServerError = $serverError
            }
        }
    }
    finally {
        if ($null -ne $serverStream) { $serverStream.Dispose() }
        if ($null -ne $accepted) { $accepted.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
        if ($null -ne $handler) { $handler.Dispose() }
        if ($null -ne $listener) { $listener.Stop() }
        if ($null -ne $requestCancellation) { $requestCancellation.Dispose() }
        if ($null -ne $chain.ServerUnsigned) { $chain.ServerUnsigned.Dispose() }
        if ($null -ne $chain.Server) { $chain.Server.Dispose() }
        if ($null -ne $chain.Root) { $chain.Root.Dispose() }
        if ($null -ne $chain.ServerKey) { $chain.ServerKey.Dispose() }
        if ($null -ne $chain.RootKey) { $chain.RootKey.Dispose() }
    }
}

try {
    Import-Module -Name $manifestPath -Force
    $script:HelperType = Get-HelperType

    switch ($Scenario) {
        'handler-policy' {
            $endpoint = New-SyntheticEndpoint
            $handler = Invoke-HandlerFactory -Endpoint $endpoint
            try {
                Write-ChildResult ([pscustomobject]@{
                    Success = $true
                    ConnectCallback = $null -ne $handler.ConnectCallback
                    UseProxy = $handler.UseProxy
                    AllowAutoRedirect = $handler.AllowAutoRedirect
                    UseCookies = $handler.UseCookies
                    AutomaticDecompression = [string]$handler.AutomaticDecompression
                    CredentialsNull = $null -eq $handler.Credentials
                    CertificateValidationCallbackNull = $null -eq $handler.SslOptions.RemoteCertificateValidationCallback
                    CertificateChainPolicyNull = $null -eq $handler.SslOptions.CertificateChainPolicy
                })
            }
            finally { $handler.Dispose() }
            break
        }

        'ordering' {
            $attempts = [System.Collections.Generic.List[string]]::new()
            $endpoint = New-SyntheticEndpoint -CandidateText @('127.0.0.2', '127.0.0.3')
            $connector = ConvertTo-Connector {
                param($candidate, $token)
                $attempts.Add([string]$candidate)
                if ([string]$candidate -eq '127.0.0.2') { throw [System.InvalidOperationException]::new('candidate failure') }
                return [System.Threading.Tasks.ValueTask[System.IO.Stream]]::new([System.IO.MemoryStream]::new())
            }
            $stream = Invoke-ConnectCore -Endpoint $endpoint -ContextHost 'transport.test.invalid' -ContextPort 443 -CancellationToken ([System.Threading.CancellationToken]::None) -ConnectionTimeout ([TimeSpan]::FromSeconds(2)) -Connector $connector
            $stream.Dispose()
            Write-ChildResult ([pscustomobject]@{ Success = $true; Attempts = @($attempts); Parallel = $false })
            break
        }

        'all-fail' {
            $attempts = [System.Collections.Generic.List[string]]::new()
            $endpoint = New-SyntheticEndpoint -CandidateText @('127.0.0.2', '127.0.0.3')
            $connector = ConvertTo-Connector {
                param($candidate, $token)
                $attempts.Add([string]$candidate)
                throw [System.InvalidOperationException]::new('candidate failure')
            }
            try {
                $null = Invoke-ConnectCore -Endpoint $endpoint -ContextHost 'transport.test.invalid' -ContextPort 443 -CancellationToken ([System.Threading.CancellationToken]::None) -ConnectionTimeout ([TimeSpan]::FromSeconds(2)) -Connector $connector
                Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true })
            }
            catch {
                $details = Get-ExceptionDetails -Exception $_.Exception
                Write-ChildResult ([pscustomobject]@{ Success = $false; Category = $details.Category; Message = $details.Message; Attempts = @($attempts) })
            }
            break
        }

        'host-mismatch' {
            $attempts = [System.Collections.Generic.List[string]]::new()
            $endpoint = New-SyntheticEndpoint
            $connector = ConvertTo-Connector {
                param($candidate, $token)
                $attempts.Add([string]$candidate)
                return [System.Threading.Tasks.ValueTask[System.IO.Stream]]::new([System.IO.MemoryStream]::new())
            }
            try {
                $null = Invoke-ConnectCore -Endpoint $endpoint -ContextHost 'wrong.test.invalid' -ContextPort 443 -CancellationToken ([System.Threading.CancellationToken]::None) -ConnectionTimeout ([TimeSpan]::FromSeconds(2)) -Connector $connector
                Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true })
            }
            catch {
                $details = Get-ExceptionDetails -Exception $_.Exception
                Write-ChildResult ([pscustomobject]@{ Success = $false; Category = $details.Category; Attempts = @($attempts) })
            }
            break
        }

        'port-mismatch' {
            $attempts = [System.Collections.Generic.List[string]]::new()
            $endpoint = New-SyntheticEndpoint
            $connector = ConvertTo-Connector {
                param($candidate, $token)
                $attempts.Add([string]$candidate)
                return [System.Threading.Tasks.ValueTask[System.IO.Stream]]::new([System.IO.MemoryStream]::new())
            }
            try {
                $null = Invoke-ConnectCore -Endpoint $endpoint -ContextHost 'transport.test.invalid' -ContextPort 8443 -CancellationToken ([System.Threading.CancellationToken]::None) -ConnectionTimeout ([TimeSpan]::FromSeconds(2)) -Connector $connector
                Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true })
            }
            catch {
                $details = Get-ExceptionDetails -Exception $_.Exception
                Write-ChildResult ([pscustomobject]@{ Success = $false; Category = $details.Category; Attempts = @($attempts) })
            }
            break
        }

        'cancelled' {
            $attempts = [System.Collections.Generic.List[string]]::new()
            $endpoint = New-SyntheticEndpoint -CandidateText @('127.0.0.2', '127.0.0.3')
            $pending = [System.Threading.Tasks.TaskCompletionSource[System.IO.Stream]]::new(
                [System.Threading.Tasks.TaskCreationOptions]::RunContinuationsAsynchronously)
            $connector = ConvertTo-Connector {
                param($candidate, $token)
                $attempts.Add([string]$candidate)
                return [System.Threading.Tasks.ValueTask[System.IO.Stream]]::new($pending.Task)
            }
            $cancellation = [System.Threading.CancellationTokenSource]::new()
            $cancellation.CancelAfter(100)
            $started = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $null = Invoke-ConnectCore -Endpoint $endpoint -ContextHost 'transport.test.invalid' -ContextPort 443 -CancellationToken $cancellation.Token -ConnectionTimeout ([TimeSpan]::FromSeconds(2)) -Connector $connector
                Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true })
            }
            catch {
                $started.Stop()
                $details = Get-ExceptionDetails -Exception $_.Exception
                Write-ChildResult ([pscustomobject]@{ Success = $false; Category = $details.Category; Attempts = @($attempts); ElapsedMilliseconds = $started.ElapsedMilliseconds })
            }
            finally { $cancellation.Dispose() }
            break
        }

        'timeout' {
            $attempts = [System.Collections.Generic.List[string]]::new()
            $endpoint = New-SyntheticEndpoint
            $pending = [System.Threading.Tasks.TaskCompletionSource[System.IO.Stream]]::new(
                [System.Threading.Tasks.TaskCreationOptions]::RunContinuationsAsynchronously)
            $connector = ConvertTo-Connector {
                param($candidate, $token)
                $attempts.Add([string]$candidate)
                return [System.Threading.Tasks.ValueTask[System.IO.Stream]]::new($pending.Task)
            }
            $started = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $null = Invoke-ConnectCore -Endpoint $endpoint -ContextHost 'transport.test.invalid' -ContextPort 443 -CancellationToken ([System.Threading.CancellationToken]::None) -ConnectionTimeout ([TimeSpan]::FromMilliseconds(150)) -Connector $connector
                Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true })
            }
            catch {
                $started.Stop()
                $details = Get-ExceptionDetails -Exception $_.Exception
                Write-ChildResult ([pscustomobject]@{ Success = $false; Category = $details.Category; Attempts = @($attempts); ElapsedMilliseconds = $started.ElapsedMilliseconds })
            }
            break
        }

        'tls-match' { Write-ChildResult (Invoke-TlsScenario -MatchingCertificate $true); break }
        'tls-mismatch' { Write-ChildResult (Invoke-TlsScenario -MatchingCertificate $false); break }

        'loopback-policy' {
            $validate = $script:HelperType.GetMethod('ValidateEndpointAsync', [System.Reflection.BindingFlags]::Static -bor [System.Reflection.BindingFlags]::Public)
            try {
                $task = $validate.Invoke($null, [object[]]@('https://127.0.0.1/', [System.Threading.CancellationToken]::None))
                $null = $task.GetAwaiter().GetResult()
                Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true })
            }
            catch {
                $details = Get-ExceptionDetails -Exception $_.Exception
                Write-ChildResult ([pscustomobject]@{ Success = $false; Category = $details.Category })
            }
            break
        }

        'production-loopback' {
            $endpoint = New-SyntheticEndpoint
            try {
                $handler = Invoke-ProductionHandlerFactory -Endpoint $endpoint
                $handler.Dispose()
                Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true })
            }
            catch {
                $details = Get-ExceptionDetails -Exception $_.Exception
                Write-ChildResult ([pscustomobject]@{ Success = $false; Category = $details.Category })
            }
            break
        }

        'public-surface' {
            $commands = @(Get-Command -Module ChannelForge | Select-Object -ExpandProperty Name)
            Write-ChildResult ([pscustomobject]@{
                Success = $true
                HasPublicFactory = $commands -contains 'CreatePinnedHandler'
                HasPublicTestConnector = $commands -contains 'ConnectPinnedForTest'
            })
            break
        }
    }
}
catch {
    $details = Get-ExceptionDetails -Exception $_.Exception
    Write-ChildResult ([pscustomobject]@{ Success = $false; Category = $details.Category; Message = $details.Message; Stack = $_.ScriptStackTrace; Position = $_.InvocationInfo.PositionMessage })
    exit 1
}
'@ | Set-Content -LiteralPath $script:ChildScriptPath -Encoding utf8

    function New-PinnedTransportConnectionModuleCopy {
        $modulePath = Join-Path $TestDrive ('ChannelForgePinnedConnection-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
        Get-ChildItem -LiteralPath $script:ModuleSourceRoot -Force | Copy-Item -Destination $modulePath -Recurse -Force
        return $modulePath
    }

    function Invoke-PinnedTransportConnectionChild {
        param(
            [Parameter(Mandatory)][string]$ModulePath,
            [Parameter(Mandatory)][string]$Scenario
        )

        $output = @(
            & $script:PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $script:ChildScriptPath -ModulePath $ModulePath -Scenario $Scenario 2>&1
        )
        $exitCode = $LASTEXITCODE
        $payload = @(
            $output |
                ForEach-Object {
                    $line = [string]$_
                    $trimmed = $line.Trim()
                    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
                        $trimmed
                    }
                }
        )
        if ($payload.Count -lt 1) {
            throw "Pinned connection child produced no parseable result. ExitCode=$exitCode Output=$($output -join ' | ')"
        }

        $parsed = $payload[$payload.Count - 1] | ConvertFrom-Json
        $parsedItems = @($parsed)
        $result = $parsedItems[$parsedItems.Count - 1]
        $result | Add-Member -NotePropertyName ExitCode -NotePropertyValue $exitCode -Force
        return $result
    }
}

Describe 'ChannelForge pinned connection foundation' {
    It 'configures a handler with the ADR 0014 safe defaults' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'handler-policy'

        $result.Success | Should -BeTrue
        $result.ConnectCallback | Should -BeTrue
        $result.UseProxy | Should -BeFalse
        $result.AllowAutoRedirect | Should -BeFalse
        $result.UseCookies | Should -BeFalse
        $result.AutomaticDecompression | Should -Be 'None'
        $result.CredentialsNull | Should -BeTrue
        $result.CertificateValidationCallbackNull | Should -BeTrue
        $result.CertificateChainPolicyNull | Should -BeTrue
    }

    It 'attempts candidates in the existing deterministic order without racing' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'ordering'

        $result.Success | Should -BeTrue
        @($result.Attempts) | Should -Be @('127.0.0.2', '127.0.0.3')
        $result.Parallel | Should -BeFalse
    }

    It 'maps all candidate failures to a stable opaque ConnectionFailure' {
        $first = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'all-fail'
        $second = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'all-fail'

        $first.Success | Should -BeFalse
        $first.Category | Should -Be 'ConnectionFailure'
        $first.Message | Should -Be 'all validated connection candidates failed.'
        $first.Message | Should -Be $second.Message
        @($first.Attempts) | Should -Be @('127.0.0.2', '127.0.0.3')
    }

    It 'rejects a mismatched connection host before invoking a connector' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'host-mismatch'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'InvalidEndpoint'
        @($result.Attempts).Count | Should -Be 0
    }

    It 'rejects a mismatched connection port before invoking a connector' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'port-mismatch'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'InvalidEndpoint'
        @($result.Attempts).Count | Should -Be 0
    }

    It 'distinguishes caller cancellation and stops further candidate attempts' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'cancelled'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'Cancelled'
        @($result.Attempts).Count | Should -Be 1
        $result.ElapsedMilliseconds | Should -BeLessThan 2000
    }

    It 'enforces one bounded internal connection deadline' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'timeout'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'Timeout'
        $result.ElapsedMilliseconds | Should -BeGreaterThan 50
        $result.ElapsedMilliseconds | Should -BeLessThan 2000
    }

    It 'connects to the injected candidate and preserves the canonical TLS host/SNI' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'tls-match'

        $result.Success | Should -BeTrue -Because ($result | ConvertTo-Json -Compress)
        $result.StatusCode | Should -Be 200
        $result.ServerDestination | Should -Be '127.0.0.2'
        $result.Sni | Should -Be 'transport.test.invalid'
        $result.ProductionChainPolicyWasNull | Should -BeTrue
        $result.ProductionValidationCallbackWasNull | Should -BeTrue
    }

    It 'fails TLS when the certificate hostname does not match the canonical host' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'tls-mismatch'

        $result.Success | Should -BeFalse -Because ($result | ConvertTo-Json -Compress)
        $result.UnexpectedSuccess | Should -BeNullOrEmpty
        $result.Failure | Should -Be 'TlsFailure' -Because ($result | ConvertTo-Json -Compress)
        $result.Sni | Should -Be 'transport.test.invalid'
        $result.ServerDestination | Should -Be '127.0.0.2'
    }

    It 'keeps production destination policy separate from the loopback test seam' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'loopback-policy'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'BlockedDestination'
    }

    It 'rejects loopback candidates in the production handler factory' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'production-loopback'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'BlockedDestination'
    }

    It 'does not expose the internal factory or connector through module commands' {
        $result = Invoke-PinnedTransportConnectionChild -ModulePath (New-PinnedTransportConnectionModuleCopy) -Scenario 'public-surface'

        $result.Success | Should -BeTrue
        $result.HasPublicFactory | Should -BeFalse
        $result.HasPublicTestConnector | Should -BeFalse
    }

    It 'does not add a production HTTP request or response-processing API' {
        $sourceText = Get-Content -Raw -LiteralPath (Join-Path $script:ModuleSourceRoot 'Private\Transport\ChannelForgePinnedHttpTransport.cs')

        $sourceText | Should -Match '(?i)SocketsHttpHandler'
        $sourceText | Should -Match '(?i)ConnectCallback'
        $sourceText | Should -Match '(?i)NetworkStream'
        $sourceText | Should -Not -Match '(?i)new\s+HttpClient|\.GetAsync|\.SendAsync|HttpRequestMessage\s+\w+|HttpResponseMessage\s+\w+|ReadAs|ResponseHeaders'
    }
}
