BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
}

Describe 'Team alias with context' {
    It 'sends Giants with no context to review and lists all three teams' {
        $r = Resolve-ChannelForgeTeamAlias -Name 'Giants'
        $r.Status | Should -Be 'Review'
        $r.Candidates.Count | Should -Be 3
        $r.Reason | Should -Not -BeNullOrEmpty
    }

    It 'resolves Giants by <Label>' -ForEach @(
        @{ Label = 'football clue'; Params = @{ Sport = 'Football' }; Team = 'New York Giants'; League = 'NFL' }
        @{ Label = 'MLB clue'; Params = @{ League = 'MLB' }; Team = 'San Francisco Giants'; League = 'MLB' }
        @{ Label = 'NPB clue'; Params = @{ Group = 'NPB Japan' }; Team = 'Yomiuri Giants'; League = 'NPB' }
        @{ Label = 'Cowboys opponent'; Params = @{ Opponent = 'Cowboys' }; Team = 'New York Giants'; League = 'NFL' }
        @{ Label = 'Dodgers opponent'; Params = @{ Opponent = 'Dodgers' }; Team = 'San Francisco Giants'; League = 'MLB' }
    ) {
        $r = Resolve-ChannelForgeTeamAlias -Name 'Giants' @Params
        $r.Status | Should -Be 'Resolved'
        $r.Team | Should -Be $Team
        $r.League | Should -Be $League
    }

    It 'sends Tigers vs Giants to review' {
        (Resolve-ChannelForgeTeamAlias -Name 'Tigers' -Opponent 'Giants').Status | Should -Be 'Review'
    }

    It 'resolves Tigers by league' {
        (Resolve-ChannelForgeTeamAlias -Name 'Tigers' -League 'MLB').Team | Should -Be 'Detroit Tigers'
        (Resolve-ChannelForgeTeamAlias -Name 'Tigers' -League 'NPB').Team | Should -Be 'Hanshin Tigers'
    }

    It 'resolves an unambiguous team with no context' {
        $r = Resolve-ChannelForgeTeamAlias -Name 'Celtics'
        $r.Status | Should -Be 'Resolved'
        $r.Team | Should -Be 'Boston Celtics'
    }

    It 'records the rejected candidates as negative evidence' {
        $r = Resolve-ChannelForgeTeamAlias -Name 'Giants' -League 'MLB'
        $neg = @($r.Evidence | Where-Object Kind -eq 'Negative')
        $neg.Count | Should -Be 2
        ($neg.Candidate | Sort-Object) | Should -Be @('New York Giants', 'Yomiuri Giants')
        @($r.Evidence | Where-Object { $_.Kind -eq 'Positive' -and $_.Candidate -eq 'San Francisco Giants' }).Count | Should -Be 1
    }

    It 'sends contradicting clues to review with conflicting evidence' {
        $r = Resolve-ChannelForgeTeamAlias -Name 'Giants' -League 'MLB' -Opponent 'Cowboys'
        $r.Status | Should -Be 'Review'
        @($r.Evidence | Where-Object Kind -eq 'Conflicting').Count | Should -BeGreaterThan 0
    }
}
