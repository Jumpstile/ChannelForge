BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Categories = @((Get-Content -LiteralPath (Join-Path $RepoRoot 'data\rules\categories.json') -Raw | ConvertFrom-Json).categories)
    $script:RegistryKeys = @(InModuleScope ChannelForge { (Get-ChannelForgeOneGuideCategoryRegistry).Key })
}

Describe 'categories.json agrees with the guide category registry' {
    It 'gives every category id a registryKey' {
        $missing = @($script:Categories | Where-Object { -not $_.registryKey } | ForEach-Object { $_.id })
        $missing | Should -BeNullOrEmpty
    }

    It 'only uses registryKey values that exist in the registry' {
        $unknown = @($script:Categories | Where-Object { $_.registryKey -and $_.registryKey -notin $script:RegistryKeys } | ForEach-Object { $_.id })
        $unknown | Should -BeNullOrEmpty
    }
}
