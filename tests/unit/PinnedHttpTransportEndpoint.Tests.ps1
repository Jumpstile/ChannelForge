BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    $script:ModuleSourceRoot = Join-Path $RepoRoot 'src\ChannelForge'
    $script:PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'

    if (-not (Test-Path -LiteralPath $script:PowerShellExecutable -PathType Leaf)) {
        $script:PowerShellExecutable = (Get-Command pwsh -ErrorAction Stop).Source
    }

    $script:ChildScriptPath = Join-Path $TestDrive 'Invoke-PinnedHttpTransportEndpointChild.ps1'
    @'
param(
    [Parameter(Mandatory)]
    [string]$ModulePath,

    [Parameter(Mandatory)]
    [string]$Endpoint,

    [Parameter()]
    [string]$AddressesJson = '[]',

    [Parameter()]
    [ValidateSet('return', 'throw', 'null')]
    [string]$ResolverMode = 'return',

    [Parameter()]
    [ValidateSet('resolver', 'cancelled')]
    [string]$Scenario = 'resolver'
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $ModulePath 'ChannelForge.psd1'
$helperTypeName = 'ChannelForge.Private.Transport.ChannelForgePinnedHttpTransport'

function Write-ChildResult {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    $Value | ConvertTo-Json -Compress -Depth 8
}

function Get-ExceptionDetails {
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

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
    elseif ($null -ne $exception.Data) {
        $category = [string]$exception.Data['ChannelForgeFailureCategory']
    }

    return [pscustomobject]@{
        Category = $category
        Message = [string]$exception.Message
    }
}

try {
    Import-Module -Name $manifestPath -Force
    $module = Get-Module -Name ChannelForge
    $initialization = & $module { Initialize-ChannelForgePinnedHttpTransport }
    $helperType = $initialization.Type

    if ($Scenario -eq 'cancelled') {
        $method = $helperType.GetMethod(
            'ValidateEndpointAsync',
            [System.Reflection.BindingFlags]::Public -bor
                [System.Reflection.BindingFlags]::Static)
        $cancellation = [System.Threading.CancellationTokenSource]::new()
        $cancellation.Cancel()

        try {
            $task = $method.Invoke($null, [object[]]@($Endpoint, $cancellation.Token))
            $null = $task.GetAwaiter().GetResult()
            Write-ChildResult ([pscustomobject]@{
                Success = $false
                UnexpectedSuccess = $true
                ResolverCalls = 0
            })
        }
        catch {
            $details = Get-ExceptionDetails -Exception $_.Exception
            Write-ChildResult ([pscustomobject]@{
                Success = $false
                Category = $details.Category
                Message = $details.Message
                ResolverCalls = 0
            })
        }

        return
    }

    $method = $helperType.GetMethod(
        'ValidateEndpointWithResolver',
        [System.Reflection.BindingFlags]::NonPublic -bor
            [System.Reflection.BindingFlags]::Static)
    $addressValues = @($AddressesJson | ConvertFrom-Json)
    $addresses = [System.Collections.Generic.List[System.Net.IPAddress]]::new()
    foreach ($addressValue in $addressValues) {
        if ($null -ne $addressValue) {
            $addresses.Add([System.Net.IPAddress]::Parse([string]$addressValue))
        }
    }

    $addressArray = $addresses.ToArray()
    $script:ResolverCalls = 0
    $resolver = [System.Func[string, System.Net.IPAddress[]]]{
        param([string]$HostName)

        $script:ResolverCalls++
        if ($ResolverMode -eq 'throw') {
            throw 'resolver failure for secret.example.invalid'
        }

        if ($ResolverMode -eq 'null') {
            return $null
        }

        return $addressArray
    }

    try {
        $validated = $method.Invoke($null, [object[]]@($Endpoint, $resolver))
        Write-ChildResult ([pscustomobject]@{
            Success = $true
            Category = $null
            Message = $null
            ResolverCalls = $script:ResolverCalls
            TlsHostName = $validated.TlsHostName
            RequestUri = $validated.RequestUri.AbsoluteUri
            Port = $validated.Port
            IsLiteralAddress = $validated.IsLiteralAddress
            Candidates = @($validated.Candidates | ForEach-Object { $_.ToString() })
        })
    }
    catch {
        $details = Get-ExceptionDetails -Exception $_.Exception
        Write-ChildResult ([pscustomobject]@{
            Success = $false
            Category = $details.Category
            Message = $details.Message
            ResolverCalls = $script:ResolverCalls
        })
    }
}
catch {
    $details = Get-ExceptionDetails -Exception $_.Exception
    Write-ChildResult ([pscustomobject]@{
        Success = $false
        Category = $details.Category
        Message = $details.Message
    })
}
'@ | Set-Content -LiteralPath $script:ChildScriptPath -Encoding utf8

    function New-PinnedTransportEndpointTestModuleCopy {
        $modulePath = Join-Path $TestDrive ('ChannelForgePinnedTransportEndpoint-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
        Get-ChildItem -LiteralPath $script:ModuleSourceRoot -Force | Copy-Item -Destination $modulePath -Recurse -Force
        return $modulePath
    }

    function Invoke-PinnedTransportEndpointChild {
        param(
            [Parameter(Mandatory)]
            [string]$Endpoint,

            [Parameter()]
            [string[]]$Addresses = @(),

            [Parameter()]
            [ValidateSet('return', 'throw', 'null')]
            [string]$ResolverMode = 'return',

            [Parameter()]
            [ValidateSet('resolver', 'cancelled')]
            [string]$Scenario = 'resolver'
        )

        $modulePath = New-PinnedTransportEndpointTestModuleCopy
        $addressesJson = '[]'
        if (@($Addresses).Count -gt 0) {
            $addressesJson = @($Addresses) | ConvertTo-Json -Compress
        }

        $output = @(& $script:PowerShellExecutable -NoLogo -NoProfile -NonInteractive -File $script:ChildScriptPath -ModulePath $modulePath -Endpoint $Endpoint -AddressesJson $addressesJson -ResolverMode $ResolverMode -Scenario $Scenario 2>&1)
        $exitCode = $LASTEXITCODE
        $json = @($output | ForEach-Object { [string]$_ } | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)

        if ($json.Count -ne 1) {
            throw "Pinned transport endpoint child produced no parseable result. ExitCode=$exitCode Output=$($output -join ' | ')"
        }

        $result = $json[0] | ConvertFrom-Json
        $result | Add-Member -NotePropertyName ExitCode -NotePropertyValue $exitCode -Force
        return $result
    }

    function Get-CandidateText {
        param(
            [Parameter(Mandatory)]
            [object]$Result
        )

        return (@($Result.Candidates) -join '|')
    }
}

Describe 'ChannelForge pinned transport endpoint validation' {
    It 'accepts HTTPS with the implicit default port 443' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://8.8.8.8' -Addresses @()

        $result.Success | Should -BeTrue
        $result.Port | Should -Be 443
        $result.IsLiteralAddress | Should -BeTrue
        $result.ResolverCalls | Should -Be 0
        $result.Candidates | Should -Be '8.8.8.8'
    }

    It 'accepts HTTPS with explicit port 443' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://8.8.4.4:443/path' -Addresses @()

        $result.Success | Should -BeTrue
        $result.Port | Should -Be 443
        $result.Candidates | Should -Be '8.8.4.4'
    }

    It 'rejects HTTP endpoints' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'http://8.8.8.8:443' -Addresses @()

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'InvalidEndpoint'
    }

    It 'rejects non-443 endpoints' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://8.8.8.8:8443' -Addresses @()

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'InvalidEndpoint'
    }

    It 'rejects URI user information' {
        # Construct explicit synthetic userinfo at runtime; no credential-shaped URL is tracked.
        $syntheticUri = [System.UriBuilder]::new('https', 'example.invalid', 443)
        $syntheticUri.UserName = 'fixture-user'
        $syntheticUri.Password = 'fixture-password'
        $result = Invoke-PinnedTransportEndpointChild -Endpoint $syntheticUri.Uri.AbsoluteUri -Addresses @()

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'InvalidEndpoint'
        $result.Message | Should -Not -Match 'password'
    }

    It 'rejects malformed or non-absolute endpoints and malformed host names' {
        foreach ($endpoint in @('not-an-absolute-uri', 'https://[::1', 'https://bad host.example:443')) {
            $result = Invoke-PinnedTransportEndpointChild -Endpoint $endpoint -Addresses @()

            $result.Success | Should -BeFalse
            $result.Category | Should -Be 'InvalidEndpoint'
        }
    }

    It 'rejects localhost before DNS resolution' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://localhost:443' -Addresses @('8.8.8.8')

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'InvalidEndpoint'
        $result.ResolverCalls | Should -Be 0
    }

    It 'rejects scoped IPv6 endpoint hosts' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://[fe80::1%25eth0]:443' -Addresses @()

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'InvalidEndpoint'
    }

    It 'canonicalizes IDN host names with Uri.IdnHost' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://bücher.example:443/guide' -Addresses @('8.8.8.8')

        $result.Success | Should -BeTrue
        $result.ResolverCalls | Should -Be 1
        $result.TlsHostName | Should -Be 'xn--bcher-kva.example'
        $result.RequestUri | Should -Match 'https://'
    }

    It 'accepts a public literal IPv4 address' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://8.8.8.8:443' -Addresses @()

        $result.Success | Should -BeTrue
        $result.Candidates | Should -Be '8.8.8.8'
    }

    It 'rejects every reviewed IPv4 deny range' {
        $cases = [ordered]@{
            '0.0.0.0/8' = '0.0.0.1'
            '10.0.0.0/8' = '10.1.2.3'
            '100.64.0.0/10' = '100.64.0.1'
            '127.0.0.0/8' = '127.0.0.1'
            '169.254.0.0/16' = '169.254.1.1'
            '172.16.0.0/12' = '172.16.0.1'
            '192.0.0.0/24' = '192.0.0.1'
            '192.0.2.0/24' = '192.0.2.1'
            '192.31.196.0/24' = '192.31.196.1'
            '192.52.193.0/24' = '192.52.193.1'
            '192.88.99.0/24' = '192.88.99.1'
            '192.168.0.0/16' = '192.168.1.1'
            '192.175.48.0/24' = '192.175.48.1'
            '198.18.0.0/15' = '198.18.0.1'
            '198.51.100.0/24' = '198.51.100.1'
            '203.0.113.0/24' = '203.0.113.1'
            '224.0.0.0/4' = '224.0.0.1'
            '240.0.0.0/4' = '240.0.0.1'
        }

        foreach ($name in $cases.Keys) {
            $result = Invoke-PinnedTransportEndpointChild -Endpoint ('https://{0}:443' -f $cases[$name]) -Addresses @()

            $result.Success | Should -BeFalse
            $result.Category | Should -Be 'BlockedDestination'
        }
    }

    It 'accepts a public literal IPv6 address' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://[2001:4860:4860::8888]:443' -Addresses @()

        $result.Success | Should -BeTrue
        $result.Candidates | Should -Be '2001:4860:4860::8888'
    }

    It 'rejects every reviewed IPv6 deny range' {
        $cases = [ordered]@{
            '::/128' = '::'
            '::1/128' = '::1'
            '64:ff9b::/96' = '64:ff9b::1'
            '64:ff9b:1::/48' = '64:ff9b:1::1'
            '100::/64' = '100::1'
            '100:0:0:1::/64' = '100:0:0:1::1'
            '2001::/23' = '2001::1'
            '2001:db8::/32' = '2001:db8::1'
            '2002::/16' = '2002::1'
            '2620:4f:8000::/48' = '2620:4f:8000::1'
            '3fff::/20' = '3fff::1'
            '5f00::/16' = '5f00::1'
            'fc00::/7' = 'fc00::1'
            'fe80::/10' = 'fe80::1'
            'fec0::/10' = 'fec0::1'
            'ff00::/8' = 'ff00::1'
            '3ffe::/16' = '3ffe::1'
        }

        foreach ($name in $cases.Keys) {
            $result = Invoke-PinnedTransportEndpointChild -Endpoint ('https://[{0}]:443' -f $cases[$name]) -Addresses @()

            $result.Success | Should -BeFalse
            $result.Category | Should -Be 'BlockedDestination'
        }
    }

    It 'rejects IPv6 addresses outside 2000::/3' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://[1000::1]:443' -Addresses @()

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'BlockedDestination'
    }

    It 'normalizes and accepts a mapped public IPv4 address' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://[::ffff:8.8.8.8]:443' -Addresses @()

        $result.Success | Should -BeTrue
        $result.Candidates | Should -Be '8.8.8.8'
    }

    It 'rejects a mapped private IPv4 address' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://[::ffff:10.0.0.1]:443' -Addresses @()

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'BlockedDestination'
    }

    It 'resolves a DNS host exactly once through the approved seam' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('8.8.8.8')

        $result.Success | Should -BeTrue
        $result.ResolverCalls | Should -Be 1
        $result.TlsHostName | Should -Be 'example.com'
    }

    It 'maps resolver exceptions to DnsFailure without leaking details' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://secret.example.invalid:443' -Addresses @('8.8.8.8') -ResolverMode 'throw'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'DnsFailure'
        $result.Message | Should -Not -Match 'secret.example.invalid|https://|resolver failure'
    }

    It 'maps null resolver results to DnsFailure' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('8.8.8.8') -ResolverMode 'null'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'DnsFailure'
    }

    It 'maps empty resolver results to DnsFailure' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @()

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'DnsFailure'
    }

    It 'accepts an all-safe DNS result after validating every candidate' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('8.8.8.8', '2001:4860:4860::8888')

        $result.Success | Should -BeTrue
        $result.ResolverCalls | Should -Be 1
        Get-CandidateText -Result $result | Should -Be '2001:4860:4860::8888|8.8.8.8'
    }

    It 'rejects a mixed safe and unsafe DNS result as a whole' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('8.8.8.8', '192.168.1.1')

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'BlockedDestination'
    }

    It 'rejects a blocked duplicate before deduplication' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('192.168.1.1', '192.168.1.1')

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'BlockedDestination'
    }

    It 'deduplicates safe addresses' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('8.8.8.8', '8.8.8.8', '2001:4860:4860::8888')

        $result.Success | Should -BeTrue
        @($result.Candidates).Count | Should -Be 2
    }

    It 'collapses mapped and ordinary IPv4 duplicates' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('8.8.8.8', '::ffff:8.8.8.8')

        $result.Success | Should -BeTrue
        @($result.Candidates).Count | Should -Be 1
        $result.Candidates | Should -Be '8.8.8.8'
    }

    It 'produces identical candidates for DNS answer permutations' {
        $first = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('8.8.8.8', '2001:4860:4860::8888', '1.1.1.1')
        $second = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('1.1.1.1', '2001:4860:4860::8888', '8.8.8.8')

        Get-CandidateText -Result $first | Should -Be (Get-CandidateText -Result $second)
    }

    It 'orders IPv6 before IPv4 and sorts bytes within each family' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Addresses @('8.8.8.8', '1.1.1.1', '2001:4860:4860::8888', '2001:4860:4860::8844')

        $result.Success | Should -BeTrue
        Get-CandidateText -Result $result | Should -Be '2001:4860:4860::8844|2001:4860:4860::8888|1.1.1.1|8.8.8.8'
    }

    It 'maps cancelled production DNS resolution to the stable Cancelled category' {
        $result = Invoke-PinnedTransportEndpointChild -Endpoint 'https://example.com:443' -Scenario 'cancelled'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'Cancelled'
    }
}
