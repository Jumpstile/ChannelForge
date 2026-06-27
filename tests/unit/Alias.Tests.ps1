BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $AliasPath = Join-Path $RepoRoot 'data\rules\aliases.json'
}

Describe 'Resolve-ChannelForgeAlias' {
    It 'returns the canonical value when input is already canonical' {
        Resolve-ChannelForgeAlias -Name 'FS1' -AliasPath $AliasPath | Should -Be 'FS1'
    }

    It 'resolves FOX Sports One to FS1' {
        Resolve-ChannelForgeAlias -Name 'FOX Sports One' -AliasPath $AliasPath | Should -Be 'FS1'
    }

    It 'resolves FOX Sports 1 to FS1' {
        Resolve-ChannelForgeAlias -Name 'FOX Sports 1' -AliasPath $AliasPath | Should -Be 'FS1'
    }

    It 'resolves ESPN HD to ESPN' {
        Resolve-ChannelForgeAlias -Name 'ESPN HD' -AliasPath $AliasPath | Should -Be 'ESPN'
    }

    It 'resolves aliases case-insensitively' {
        Resolve-ChannelForgeAlias -Name 'fox sports one' -AliasPath $AliasPath | Should -Be 'FS1'
    }

    It 'returns unknown names unchanged' {
        Resolve-ChannelForgeAlias -Name 'Unknown Channel' -AliasPath $AliasPath | Should -Be 'Unknown Channel'
    }

    It 'throws when the alias file is missing' {
        { Resolve-ChannelForgeAlias -Name 'FS1' -AliasPath '.\missing-aliases.json' } | Should -Throw
    }
}