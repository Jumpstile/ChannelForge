BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ProviderParser.psm1') -Force
}

Describe 'Read-ChannelForgeProvider' {
    It 'loads all configured M3U sources' {
        $path = Join-Path $RepoRoot 'data\providers\mybunny.json'

        $sources = @(Read-ChannelForgeProvider -Path $path)

        $sources.Count | Should -Be 16
    }

    It 'includes the Sports source' {
        $path = Join-Path $RepoRoot 'data\providers\mybunny.json'

        $sources = @(Read-ChannelForgeProvider -Path $path)

        $sources.Name | Should -Contain 'Sports'
        ($sources | Where-Object Name -eq 'Sports').Url | Should -Be 'https://example.invalid/REDACTED'
    }

    It 'throws when the provider file is missing' {
        { Read-ChannelForgeProvider -Path '.\does-not-exist.json' } | Should -Throw
    }
}