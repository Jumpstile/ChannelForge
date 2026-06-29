BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    $script:PublicDir = Join-Path $RepoRoot 'src\ChannelForge\Public'
    $script:PrivateDir = Join-Path $RepoRoot 'src\ChannelForge\Private'

    Import-Module $script:ManifestPath -Force
    $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
}

Describe 'ChannelForge module manifest' {
    It 'passes Test-ModuleManifest' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'imports successfully with Import-Module -Force' {
        { Import-Module $script:ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        (Get-Module -Name ChannelForge) | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the functions in src/ChannelForge/Public, no more, no fewer' {
        $publicFunctionNames = @((Get-ChildItem -LiteralPath $script:PublicDir -Filter '*.ps1').BaseName | Sort-Object)
        $manifestFunctionNames = @($script:Manifest.FunctionsToExport | Sort-Object)

        $manifestFunctionNames | Should -Be $publicFunctionNames
    }

    It 'does not use a wildcard for FunctionsToExport' {
        $script:Manifest.FunctionsToExport | Should -Not -Contain '*'
    }

    It 'exports no cmdlets' {
        @($script:Manifest.CmdletsToExport) | Should -BeNullOrEmpty
    }

    It 'exports no variables' {
        @($script:Manifest.VariablesToExport) | Should -BeNullOrEmpty
    }

    It 'exports no aliases' {
        @($script:Manifest.AliasesToExport) | Should -BeNullOrEmpty
    }

    It 'actually exports, at runtime, exactly what the manifest declares' {
        $module = Get-Module -Name ChannelForge
        $exportedFunctionNames = @($module.ExportedFunctions.Keys | Sort-Object)
        $manifestFunctionNames = @($script:Manifest.FunctionsToExport | Sort-Object)

        $exportedFunctionNames | Should -Be $manifestFunctionNames
        @($module.ExportedCmdlets.Keys) | Should -BeNullOrEmpty
        @($module.ExportedVariables.Keys) | Should -BeNullOrEmpty
        @($module.ExportedAliases.Keys) | Should -BeNullOrEmpty
    }

    It 'declares Core as the only compatible PSEdition' {
        $script:Manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'declares a PowerShellVersion of at least 7.0' {
        [version]$script:Manifest.PowerShellVersion | Should -BeGreaterOrEqual ([version]'7.0')
    }

    It 'does not declare RequiredModules (no runtime module dependencies today)' {
        $script:Manifest.Keys | Should -Not -Contain 'RequiredModules'
    }

    It 'declares a ProjectUri pointing at the real GitHub repository' {
        $script:Manifest.PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/Jumpstile/ChannelForge'
    }

    It 'does not claim a LicenseUri (no license file is tracked yet)' {
        $script:Manifest.PrivateData.PSData.Keys | Should -Not -Contain 'LicenseUri'
    }

    It 'does not export any Private helper function' {
        $privateFunctionNames = @((Get-ChildItem -LiteralPath $script:PrivateDir -Filter '*.ps1').BaseName)
        $module = Get-Module -Name ChannelForge

        $privateFunctionNames | Should -Not -BeNullOrEmpty
        foreach ($name in $privateFunctionNames) {
            $module.ExportedFunctions.Keys | Should -Not -Contain $name
            Get-Command -Name $name -Module ChannelForge -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    It 'has no name shared between Public and Private (a prerequisite for the export checks above to mean anything)' {
        $publicFunctionNames = @((Get-ChildItem -LiteralPath $script:PublicDir -Filter '*.ps1').BaseName)
        $privateFunctionNames = @((Get-ChildItem -LiteralPath $script:PrivateDir -Filter '*.ps1').BaseName)

        $overlap = $publicFunctionNames | Where-Object { $privateFunctionNames -contains $_ }
        $overlap | Should -BeNullOrEmpty
    }
}

Describe 'Module root directory has no orphaned/unreferenced .psm1 files' {
    It 'contains only the manifest-referenced root module' {
        $moduleRoot = Join-Path $RepoRoot 'src\ChannelForge'
        $psm1Files = @((Get-ChildItem -LiteralPath $moduleRoot -Filter '*.psm1').Name)

        $psm1Files | Should -Be @($script:Manifest.RootModule)
    }
}
