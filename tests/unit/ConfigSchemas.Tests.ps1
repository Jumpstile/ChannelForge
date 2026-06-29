BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ProviderSchema = Join-Path $RepoRoot 'schemas\provider.schema.json'
    $script:EpgSchema = Join-Path $RepoRoot 'schemas\epg_sources.schema.json'
}

Describe 'Provider source schema' {
    It 'accepts the tracked example template' {
        $path = Join-Path $RepoRoot 'data\providers\provider.example.json'
        Test-Json -Path $path -SchemaFile $script:ProviderSchema | Should -BeTrue
    }

    It 'accepts the tracked fixture provider config' {
        $path = Join-Path $RepoRoot 'data\providers\mybunny.json'
        Test-Json -Path $path -SchemaFile $script:ProviderSchema | Should -BeTrue
    }

    It 'accepts a config that is shape-valid but has a runtime-invalid URL (schema does not duplicate the trust-boundary check)' {
        $path = Join-Path $RepoRoot 'tests\fixtures\provider-invalid-url.json'
        Test-Json -Path $path -SchemaFile $script:ProviderSchema | Should -BeTrue
    }

    It 'rejects a source missing the required enabled field' {
        $path = Join-Path $RepoRoot 'tests\fixtures\provider-schema-invalid.json'
        { Test-Json -Path $path -SchemaFile $script:ProviderSchema -ErrorAction Stop } | Should -Throw '*enabled*'
    }

    It 'rejects a source where enabled is the wrong type' {
        $path = Join-Path $RepoRoot 'tests\fixtures\provider-schema-wrong-type.json'
        { Test-Json -Path $path -SchemaFile $script:ProviderSchema -ErrorAction Stop } | Should -Throw '*boolean*'
    }

    It 'rejects a config missing the top-level sources array' {
        $json = '{"provider":"example-provider"}'
        { Test-Json -Json $json -SchemaFile $script:ProviderSchema -ErrorAction Stop } | Should -Throw '*sources*'
    }

    It 'rejects an unknown top-level property' {
        $json = '{"provider":"example-provider","sources":[{"name":"Sports","url":"https://example.invalid/x","enabled":true}],"unexpected_field":"x"}'
        { Test-Json -Json $json -SchemaFile $script:ProviderSchema -ErrorAction Stop } | Should -Throw
    }
}

Describe 'EPG source schema' {
    It 'accepts the tracked example template' {
        $path = Join-Path $RepoRoot 'data\epg\epg_sources.example.json'
        Test-Json -Path $path -SchemaFile $script:EpgSchema | Should -BeTrue
    }

    It 'accepts the tracked fixture EPG config' {
        $path = Join-Path $RepoRoot 'data\epg\epg_sources.json'
        Test-Json -Path $path -SchemaFile $script:EpgSchema | Should -BeTrue
    }

    It 'accepts a config that is shape-valid but has a runtime-invalid URL (schema does not duplicate the trust-boundary check)' {
        $path = Join-Path $RepoRoot 'tests\fixtures\epg-invalid-url.json'
        Test-Json -Path $path -SchemaFile $script:EpgSchema | Should -BeTrue
    }

    It 'rejects a source missing the required priority field' {
        $path = Join-Path $RepoRoot 'tests\fixtures\epg-schema-invalid.json'
        { Test-Json -Path $path -SchemaFile $script:EpgSchema -ErrorAction Stop } | Should -Throw '*priority*'
    }

    It 'rejects a source with a role outside the known enum' {
        $path = Join-Path $RepoRoot 'tests\fixtures\epg-schema-bad-role.json'
        { Test-Json -Path $path -SchemaFile $script:EpgSchema -ErrorAction Stop } | Should -Throw
    }

    It 'rejects a config missing the top-level epg_sources array' {
        $json = '{}'
        { Test-Json -Json $json -SchemaFile $script:EpgSchema -ErrorAction Stop } | Should -Throw '*epg_sources*'
    }
}

Describe 'Schemas supplement, not replace, runtime validation' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    }

    It 'Read-ChannelForgeProvider still rejects a malformed URL that schema validation alone would accept' {
        $path = Join-Path $RepoRoot 'tests\fixtures\provider-invalid-url.json'

        Test-Json -Path $path -SchemaFile $script:ProviderSchema | Should -BeTrue
        { Read-ChannelForgeProvider -Path $path } | Should -Throw
    }

    It 'Read-ChannelForgeEpgSource still rejects an unsupported URL scheme that schema validation alone would accept' {
        $path = Join-Path $RepoRoot 'tests\fixtures\epg-invalid-url.json'

        Test-Json -Path $path -SchemaFile $script:EpgSchema | Should -BeTrue
        { Read-ChannelForgeEpgSource -Path $path } | Should -Throw
    }
}
