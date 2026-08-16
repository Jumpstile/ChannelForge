BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    $script:ModuleSourceRoot = Join-Path $RepoRoot 'src\ChannelForge'
    $script:HelperSourcePath = Join-Path $script:ModuleSourceRoot 'Private\Transport\ChannelForgePinnedHttpTransport.cs'
    $script:LoaderSourcePath = Join-Path $script:ModuleSourceRoot 'Private\Initialize-ChannelForgePinnedHttpTransport.ps1'
    $script:PowerShellExecutable = Join-Path $PSHOME 'pwsh.exe'

    if (-not (Test-Path -LiteralPath $script:PowerShellExecutable -PathType Leaf)) {
        $script:PowerShellExecutable = (Get-Command pwsh -ErrorAction Stop).Source
    }

    $script:ChildScriptPath = Join-Path $TestDrive 'Invoke-PinnedHttpTransportLoaderChild.ps1'
    @'
param(
    [Parameter(Mandatory)]
    [string]$ModulePath,

    [Parameter(Mandatory)]
    [ValidateSet('import-only', 'compile', 'reimport', 'preloaded-matching', 'conflicting', 'shape-mismatch', 'multiple', 'initialize')]
    [string]$Scenario
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $ModulePath 'ChannelForge.psd1'
$helperTypeName = 'ChannelForge.Private.Transport.ChannelForgePinnedHttpTransport'

function Get-HelperTypes {
    $types = [System.Collections.Generic.List[System.Type]]::new()
    foreach ($assembly in @([System.AppDomain]::CurrentDomain.GetAssemblies())) {
        $type = $assembly.GetType($helperTypeName, $false, $false)
        if ($null -ne $type) {
            $types.Add($type)
        }
    }

    return @($types)
}

function Invoke-Initializer {
    $module = Get-Module -Name ChannelForge
    return (& $module { Initialize-ChannelForgePinnedHttpTransport })
}

function New-DynamicHelperType {
    param(
        [Parameter(Mandatory)]
        [int]$Version
    )

    $assemblyName = [System.Reflection.AssemblyName]::new(
        'ChannelForgePinnedTransportTest' + [guid]::NewGuid().ToString('N'))
    $assemblyBuilder = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
        $assemblyName,
        [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
    $moduleBuilder = $assemblyBuilder.DefineDynamicModule($assemblyName.Name)
    $typeBuilder = $moduleBuilder.DefineType(
        $helperTypeName,
        [System.Reflection.TypeAttributes]::Public -bor
            [System.Reflection.TypeAttributes]::Class -bor
            [System.Reflection.TypeAttributes]::Abstract -bor
            [System.Reflection.TypeAttributes]::Sealed)

    $nameField = $typeBuilder.DefineField(
        'ContractName',
        [string],
        [System.Reflection.FieldAttributes]::Public -bor
            [System.Reflection.FieldAttributes]::Static -bor
            [System.Reflection.FieldAttributes]::Literal)
    $nameField.SetConstant('ChannelForgePinnedHttpTransport')

    $versionField = $typeBuilder.DefineField(
        'ContractVersion',
        [int],
        [System.Reflection.FieldAttributes]::Public -bor
            [System.Reflection.FieldAttributes]::Static -bor
            [System.Reflection.FieldAttributes]::Literal)
    $versionField.SetConstant($Version)

    $methodBuilder = $typeBuilder.DefineMethod(
        'HasRequiredCapabilities',
        [System.Reflection.MethodAttributes]::Public -bor
            [System.Reflection.MethodAttributes]::Static,
        [bool],
        [Type[]]@())
    $il = $methodBuilder.GetILGenerator()
    $il.Emit([System.Reflection.Emit.OpCodes]::Ldc_I4_1)
    $il.Emit([System.Reflection.Emit.OpCodes]::Ret)

    return $typeBuilder.CreateType()
}

function Write-ChildResult {
    param(
        [Parameter(Mandatory)]
        [object]$Value
    )

    $Value | ConvertTo-Json -Compress -Depth 8
}

try {
    Import-Module -Name $manifestPath -Force

    switch ($Scenario) {
        'import-only' {
            Write-ChildResult ([pscustomobject]@{
                Success = $true
                HelperCount = @(Get-HelperTypes).Count
            })
            break
        }

        'compile' {
            $first = Invoke-Initializer
            $firstCount = @(Get-HelperTypes).Count
            $second = Invoke-Initializer
            $secondCount = @(Get-HelperTypes).Count

            Write-ChildResult ([pscustomobject]@{
                Success = $true
                FirstMode = $first.LoadMode
                SecondMode = $second.LoadMode
                TypeName = $first.Type.FullName
                ContractVersion = $first.ContractVersion
                Capability = [bool](@($first.Type.GetMethods() | Where-Object { $_.Name -eq 'HasRequiredCapabilities' -and $_.GetParameters().Count -eq 0 })[0].Invoke($null, [object[]]@()))
                FirstHelperCount = $firstCount
                SecondHelperCount = $secondCount
                CompilerWarnings = @($first.CompilerWarnings)
            })
            break
        }

        'reimport' {
            $first = Invoke-Initializer
            Remove-Module -Name ChannelForge -Force
            Import-Module -Name $manifestPath -Force
            $second = Invoke-Initializer

            Write-ChildResult ([pscustomobject]@{
                Success = $true
                FirstMode = $first.LoadMode
                SecondMode = $second.LoadMode
                ContractVersion = $second.ContractVersion
                HelperCount = @(Get-HelperTypes).Count
            })
            break
        }

        'preloaded-matching' {
            $sourcePath = Join-Path $ModulePath 'Private\Transport\ChannelForgePinnedHttpTransport.cs'
            $source = Get-Content -Raw -LiteralPath $sourcePath
            $null = @(Add-Type -TypeDefinition $source -Language CSharp -PassThru)
            $result = Invoke-Initializer

            Write-ChildResult ([pscustomobject]@{
                Success = $true
                Mode = $result.LoadMode
                TypeName = $result.Type.FullName
                ContractVersion = $result.ContractVersion
                HelperCount = @(Get-HelperTypes).Count
            })
            break
        }

        'conflicting' {
            $source = @"
namespace ChannelForge.Private.Transport {
    public static class ChannelForgePinnedHttpTransport {
        public const string ContractName = "ChannelForgePinnedHttpTransport";
        public const int ContractVersion = 1;
        public static bool HasRequiredCapabilities() { return true; }
    }
}
"@
            $null = @(Add-Type -TypeDefinition $source -Language CSharp -PassThru)
            $result = Invoke-Initializer

            Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true; Mode = $result.LoadMode })
            break
        }

        'shape-mismatch' {
            $source = @"
namespace ChannelForge.Private.Transport {
    public static class ChannelForgePinnedHttpTransport {
        public const string ContractName = "ChannelForgePinnedHttpTransport";
        public const int ContractVersion = 2;
        public static bool HasRequiredCapabilities() { return true; }
    }
}
"@
            $null = @(Add-Type -TypeDefinition $source -Language CSharp -PassThru)
            $result = Invoke-Initializer

            Write-ChildResult ([pscustomobject]@{ Success = $false; UnexpectedSuccess = $true; Mode = $result.LoadMode })
            break
        }

        'multiple' {
            try {
                $null = New-DynamicHelperType -Version 1
                $null = New-DynamicHelperType -Version 1
                $result = Invoke-Initializer
                Write-ChildResult ([pscustomobject]@{ Success = $false; Reproducible = $true; UnexpectedSuccess = $true })
            }
            catch {
                $category = $null
                if ($null -ne $_.Exception.Data) {
                    $category = $_.Exception.Data['ChannelForgeFailureCategory']
                }

                Write-ChildResult ([pscustomobject]@{
                    Success = $false
                    Reproducible = $true
                    Category = $category
                    Message = $_.Exception.Message
                })
            }
            break
        }

        default {
            $result = Invoke-Initializer
            Write-ChildResult ([pscustomobject]@{
                Success = $true
                Mode = $result.LoadMode
                TypeName = $result.Type.FullName
                ContractVersion = $result.ContractVersion
            })
            break
        }
    }
}
catch {
    $category = $null
    if ($null -ne $_.Exception.Data) {
        $category = $_.Exception.Data['ChannelForgeFailureCategory']
    }

    Write-ChildResult ([pscustomobject]@{
        Success = $false
        Category = $category
        Message = $_.Exception.Message
        FullyQualifiedErrorId = $_.FullyQualifiedErrorId
    })
}
'@ | Set-Content -LiteralPath $script:ChildScriptPath -Encoding utf8

    Import-Module -Name $script:ManifestPath -Force

    function New-PinnedTransportTestModuleCopy {
        $modulePath = Join-Path $TestDrive ('ChannelForgePinnedTransport-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
        Get-ChildItem -LiteralPath $script:ModuleSourceRoot -Force | Copy-Item -Destination $modulePath -Recurse -Force
        return $modulePath
    }

    function Invoke-PinnedTransportChild {
        param(
            [Parameter(Mandatory)]
            [string]$ModulePath,

            [Parameter(Mandatory)]
            [ValidateSet('import-only', 'compile', 'reimport', 'preloaded-matching', 'conflicting', 'shape-mismatch', 'multiple', 'initialize')]
            [string]$Scenario
        )

        $output = @(
            & $script:PowerShellExecutable `
                -NoLogo `
                -NoProfile `
                -NonInteractive `
                -File $script:ChildScriptPath `
                -ModulePath $ModulePath `
                -Scenario $Scenario `
                2>&1
        )
        $exitCode = $LASTEXITCODE
        $json = @(
            $output |
                ForEach-Object { [string]$_ } |
                Where-Object { $_.TrimStart().StartsWith('{') } |
                Select-Object -Last 1
        )

        if ($json.Count -ne 1) {
            throw "Pinned transport child produced no parseable result. ExitCode=$exitCode Output=$($output -join ' | ')"
        }

        $result = $json[0] | ConvertFrom-Json
        $result | Add-Member -NotePropertyName ExitCode -NotePropertyValue $exitCode -Force
        return $result
    }
}

function New-PinnedTransportTestModuleCopy {
    $modulePath = Join-Path $TestDrive ('ChannelForgePinnedTransport-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
    Get-ChildItem -LiteralPath $script:ModuleSourceRoot -Force | Copy-Item -Destination $modulePath -Recurse -Force
    return $modulePath
}

function Invoke-PinnedTransportChild {
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [ValidateSet('import-only', 'compile', 'reimport', 'preloaded-matching', 'conflicting', 'shape-mismatch', 'multiple', 'initialize')]
        [string]$Scenario
    )

    $output = @(
        & $script:PowerShellExecutable `
            -NoLogo `
            -NoProfile `
            -NonInteractive `
            -File $script:ChildScriptPath `
            -ModulePath $ModulePath `
            -Scenario $Scenario `
            2>&1
    )
    $exitCode = $LASTEXITCODE
    $json = @(
        $output |
            ForEach-Object { [string]$_ } |
            Where-Object { $_.TrimStart().StartsWith('{') } |
            Select-Object -Last 1
    )

    if ($json.Count -ne 1) {
        throw "Pinned transport child produced no parseable result. ExitCode=$exitCode Output=$($output -join ' | ')"
    }

    $result = $json[0] | ConvertFrom-Json
    $result | Add-Member -NotePropertyName ExitCode -NotePropertyValue $exitCode -Force
    return $result
}

Describe 'ChannelForge pinned transport lazy-loader foundation' {
    It 'does not load or compile the helper during ordinary module import' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'import-only'

        $result.Success | Should -BeTrue
        $result.HelperCount | Should -Be 0
        $result.ExitCode | Should -Be 0
    }

    It 'keeps the tracked helper source at a strict UTF-8 regular file' {
        $bytes = [System.IO.File]::ReadAllBytes($script:HelperSourcePath)
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)

        { $null = $utf8.GetString($bytes) } | Should -Not -Throw
        (Get-Item -LiteralPath $script:HelperSourcePath).PSIsContainer | Should -BeFalse
        ((Get-Item -LiteralPath $script:HelperSourcePath).Attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should -Be 0
    }

    It 'compiles the helper on first initialization and reuses it without recompiling' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'compile'

        $result.Success | Should -BeTrue
        $result.FirstMode | Should -Be 'Compiled'
        $result.SecondMode | Should -Be 'Reused'
        $result.TypeName | Should -Be 'ChannelForge.Private.Transport.ChannelForgePinnedHttpTransport'
        $result.ContractVersion | Should -Be 2
        $result.Capability | Should -BeTrue
        $result.FirstHelperCount | Should -Be 1
        $result.SecondHelperCount | Should -Be 1
        @($result.CompilerWarnings) | Should -Not -Contain 'no compiler diagnostics were returned.'
        $result.ExitCode | Should -Be 0
    }

    It 'reuses the loaded helper after module reimport' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'reimport'

        $result.Success | Should -BeTrue
        $result.FirstMode | Should -Be 'Compiled'
        $result.SecondMode | Should -Be 'Reused'
        $result.ContractVersion | Should -Be 2
        $result.HelperCount | Should -Be 1
    }

    It 'reuses an already-loaded matching v2 helper' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'preloaded-matching'

        $result.Success | Should -BeTrue
        $result.Mode | Should -Be 'Reused'
        $result.TypeName | Should -Be 'ChannelForge.Private.Transport.ChannelForgePinnedHttpTransport'
        $result.ContractVersion | Should -Be 2
        $result.HelperCount | Should -Be 1
    }

    It 'fails closed when a conflicting helper contract version is already loaded' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'conflicting'

        $result.Success | Should -BeFalse
        $result.UnexpectedSuccess | Should -BeNullOrEmpty
        $result.Category | Should -Be 'ConflictingContract'
        $result.Message | Should -Match 'ConflictingContract'
    }

    It 'fails closed when a v2 helper has a mismatched endpoint contract shape' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'shape-mismatch'

        $result.Success | Should -BeFalse
        $result.UnexpectedSuccess | Should -BeNullOrEmpty
        $result.Category | Should -Be 'ContractMismatch'
        $result.Message | Should -Match 'ContractMismatch'
    }

    It 'fails closed on multiple loaded definitions when that state is reproducible' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'multiple'

        if (-not $result.Reproducible) {
            Set-ItResult -Skipped -Because 'the runtime did not permit two dynamic assemblies with the exact helper type name.'
            return
        }

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'ConflictingContract'
    }

    It 'fails closed with SourceMissing when the fixed source is absent' {
        $modulePath = New-PinnedTransportTestModuleCopy
        Remove-Item -LiteralPath (Join-Path $modulePath 'Private\Transport\ChannelForgePinnedHttpTransport.cs') -Force
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'initialize'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'SourceMissing'
    }

    It 'fails closed with CompilationFailed and surfaces compiler diagnostics for malformed source' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $sourcePath = Join-Path $modulePath 'Private\Transport\ChannelForgePinnedHttpTransport.cs'
        'namespace ChannelForge.Private.Transport { public static class {' | Set-Content -LiteralPath $sourcePath -Encoding utf8
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'initialize'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'CompilationFailed'
        $result.Message | Should -Match '(?i)(CS\d+|compiler|error)'
    }

    It 'fails closed with InvalidSourceEncoding for invalid UTF-8 source bytes' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $sourcePath = Join-Path $modulePath 'Private\Transport\ChannelForgePinnedHttpTransport.cs'
        [System.IO.File]::WriteAllBytes($sourcePath, [byte[]](0xC3, 0x28))
        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'initialize'

        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'InvalidSourceEncoding'
    }

    It 'fails closed when the fixed source is a reparse point where the runtime permits the test' {
        $modulePath = New-PinnedTransportTestModuleCopy
        $sourcePath = Join-Path $modulePath 'Private\Transport\ChannelForgePinnedHttpTransport.cs'
        $targetPath = Join-Path $TestDrive ('PinnedTransportTarget-' + [guid]::NewGuid().ToString('N') + '.cs')
        Copy-Item -LiteralPath $script:HelperSourcePath -Destination $targetPath -Force
        Remove-Item -LiteralPath $sourcePath -Force

        try {
            New-Item -ItemType SymbolicLink -Path $sourcePath -Target $targetPath -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'the current Windows runtime does not permit creating a test symbolic link.'
            return
        }

        $result = Invoke-PinnedTransportChild -ModulePath $modulePath -Scenario 'initialize'
        $result.Success | Should -BeFalse
        $result.Category | Should -Be 'SourceIntegrityFailure'
    }

    It 'fails before compilation when the runtime capability seam reports unsupported' {
        InModuleScope ChannelForge {
            Mock Test-ChannelForgePinnedHttpTransportRuntimeCapability { return $false }
            Mock Add-Type { throw 'Add-Type must not be called for an unsupported runtime.' }

            { Initialize-ChannelForgePinnedHttpTransport } | Should -Throw '*RuntimeUnsupported*'
            Should -Invoke Add-Type -Times 0 -Scope It
        }
    }

    It 'surfaces compiler warnings without turning a successful compilation into a failure' {
        InModuleScope ChannelForge {
            $script:loaderLookupCount = 0
            Mock Test-ChannelForgePinnedHttpTransportRuntimeCapability { return $true }
            Mock Get-ChannelForgePinnedHttpTransportSource {
                [pscustomobject]@{ Path = '<module-source>'; Text = 'test source' }
            }
            Mock Add-Type { Write-Warning 'simulated compiler warning' }
            Mock Get-ChannelForgePinnedHttpTransportLoadedType {
                $script:loaderLookupCount++
                if ($script:loaderLookupCount -eq 1) {
                    return @()
                }

                return @([string])
            }
            Mock Get-ChannelForgePinnedHttpTransportContractState {
                [pscustomobject]@{
                    Valid = $true
                    Category = $null
                    Detail = $null
                    ContractVersion = 2
                    CapabilityMethod = [string].GetMethod('IsNullOrEmpty', [Type[]]@([string]))
                }
            }
            Mock Test-ChannelForgePinnedHttpTransportLoadedCapability { return $true }

            $capturedWarnings = @()
            $result = Initialize-ChannelForgePinnedHttpTransport -WarningVariable capturedWarnings

            $result.LoadMode | Should -Be 'Compiled'
            @($capturedWarnings).Count | Should -BeGreaterThan 0
            Should -Invoke Add-Type -Times 1 -Scope It
        }
    }

    It 'exposes no caller-controlled source/path/code surface or external acquisition mechanism' {
        $loaderText = Get-Content -Raw -LiteralPath $script:LoaderSourcePath
        $sourceText = Get-Content -Raw -LiteralPath $script:HelperSourcePath

        InModuleScope ChannelForge {
            (Get-Command Initialize-ChannelForgePinnedHttpTransport).Parameters.Keys |
                Should -Not -Contain 'Path'
            (Get-Command Initialize-ChannelForgePinnedHttpTransport).Parameters.Keys |
                Should -Not -Contain 'Source'
            (Get-Command Initialize-ChannelForgePinnedHttpTransport).Parameters.Keys |
                Should -Not -Contain 'Code'
            (Get-Command Initialize-ChannelForgePinnedHttpTransport).Parameters.Keys |
                Should -Not -Contain 'TypeDefinition'
        }

        $loaderText | Should -Not -Match '-ReferencedAssemblies'
        $loaderText | Should -Not -Match '-OutputAssembly'
        $loaderText | Should -Not -Match '-IgnoreWarnings'
        $loaderText | Should -Not -Match '-CompilerOptions'
        $loaderText | Should -Not -Match '(?i)Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|Install-Module|Install-Package|PackageManagement|HttpClient|Dns\.Get|System\.Net\.Sockets'
        $sourceText | Should -Not -Match '(?i)new\s+SocketsHttpHandler|HttpClient|Socket\.Connect|Socket\.ConnectAsync|TcpClient|NetworkStream|ConnectAsync|GetStream|HttpRequest|ResponseMessage|SendAsync|GetAsync'
    }

    It 'leaves local M3U and XMLTV functionality unaffected' {
        $m3uPath = Join-Path $RepoRoot 'tests\fixtures\tiny.m3u'
        $xmltvPath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'

        $channels = @(Import-ChannelForgeM3UPlaylist -Path $m3uPath -Provider 'transport-foundation-test' -Playlist 'tiny')
        $programmes = @(Import-ChannelForgeXmltvSource -Path $xmltvPath -SourceId 'transport-foundation-test')

        $channels.Count | Should -Be 3
        $programmes.Count | Should -Be 2
    }
}
