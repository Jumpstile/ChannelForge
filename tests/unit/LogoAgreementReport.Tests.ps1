BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Get-ChannelForgeLogoAgreementReport' {
    It 'counts agree, differ, one-sided and no-id channels by exact id and never prints links' {
        $r = InModuleScope ChannelForge {
            $channels = @(
                [pscustomobject]@{ TvgId = 'a.x'; DisplayName = 'Alpha'; Logo = 'https://img.example.com/a.png' }
                [pscustomobject]@{ TvgId = 'b.x'; DisplayName = 'Bravo'; Logo = 'https://img.example.com/b.png' }
                [pscustomobject]@{ TvgId = 'c.x'; DisplayName = 'Charlie'; Logo = 'https://img.example.com/c.png' }
                [pscustomobject]@{ TvgId = 'd.x'; DisplayName = 'Delta'; Logo = '' }
                [pscustomobject]@{ TvgId = 'e.x'; DisplayName = 'Echo'; Logo = '' }
                [pscustomobject]@{ TvgId = 'A.X'; DisplayName = 'Foxtrot'; Logo = 'https://img.example.com/a.png' }
                [pscustomobject]@{ TvgId = ''; DisplayName = 'Golf'; Logo = 'https://img.example.com/g.png' }
            )
            $icons = @{
                'a.x' = 'https://img.example.com/a.png'
                'b.x' = 'https://img.example.com/other.png'
                'd.x' = 'https://img.example.com/d.png'
            }
            Get-ChannelForgeLogoAgreementReport -Channel $channels -IconByChannelId $icons
        }
        $r.Agree | Should -Be 1
        $r.Differ | Should -Be 1
        $r.DifferNames | Should -Be @('Bravo')
        $r.PlaylistOnly | Should -Be 2
        $r.GuideOnly | Should -Be 1
        $r.Neither | Should -Be 1
        $r.NoId | Should -Be 1
        $r.Warning | Should -Not -Match 'https'
    }

    It 'has no warning when every logo agrees' {
        $r = InModuleScope ChannelForge {
            Get-ChannelForgeLogoAgreementReport -Channel @([pscustomobject]@{ TvgId = 'a.x'; DisplayName = 'Alpha'; Logo = 'https://img.example.com/a.png' }) -IconByChannelId @{ 'a.x' = 'https://img.example.com/a.png' }
        }
        $r.Warning | Should -BeNullOrEmpty
    }
}
