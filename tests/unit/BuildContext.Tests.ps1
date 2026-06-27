BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'New-ChannelForgeBuildContext' {
    It 'creates a build context with required metadata' {
        $context = New-ChannelForgeBuildContext -SourceDirectory $RepoRoot

        $context.BuildId | Should -Not -BeNullOrEmpty
        $context.BuildTime | Should -BeOfType [datetime]
        $context.Version | Should -Not -BeNullOrEmpty
        $context.SourceDirectory | Should -Be $RepoRoot
    }

    It 'initializes collection properties' {
        $context = New-ChannelForgeBuildContext

        $context.Providers.Count | Should -Be 0
        $context.Playlists.Count | Should -Be 0
        $context.Channels.Count | Should -Be 0
        $context.GuideSources.Count | Should -Be 0
        $context.Programmes.Count | Should -Be 0
        $context.Warnings.Count | Should -Be 0
        $context.Errors.Count | Should -Be 0
        $context.Information.Count | Should -Be 0
    }

    It 'initializes statistics and outputs as hashtables' {
        $context = New-ChannelForgeBuildContext

        $context.Statistics | Should -BeOfType [hashtable]
        $context.Outputs | Should -BeOfType [hashtable]
    }
}