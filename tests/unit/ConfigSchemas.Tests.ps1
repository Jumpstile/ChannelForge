BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ProviderSchema = Join-Path $RepoRoot 'schemas\provider.schema.json'
    $script:EpgSchema = Join-Path $RepoRoot 'schemas\epg_sources.schema.json'
    $script:LocalsSchema = Join-Path $RepoRoot 'schemas\locals.schema.json'
    $script:NumberingBlocksSchema = Join-Path $RepoRoot 'schemas\numbering_blocks.schema.json'
    $script:CategoriesSchema = Join-Path $RepoRoot 'schemas\categories.schema.json'
    $script:AliasesSchema = Join-Path $RepoRoot 'schemas\aliases.schema.json'
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

    It 'accepts a provider name never seen in tracked examples (schema is not overfit to current provider names)' {
        $json = '{"provider":"some-other-provider-entirely","sources":[{"name":"Whatever","url":"https://example.invalid/x","enabled":true}]}'
        Test-Json -Json $json -SchemaFile $script:ProviderSchema | Should -BeTrue
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

    It 'accepts a role outside the roles seen in tracked data today (schema is not overfit to the current role list)' {
        $path = Join-Path $RepoRoot 'tests\fixtures\epg-schema-bad-role.json'
        Test-Json -Path $path -SchemaFile $script:EpgSchema | Should -BeTrue
    }

    It 'rejects a role that is the wrong type' {
        $json = '{"epg_sources":[{"name":"x","priority":1,"url":"https://example.invalid/x","enabled":true,"role":5}]}'
        { Test-Json -Json $json -SchemaFile $script:EpgSchema -ErrorAction Stop } | Should -Throw
    }

    It 'rejects a config missing the top-level epg_sources array' {
        $json = '{}'
        { Test-Json -Json $json -SchemaFile $script:EpgSchema -ErrorAction Stop } | Should -Throw '*epg_sources*'
    }
}

Describe 'Locals schema' {
    It 'accepts the tracked locals config' {
        $path = Join-Path $RepoRoot 'data\lineup\locals.json'
        Test-Json -Path $path -SchemaFile $script:LocalsSchema | Should -BeTrue
    }

    It 'accepts a station/network/market never seen in tracked data (schema is not overfit to current values)' {
        $json = '{"locals":[{"number":99,"station":"WXYZ","network":"Some New Network","market":"Nowhere","display":"WXYZ Some New Network Nowhere"}]}'
        Test-Json -Json $json -SchemaFile $script:LocalsSchema | Should -BeTrue
    }

    It 'accepts an empty locals array' {
        $json = '{"locals":[]}'
        Test-Json -Json $json -SchemaFile $script:LocalsSchema | Should -BeTrue
    }

    It 'rejects a local channel where number is the wrong type' {
        $path = Join-Path $RepoRoot 'tests\fixtures\locals-schema-invalid.json'
        { Test-Json -Path $path -SchemaFile $script:LocalsSchema -ErrorAction Stop } | Should -Throw '*number*'
    }

    It 'rejects a local channel missing a required field' {
        $json = '{"locals":[{"number":2,"station":"WCBS","network":"CBS","market":"New York"}]}'
        { Test-Json -Json $json -SchemaFile $script:LocalsSchema -ErrorAction Stop } | Should -Throw '*display*'
    }

    It 'rejects a config missing the top-level locals array' {
        $json = '{}'
        { Test-Json -Json $json -SchemaFile $script:LocalsSchema -ErrorAction Stop } | Should -Throw '*locals*'
    }
}

Describe 'Numbering blocks schema' {
    It 'accepts the tracked numbering blocks config' {
        $path = Join-Path $RepoRoot 'data\lineup\numbering_blocks.json'
        Test-Json -Path $path -SchemaFile $script:NumberingBlocksSchema | Should -BeTrue
    }

    It 'accepts a category never seen in tracked data (schema is not overfit to current categories)' {
        $json = '{"blocks":[{"start":1000,"end":1099,"category":"Some New Category"}]}'
        Test-Json -Json $json -SchemaFile $script:NumberingBlocksSchema | Should -BeTrue
    }

    It 'accepts a block without optional notes' {
        $json = '{"blocks":[{"start":1,"end":10,"category":"Test"}]}'
        Test-Json -Json $json -SchemaFile $script:NumberingBlocksSchema | Should -BeTrue
    }

    It 'rejects a block missing the required category field' {
        $path = Join-Path $RepoRoot 'tests\fixtures\numbering-blocks-schema-invalid.json'
        { Test-Json -Path $path -SchemaFile $script:NumberingBlocksSchema -ErrorAction Stop } | Should -Throw '*category*'
    }

    It 'rejects a block where start is the wrong type' {
        $json = '{"blocks":[{"start":"100","end":199,"category":"Test"}]}'
        { Test-Json -Json $json -SchemaFile $script:NumberingBlocksSchema -ErrorAction Stop } | Should -Throw
    }

    It 'rejects a config missing the top-level blocks array' {
        $json = '{}'
        { Test-Json -Json $json -SchemaFile $script:NumberingBlocksSchema -ErrorAction Stop } | Should -Throw '*blocks*'
    }
}

Describe 'Categories schema' {
    It 'accepts the tracked categories config' {
        $path = Join-Path $RepoRoot 'data\lineup\categories.json'
        Test-Json -Path $path -SchemaFile $script:CategoriesSchema | Should -BeTrue
    }

    It 'accepts a category list never seen in tracked data (schema is not overfit to current categories)' {
        $json = '{"primary_categories":["Something Entirely New"]}'
        Test-Json -Json $json -SchemaFile $script:CategoriesSchema | Should -BeTrue
    }

    It 'accepts a config without the optional policy fields' {
        $json = '{"primary_categories":["A","B"]}'
        Test-Json -Json $json -SchemaFile $script:CategoriesSchema | Should -BeTrue
    }

    It 'rejects a config missing the required primary_categories field' {
        $path = Join-Path $RepoRoot 'tests\fixtures\categories-schema-invalid.json'
        { Test-Json -Path $path -SchemaFile $script:CategoriesSchema -ErrorAction Stop } | Should -Throw '*primary_categories*'
    }

    It 'rejects an empty primary_categories array' {
        $json = '{"primary_categories":[]}'
        { Test-Json -Json $json -SchemaFile $script:CategoriesSchema -ErrorAction Stop } | Should -Throw
    }

    It 'rejects an unknown top-level property' {
        $json = '{"primary_categories":["A"],"unexpected_field":"x"}'
        { Test-Json -Json $json -SchemaFile $script:CategoriesSchema -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Aliases schema' {
    It 'accepts the tracked aliases config' {
        $path = Join-Path $RepoRoot 'data\rules\aliases.json'
        Test-Json -Path $path -SchemaFile $script:AliasesSchema | Should -BeTrue
    }

    It 'accepts a canonical/alias never seen in tracked data (schema is not overfit to current channel names)' {
        $json = '{"aliases":[{"canonical":"Some New Channel","aliases":["Some New Channel","SNC"]}]}'
        Test-Json -Json $json -SchemaFile $script:AliasesSchema | Should -BeTrue
    }

    It 'accepts an empty aliases array' {
        $json = '{"aliases":[]}'
        Test-Json -Json $json -SchemaFile $script:AliasesSchema | Should -BeTrue
    }

    It 'rejects an alias entry with an empty aliases list' {
        $path = Join-Path $RepoRoot 'tests\fixtures\aliases-schema-invalid.json'
        { Test-Json -Path $path -SchemaFile $script:AliasesSchema -ErrorAction Stop } | Should -Throw '*aliases*'
    }

    It 'rejects an alias entry missing the canonical field' {
        $json = '{"aliases":[{"aliases":["FS1"]}]}'
        { Test-Json -Json $json -SchemaFile $script:AliasesSchema -ErrorAction Stop } | Should -Throw '*canonical*'
    }

    It 'rejects a config missing the top-level aliases array' {
        $json = '{}'
        { Test-Json -Json $json -SchemaFile $script:AliasesSchema -ErrorAction Stop } | Should -Throw '*aliases*'
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
