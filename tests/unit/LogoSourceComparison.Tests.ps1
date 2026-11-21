BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
}

Describe 'Get-ChannelForgeLogoSourceComparison' {
    It 'names agreement, conflict, one-sided and missing logos, and never returns the link' {
        InModuleScope ChannelForge {
            $playlist = @(
                [pscustomobject]@{ Id = 'a.example'; Logo = 'https://img.example.com/a.png' }
                [pscustomobject]@{ Id = 'b.example'; Logo = 'https://img.example.com/b.png' }
                [pscustomobject]@{ Id = 'c.example'; Logo = 'https://img.example.com/c.png' }
                [pscustomobject]@{ Id = 'e.example'; Logo = '' }
                [pscustomobject]@{ Id = 'Case.example'; Logo = 'https://img.example.com/x.png' }
            )
            $guide = @(
                [pscustomobject]@{ Id = 'a.example'; Icon = 'https://img.example.com/a.png' }
                [pscustomobject]@{ Id = 'b.example'; Icon = 'https://img.example.com/other.png' }
                [pscustomobject]@{ Id = 'd.example'; Icon = 'https://img.example.com/d.png' }
                [pscustomobject]@{ Id = 'e.example'; Icon = '' }
                [pscustomobject]@{ Id = 'case.example'; Icon = 'https://img.example.com/x.png' }
            )
            $rows = @(Get-ChannelForgeLogoSourceComparison -PlaylistRow $playlist -GuideRow $guide)
            $state = [hashtable]::new([System.StringComparer]::Ordinal)
            foreach ($row in $rows) { $state[$row.Id] = $row.State }
            $state['a.example'] | Should -BeExactly 'Agreement'
            $state['b.example'] | Should -BeExactly 'Conflict'
            $state['c.example'] | Should -BeExactly 'PlaylistOnly'
            $state['d.example'] | Should -BeExactly 'GuideOnly'
            $state['e.example'] | Should -BeExactly 'Missing'
            $state['Case.example'] | Should -BeExactly 'PlaylistOnly'
            $state['case.example'] | Should -BeExactly 'GuideOnly'
            ($rows | ConvertTo-Json -Depth 4) | Should -Not -Match 'img\.example\.com'
        }
    }
}
