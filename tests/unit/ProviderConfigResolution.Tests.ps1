BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function New-ProviderDirFixture {
        $providerDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Force -Path $providerDir | Out-Null
        return $providerDir
    }
}

Describe 'Resolve-ChannelForgeProviderConfigPath - precedence and discovery' {
    It 'falls back to the tracked file when no local file and no override exist' {
        $providerDir = New-ProviderDirFixture
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'mybunny.json') -Encoding UTF8

        $resolved = Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $providerDir -TrackedFileName 'mybunny.json'

        $resolved | Should -Be (Join-Path $providerDir 'mybunny.json')
    }

    It 'prefers a single local provider file over the tracked file' {
        $providerDir = New-ProviderDirFixture
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'mybunny.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'provider.local.json') -Encoding UTF8

        $resolved = Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $providerDir -TrackedFileName 'mybunny.json'

        $resolved | Should -Be (Join-Path $providerDir 'provider.local.json')
    }

    It 'discovers local files non-recursively (a *.local.json in a subdirectory is ignored)' {
        $providerDir = New-ProviderDirFixture
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'mybunny.json') -Encoding UTF8
        $subDir = Join-Path $providerDir 'nested'
        New-Item -ItemType Directory -Force -Path $subDir | Out-Null
        '{}' | Set-Content -LiteralPath (Join-Path $subDir 'sneaky.local.json') -Encoding UTF8

        $resolved = Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $providerDir -TrackedFileName 'mybunny.json'

        $resolved | Should -Be (Join-Path $providerDir 'mybunny.json')
    }

    It 'throws loudly when multiple local provider files exist, naming both' {
        $providerDir = New-ProviderDirFixture
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'mybunny.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'a.local.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'b.local.json') -Encoding UTF8

        { Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $providerDir -TrackedFileName 'mybunny.json' } | Should -Throw '*a.local.json*b.local.json*'
    }

    It 'does not fall back to the tracked file when the provider directory does not exist yet' {
        $providerDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())

        $resolved = Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $providerDir -TrackedFileName 'mybunny.json'

        $resolved | Should -Be (Join-Path $providerDir 'mybunny.json')
    }
}

Describe 'Resolve-ChannelForgeProviderConfigPath - explicit override precedence' {
    It 'uses the override even when a local file also exists' {
        $providerDir = New-ProviderDirFixture
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'mybunny.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'provider.local.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'chosen.local.json') -Encoding UTF8

        $resolved = Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $providerDir -TrackedFileName 'mybunny.json' -OverridePath 'chosen.local.json'

        $resolved | Should -Be (Join-Path $providerDir 'chosen.local.json')
    }

    It 'bypasses local-file ambiguity entirely when an override is given' {
        $providerDir = New-ProviderDirFixture
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'mybunny.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'a.local.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'b.local.json') -Encoding UTF8
        '{}' | Set-Content -LiteralPath (Join-Path $providerDir 'chosen.local.json') -Encoding UTF8

        { Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $providerDir -TrackedFileName 'mybunny.json' -OverridePath 'chosen.local.json' } | Should -Not -Throw
    }
}

Describe 'Resolve-ChannelForgeProviderConfigPath - override confinement' {
    BeforeEach {
        $script:ProviderDir = New-ProviderDirFixture
        '{}' | Set-Content -LiteralPath (Join-Path $script:ProviderDir 'mybunny.json') -Encoding UTF8
    }

    It 'rejects a traversal override path' {
        { Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $script:ProviderDir -TrackedFileName 'mybunny.json' -OverridePath '..\..\Windows\System32\drivers\etc\hosts' } | Should -Throw '*approved location*'
    }

    It 'rejects an absolute override path outside the provider directory' {
        $outside = Join-Path $TestDrive 'outside-secret.json'
        '{}' | Set-Content -LiteralPath $outside -Encoding UTF8

        { Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $script:ProviderDir -TrackedFileName 'mybunny.json' -OverridePath $outside } | Should -Throw '*approved location*'
    }

    It 'rejects a UNC override path' {
        { Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $script:ProviderDir -TrackedFileName 'mybunny.json' -OverridePath '\\server\share\provider.json' } | Should -Throw '*approved location*'
    }

    It 'rejects an override path that resolves to a directory' {
        $subDir = Join-Path $script:ProviderDir 'adir'
        New-Item -ItemType Directory -Force -Path $subDir | Out-Null

        { Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $script:ProviderDir -TrackedFileName 'mybunny.json' -OverridePath 'adir' } | Should -Throw '*directory*'
    }

    It 'rejects a non-JSON override file' {
        Set-Content -LiteralPath (Join-Path $script:ProviderDir 'provider.local.csv') -Value 'name,url' -Encoding UTF8

        { Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $script:ProviderDir -TrackedFileName 'mybunny.json' -OverridePath 'provider.local.csv' } | Should -Throw '*.json*'
    }

    It 'rejects an override path that does not exist' {
        { Resolve-ChannelForgeProviderConfigPath -ProviderDirectory $script:ProviderDir -TrackedFileName 'mybunny.json' -OverridePath 'does-not-exist.json' } | Should -Throw '*not found*'
    }
}
