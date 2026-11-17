BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    $script:Build = [datetime]::Parse('2026-10-01T12:00:00Z').ToUniversalTime()
    function New-Chan([string]$Id, [string]$Name) { [pscustomobject]@{ TvgId = $Id; DisplayName = $Name; Group = 'News' } }
    function New-Prog([string]$Id, [string]$StartText, [int]$Hours = 2) {
        $start = [datetimeoffset]::Parse($StartText)
        New-ChannelForgeProgramme -ChannelId $Id -Start $start -End $start.AddHours($Hours) -Title 'Show' -SourceId 'g'
    }
    function Get-Ready($Channel, $Programme) {
        InModuleScope ChannelForge -Parameters @{ C = $Channel; P = $Programme; B = $script:Build } {
            $evidence = @(ConvertTo-ChannelForgeGuideEvidenceFromPlaylist -Channel $C -Programme $P -BuildTimeUtc $B -SourceId 'g')
            [pscustomobject]@{ Evidence = $evidence; Readiness = (Get-ChannelForgeGuideReadiness -Evidence $evidence) }
        }
    }
    function Get-Record($Result, [string]$Id) { @($Result.Readiness.Records | Where-Object { $_.ChannelReference -ceq $Id })[0] }
}

Describe 'Guide evidence from a playlist and one guide' {
    It 'gives readiness a result for a current guide, one record per channel' {
        $r = Get-Ready @((New-Chan 'a' 'Alpha'), (New-Chan 'b' 'Beta')) @((New-Prog 'a' '2026-10-01T10:00:00Z'), (New-Prog 'b' '2026-10-01T11:00:00Z'))
        $r.Evidence.Count | Should -Be 2
        $r.Evidence[0].GetType().Name | Should -Be 'GuideEvidenceRecord'
        @($r.Readiness.Records).Count | Should -Be 2
        (Get-Record $r 'a').ReadinessState | Should -Be 'SafeCandidate'
        $r.Readiness.StateCounts.StaleSource | Should -Be 0
    }

    It 'reports a channel without programmes as missing, and keeps it' {
        $r = Get-Ready @((New-Chan 'a' 'Alpha'), (New-Chan 'none' 'Nothing'), (New-Chan '' 'No id')) @((New-Prog 'a' '2026-10-01T10:00:00Z'))
        @($r.Readiness.Records).Count | Should -Be 3
        $missing = Get-Record $r 'none'
        $missing.ReadinessState | Should -Be 'Unresolved'
        $missing.ReasonCodes | Should -Contain 'NoEventData'
        $r.Readiness.StateCounts.Unresolved | Should -Be 2
    }

    It 'shows a guide that ended before the build as stale' {
        $r = Get-Ready @((New-Chan 'a' 'Alpha'), (New-Chan 'b' 'Beta')) @((New-Prog 'a' '2026-09-20T10:00:00Z'), (New-Prog 'b' '2026-10-01T11:00:00Z'))
        (Get-Record $r 'a').ReadinessState | Should -Be 'StaleSource'
        (Get-Record $r 'b').ReadinessState | Should -Be 'SafeCandidate'
        $r.Readiness.StateCounts.StaleSource | Should -Be 1
    }

    It 'gives the same result whatever the channel order' {
        $channels = @((New-Chan 'c' 'Gamma'), (New-Chan 'a' 'Alpha'), (New-Chan 'x' 'Gone'), (New-Chan '' 'No id'), (New-Chan 'b' 'Beta'))
        $programmes = @((New-Prog 'a' '2026-10-01T10:00:00Z'), (New-Prog 'b' '2026-09-01T10:00:00Z'), (New-Prog 'c' '2026-10-01T10:00:00Z'))
        $one = Get-Ready $channels $programmes
        $two = Get-Ready @($channels[4..0]) @($programmes[2..0])
        ($two.Readiness | ConvertTo-Json -Depth 8) | Should -Be ($one.Readiness | ConvertTo-Json -Depth 8)
    }
}

Describe 'Guide evidence for tvg-ids with spaces and symbols' {
    BeforeAll {
        $script:Odd = @((New-Chan 'BBC One (HD) | UK' 'One'), (New-Chan 'BBC One (HD) & UK' 'Two'), (New-Chan 'No Guide #1' 'Three'))
        $script:OddProg = @((New-Prog 'BBC One (HD) | UK' '2026-10-01T10:00:00Z'), (New-Prog 'BBC One (HD) & UK' '2026-10-01T10:00:00Z'))
    }

    It 'counts a channel with programmes as guided, not missing, and keeps two odd ids apart' {
        $r = Get-Ready $script:Odd $script:OddProg
        @($r.Readiness.Records).Count | Should -Be 3
        $r.Readiness.StateCounts.SafeCandidate | Should -Be 2
        $r.Readiness.StateCounts.Unresolved | Should -Be 1
        @($r.Evidence.ChannelReference | Where-Object { $_ } | Select-Object -Unique).Count | Should -Be 3
    }

    It 'gives the same result whatever the channel order' {
        $one = Get-Ready $script:Odd $script:OddProg
        $two = Get-Ready @($script:Odd[2..0]) @($script:OddProg[1..0])
        ($two.Readiness | ConvertTo-Json -Depth 8) | Should -Be ($one.Readiness | ConvertTo-Json -Depth 8)
    }
}
