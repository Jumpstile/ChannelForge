BeforeAll {
    Mock -CommandName Read-Host -MockWith { '' }
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:WorkflowPath = Join-Path $script:RepoRoot 'scripts\Build-My-Lineup.ps1'
    $script:PlaylistFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\playlist.m3u'
    $script:GuideFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\guide.xml'
    $script:MalformedPlaylist = Join-Path $script:RepoRoot 'tests\fixtures\provider-invalid-url.json'

    function New-GuidedSetupRoot {
        param([Parameter(Mandatory)][string]$Name)

        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'data\rules'), (Join-Path $root 'data\lineup') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\rules\aliases.json') -Destination (Join-Path $root 'data\rules\aliases.json')
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'data\lineup\numbering_blocks.json') -Destination (Join-Path $root 'data\lineup\numbering_blocks.json')
        return $root
    }

    function Read-GuidedSetupSummary {
        param([Parameter(Mandatory)][string]$Root)
        return Get-Content -LiteralPath (Join-Path $Root 'output\reports\guided-setup-summary.json') -Raw | ConvertFrom-Json
    }
}

Describe 'Build-My-Lineup.ps1 beginner workflow' {
    It 'shows a concise candidate proposal without publishing' {
        $root = New-GuidedSetupRoot -Name 'proposal'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PROPOSAL_READY'
        $summary.ChannelCount | Should -Be 5
        $summary.ExactGuideMatchCount | Should -Be 2
        $summary.AmbiguityCount | Should -Be 1
        $summary.GuideOnlyCount | Should -Be 3
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
        $summary.CandidatePath | Should -BeNullOrEmpty
        ($summary | ConvertTo-Json -Depth 12) | Should -Not -Match '[0-9a-f]{64}'
    }


    It 'returns a safe machine plan without mutating accepted state' {
        $root = New-GuidedSetupRoot -Name 'machine-plan'
        $machineLine = @(
            & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture -PlanOnly -MachineResult |
                Where-Object { $_ -is [string] -and $_.StartsWith('CHANNELFORGE_MACHINE_RESULT:') } |
                Select-Object -Last 1
        )

        $machineLine.Count | Should -Be 1
        $machine = ($machineLine -replace '^CHANNELFORGE_MACHINE_RESULT:', '') | ConvertFrom-Json
        $machine.Status | Should -Be 'PROPOSAL_READY'
        $machine.CandidateManifestHash | Should -Match '^[0-9a-f]{64}$'
        $machine.BuildIdentity | Should -Match '^[0-9a-f]{64}$'
        $machine.AcceptedLineupStatus | Should -Be 'none'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'fails closed when the candidate or accepted parent is stale' {
        $root = New-GuidedSetupRoot -Name 'machine-stale'
        $planLine = @(
            & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture -PlanOnly -MachineResult |
                Where-Object { $_ -is [string] -and $_.StartsWith('CHANNELFORGE_MACHINE_RESULT:') } |
                Select-Object -Last 1
        )
        $plan = ($planLine -replace '^CHANNELFORGE_MACHINE_RESULT:', '') | ConvertFrom-Json

        {
            & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture -Accept -AmbiguousAction Cancel `
                -ExpectedCandidateManifestHash ('0' * 64) -ExpectedBuildIdentity $plan.BuildIdentity `
                -ExpectedParentGenerationManifestHash ''
        } | Should -Throw '*candidate is no longer current*'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse

        {
            & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture -Accept -AmbiguousAction Cancel `
                -ExpectedCandidateManifestHash $plan.CandidateManifestHash -ExpectedBuildIdentity $plan.BuildIdentity `
                -ExpectedParentGenerationManifestHash ('1' * 64)
        } | Should -Throw '*accepted parent is no longer current*'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }
    It 'reports several material guide ambiguities before acceptance' {
        $root = New-GuidedSetupRoot -Name 'several-ambiguities'
        $guide = Join-Path $TestDrive 'several-ambiguities.xml'
        @'
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="zeta.us"><display-name>Zeta First</display-name></channel>
  <channel id="zeta.us"><display-name>Zeta Second</display-name></channel>
  <channel id="alpha.us"><display-name>Alpha First</display-name></channel>
  <channel id="alpha.us"><display-name>Alpha Second</display-name></channel>
  <programme start="20260824080000 +0000" stop="20260824090000 +0000" channel="zeta.us"><title>Zeta Morning</title></programme>
  <programme start="20260824100000 +0000" stop="20260824110000 +0000" channel="alpha.us"><title>Alpha Morning</title></programme>
</tv>
'@ | Set-Content -LiteralPath $guide -Encoding utf8

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $guide

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PROPOSAL_READY'
        $summary.AmbiguityCount | Should -Be 2
        $summary.WhatHappened | Should -Match 'Analyzed 5 channels'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'keeps the channels but suppresses an ambiguous guide from accepted output' {
        $root = New-GuidedSetupRoot -Name 'accepted'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture -Accept -AmbiguousAction KeepWithoutGuide

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PUBLISHED'
        $summary.GuideStatus | Should -Be 'GUIDE_SKIPPED_AMBIGUITY'
        $summary.ConsumerM3UPath | Should -Be 'output/guided-setup/accepted/lineup.m3u'
        $summary.ConsumerXMLTVPath | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $root ($summary.ConsumerM3UPath -replace '/', '\')) -PathType Leaf | Should -BeTrue
        $pointer = Get-Content -LiteralPath (Join-Path $root 'state\accepted-lineup.json') -Raw | ConvertFrom-Json
        Test-Path -LiteralPath (Join-Path $root ("state\generations\{0}\merged.m3u" -f $pointer.GenerationId)) -PathType Leaf | Should -BeTrue
    }

    It 'publishes an exact-match XMLTV proposal through the existing acceptance boundary' {
        $root = New-GuidedSetupRoot -Name 'exact-guide'
        $playlist = Join-Path $TestDrive 'exact-guide.m3u'
        @'
#EXTM3U
#EXTINF:-1 tvg-id="zeta.us" tvg-name="Zeta" group-title="News",Zeta Exact
https://example.invalid/live/zeta
#EXTINF:-1 tvg-id="missing-id.us" tvg-name="Missing ID" group-title="News",Missing Tvg Id
https://example.invalid/live/missing-id
#EXTINF:-1 tvg-id="missing.us" tvg-name="Missing Guide" group-title="News",Missing Guide
https://example.invalid/live/missing-guide
#EXTINF:-1 tvg-id="ambiguous.us" tvg-name="Ambiguous" group-title="News",Ambiguous Guide
https://example.invalid/live/ambiguous
#EXTINF:-1 tvg-id="alpha.us" tvg-name="Alpha" group-title="News",Alpha Exact
https://example.invalid/live/alpha
'@ | Set-Content -LiteralPath $playlist -Encoding utf8

        $guide = Join-Path $TestDrive 'exact-guide.xml'
        @'
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="zeta.us"><display-name>Zeta Exact</display-name></channel>
  <channel id="missing-id.us"><display-name>Missing ID</display-name></channel>
  <channel id="missing.us"><display-name>Missing Guide</display-name></channel>
  <channel id="ambiguous.us"><display-name>Ambiguous Guide</display-name></channel>
  <channel id="alpha.us"><display-name>Alpha Exact</display-name></channel>
  <programme start="20260824080000 +0000" stop="20260824090000 +0000" channel="zeta.us"><title>Zeta Morning</title></programme>
  <programme start="20260824090000 +0000" stop="20260824100000 +0000" channel="missing-id.us"><title>Missing ID Morning</title></programme>
  <programme start="20260824100000 +0000" stop="20260824110000 +0000" channel="missing.us"><title>Missing Guide Morning</title></programme>
  <programme start="20260824110000 +0000" stop="20260824120000 +0000" channel="ambiguous.us"><title>Ambiguous Morning</title></programme>
  <programme start="20260824120000 +0000" stop="20260824130000 +0000" channel="alpha.us"><title>Alpha Morning</title></programme>
</tv>
'@ | Set-Content -LiteralPath $guide -Encoding utf8

        & $script:WorkflowPath -Root $root -M3UPath $playlist -XMLTVPath $guide -Accept

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PUBLISHED'
        $summary.ChannelCount | Should -Be 5
        $summary.ExactGuideMatchCount | Should -Be 5
        $summary.AmbiguityCount | Should -Be 0
        $summary.GuideOnlyCount | Should -Be 0
        $summary.ConsumerM3UPath | Should -Be 'output/guided-setup/accepted/lineup.m3u'
        $summary.ConsumerXMLTVPath | Should -Be 'output/guided-setup/accepted/guide.xml'
        Test-Path -LiteralPath (Join-Path $root ($summary.ConsumerM3UPath -replace '/', '\')) -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root ($summary.ConsumerXMLTVPath -replace '/', '\')) -PathType Leaf | Should -BeTrue
    }

    It 'preserves an accepted guide when a later ambiguous guide is kept' {
        $root = New-GuidedSetupRoot -Name 'prior-guide-ambiguity'
        $exactGuide = Join-Path $TestDrive 'prior-guide-exact.xml'
        @'
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="zeta.us"><display-name>Zeta Exact</display-name></channel>
  <channel id="alpha.us"><display-name>Alpha Exact</display-name></channel>
  <programme start="20260824080000 +0000" stop="20260824090000 +0000" channel="zeta.us"><title>Zeta Morning</title></programme>
  <programme start="20260824100000 +0000" stop="20260824110000 +0000" channel="alpha.us"><title>Alpha Morning</title></programme>
</tv>
'@ | Set-Content -LiteralPath $exactGuide -Encoding utf8

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $exactGuide -Accept
        $pointerPath = Join-Path $root 'state\accepted-lineup.json'
        $pointerBefore = Get-Content -LiteralPath $pointerPath -Raw

        $ambiguousGuide = Join-Path $TestDrive 'prior-guide-ambiguous.xml'
        @'
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="zeta.us"><display-name>Zeta First</display-name></channel>
  <channel id="zeta.us"><display-name>Zeta Second</display-name></channel>
  <programme start="20260824080000 +0000" stop="20260824090000 +0000" channel="zeta.us"><title>Zeta Morning</title></programme>
</tv>
'@ | Set-Content -LiteralPath $ambiguousGuide -Encoding utf8

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $ambiguousGuide -Accept -AmbiguousAction KeepWithoutGuide } |
            Should -Throw '*existing accepted guide*'

        (Get-Content -LiteralPath $pointerPath -Raw) | Should -Be $pointerBefore
        (Read-GuidedSetupSummary -Root $root).WhatHappened | Should -Match 'existing accepted guide'
    }
    It 'reports stable consumer view failure after accepted publication without misreporting state' {
        $root = New-GuidedSetupRoot -Name 'consumer-view-failure'

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -Accept -FaultHook 'ConsumerView.BeforeSwap' } |
            Should -Throw '*stable consumer view*'

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PUBLISHED_VIEW_REFRESH_FAILED'
        $summary.WhatHappened | Should -Match 'accepted lineup was published'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') -PathType Leaf | Should -BeTrue
        $pointerPath = Join-Path $root 'state\accepted-lineup.json'
        $pointerBeforeRetry = Get-Content -LiteralPath $pointerPath -Raw
        Test-Path -LiteralPath $pointerPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'output\guided-setup\accepted\lineup.m3u') | Should -BeFalse

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -Accept -FaultHook 'ConsumerView.BeforeSwap' } |
            Should -Throw '*stable consumer view*'

        $retrySummary = Read-GuidedSetupSummary -Root $root
        $retrySummary.Status | Should -Be 'ALREADY_ACCEPTED'
        $retrySummary.WhatHappened | Should -Be 'This exact proposal is already the accepted lineup.'
        $retrySummary.Changed | Should -Be 'Nothing; the accepted lineup was reused.'
        (Get-Content -LiteralPath $pointerPath -Raw) | Should -Be $pointerBeforeRetry
        @(Get-ChildItem -LiteralPath (Join-Path $root 'state\generations') -Directory).Count | Should -Be 1
    }

    It 'reports an accepted-rerun report-write failure without mislabeling it' {
        $root = New-GuidedSetupRoot -Name 'report-write-failure'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -Accept
        $pointerPath = Join-Path $root 'state\accepted-lineup.json'
        $pointerBeforeRetry = Get-Content -LiteralPath $pointerPath -Raw

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -Accept -FaultHook 'Report.BeforeWrite' } |
            Should -Throw '*report write*'

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'ALREADY_ACCEPTED'
        $summary.WhatHappened | Should -Be 'This exact proposal is already the accepted lineup.'
        $summary.Changed | Should -Be 'Nothing; the accepted lineup was reused.'
        $summary.ConsumerM3UPath | Should -Be 'output/guided-setup/accepted/lineup.m3u'
        (Get-Content -LiteralPath $pointerPath -Raw) | Should -Be $pointerBeforeRetry
        @(Get-ChildItem -LiteralPath (Join-Path $root 'state\generations') -Directory).Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $root 'output\guided-setup\accepted\lineup.m3u') -PathType Leaf | Should -BeTrue
    }


    It 'supports the no-guide path without fabricating XMLTV output' {
        $root = New-GuidedSetupRoot -Name 'no-guide'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -Accept

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PUBLISHED'
        $summary.GuideStatus | Should -Be 'NO_GUIDE_SELECTED'
        $summary.ExactGuideMatchCount | Should -Be 0
        $summary.ConsumerM3UPath | Should -Be 'output/guided-setup/accepted/lineup.m3u'
        $summary.ConsumerXMLTVPath | Should -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $root $summary.ConsumerM3UPath) -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'output\guided-setup\accepted\guide.xml') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') -PathType Leaf | Should -BeTrue
    }

    It 'stops on unresolved material ambiguity and preserves accepted state' {
        $root = New-GuidedSetupRoot -Name 'cancel-ambiguity'

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture -Accept -AmbiguousAction Cancel } | Should -Throw '*ambiguous guide match*'

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'FAILED'
        $summary.WhatHappened | Should -Be 'An ambiguous guide match was left unresolved; nothing was published.'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'reports a malformed guide without publishing accepted output' {
        $root = New-GuidedSetupRoot -Name 'malformed-guide'
        $guide = Join-Path $TestDrive 'malformed-guide.xml'
        '<tv><channel id="broken">' | Set-Content -LiteralPath $guide -Encoding utf8

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $guide } | Should -Throw

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'FAILED'
        $summary.Preserved | Should -Match 'accepted output was not changed'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'reports a missing guide path without publishing accepted output' {
        $root = New-GuidedSetupRoot -Name 'missing-guide'
        $missing = Join-Path $TestDrive 'does-not-exist.xml'

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $missing } | Should -Throw

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'FAILED'
        $summary.WhatHappened | Should -Not -Match 'does-not-exist|[A-Z]:\\\\|https?://'
    }

    It 'rejects an empty playlist with an actionable safe summary' {
        $root = New-GuidedSetupRoot -Name 'empty-playlist'
        $empty = Join-Path $TestDrive 'empty.m3u'
        '#EXTM3U' | Set-Content -LiteralPath $empty -Encoding utf8

        { & $script:WorkflowPath -Root $root -M3UPath $empty } | Should -Throw

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'FAILED'
        $summary.WhatHappened | Should -Be 'No channels were found in the IPTV playlist.'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'redacts source paths and stream-shaped values from the user reports' {
        $root = New-GuidedSetupRoot -Name 'redaction'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture

        foreach ($path in @(
                (Join-Path $root 'output\reports\guided-setup-summary.json'),
                (Join-Path $root 'output\reports\guided-setup-plan.md')
            )) {
            $raw = Get-Content -LiteralPath $path -Raw
            $raw | Should -Not -Match 'https?://|[A-Z]:\\|^\\\\'
        }
    }

    It 'writes a safe failure summary for malformed input without publishing' {
        $root = New-GuidedSetupRoot -Name 'malformed'

        { & $script:WorkflowPath -Root $root -M3UPath $script:MalformedPlaylist } | Should -Throw

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'FAILED'
        $summary.Preserved | Should -Match 'accepted output was not changed'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
        $summary.WhatHappened | Should -Not -Match 'https?://|[A-Z]:\\|ACCOUNT_ID|API_TOKEN'
    }

    It 'reuses an identical accepted proposal on a stable rerun' {
        $root = New-GuidedSetupRoot -Name 'rerun'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -Accept
        $first = Read-GuidedSetupSummary -Root $root
        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -Accept
        $second = Read-GuidedSetupSummary -Root $root

        $second.Status | Should -Be 'ALREADY_ACCEPTED'
        @(Get-ChildItem -LiteralPath (Join-Path $root 'state\generations') -Directory).Count | Should -Be 1
    }
}
