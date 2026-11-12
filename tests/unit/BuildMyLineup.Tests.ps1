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

    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Pwsh = (Get-Command -Name pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source

    function Get-TestChannelKey {
        param([Parameter(Mandatory)][string]$Url)
        & (Get-Module ChannelForge) { param($u) Get-ChannelForgeChannelKey -Url $u } $Url
    }

    # Six channels: A One/A Two share a.us, B One/B Two/B Three share b.us, Real has a unique id.
    function New-SharedIdFixture {
        param([Parameter(Mandatory)][string]$Name, [hashtable]$Rename = @{})
        $channels = @(
            @('A One', 'a.us', 'a1'), @('A Two', 'a.us', 'a2'),
            @('B One', 'b.us', 'b1'), @('B Two', 'b.us', 'b2'), @('B Three', 'b.us', 'b3'),
            @('Real', 'real.us', 'real'))
        $lines = @('#EXTM3U')
        foreach ($channel in $channels) {
            $title = if ($Rename.ContainsKey($channel[0])) { $Rename[$channel[0]] } else { $channel[0] }
            $lines += "#EXTINF:-1 tvg-id=`"$($channel[1])`" tvg-name=`"$title`" group-title=`"News`",$title"
            $lines += "https://example.invalid/live/$($channel[2])"
        }
        $playlist = Join-Path $TestDrive "$Name.m3u"
        $lines -join "`n" | Set-Content -LiteralPath $playlist -Encoding utf8
        $guide = Join-Path $TestDrive "$Name.xml"
        $xml = @('<?xml version="1.0" encoding="UTF-8"?>', '<tv>')
        foreach ($id in 'a.us', 'b.us', 'real.us') {
            $xml += "  <channel id=`"$id`"><display-name>$id</display-name></channel>"
            $xml += "  <programme start=`"20260824080000 +0000`" stop=`"20260826080000 +0000`" channel=`"$id`"><title>Show $id</title></programme>"
        }
        $xml += '</tv>'
        $xml -join "`n" | Set-Content -LiteralPath $guide -Encoding utf8
        return [pscustomobject]@{ Playlist = $playlist; Guide = $guide; Root = (New-GuidedSetupRoot -Name $Name) }
    }

    # Runs the build with no keyboard (redirected input), in a real child pwsh.
    function Invoke-NoKeyboardBuild {
        param([Parameter(Mandatory)]$Fixture, [string[]]$Extra = @())
        $output = '' | & $script:Pwsh -NoProfile -File $script:WorkflowPath -Root $Fixture.Root -M3UPath $Fixture.Playlist -XMLTVPath $Fixture.Guide -Accept @Extra 2>&1 | Out-String
        return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
    }

    function Set-TestDecisions {
        param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][object[]]$Record)
        New-Item -ItemType Directory -Force -Path (Join-Path $Root 'state') | Out-Null
        $rows = @($Record | ForEach-Object {
                $row = [ordered]@{ key = (Get-TestChannelKey -Url "https://example.invalid/live/$($_.Stream)"); name = $_.Stream; choice = $_.Choice }
                if ($_.GuideId) { $row.guideId = $_.GuideId }
                $row.decidedAt = '2026-11-12T20:00:00Z'
                $row
            })
        ConvertTo-Json -InputObject $rows -Depth 4 | Set-Content -LiteralPath (Join-Path $Root 'state\channel-decisions.json') -Encoding utf8
    }

    function Get-TestGuide {
        param([Parameter(Mandatory)]$Summary, [Parameter(Mandatory)][string]$Name)
        @($Summary.ChannelGuides | Where-Object { $_.name -eq $Name })[0]
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

    It 'keeps the channels and still publishes the guide for exact matches when one is held back' {
        $root = New-GuidedSetupRoot -Name 'accepted'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture -Accept -AmbiguousAction KeepWithoutGuide

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PUBLISHED'
        $summary.GuideStatus | Should -Be 'XMLTV_SELECTED'
        $summary.ConsumerM3UPath | Should -Be 'output/guided-setup/accepted/lineup.m3u'
        $summary.ConsumerXMLTVPath | Should -Be 'output/guided-setup/accepted/guide.xml'
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

    It 'normal mode with no decision: full lineup, affected channels have guide null, report lists them' {
        $fixture = New-SharedIdFixture -Name 'normal-mode'

        $run = Invoke-NoKeyboardBuild -Fixture $fixture

        $run.ExitCode | Should -Be 0
        $run.Output | Should -Match '5 channels have no guide\. Run again and choose OwnPlaceholder'
        $run.Output | Should -Match 'channel-decisions\.json'
        $summary = Read-GuidedSetupSummary -Root $fixture.Root
        $summary.Status | Should -Be 'PUBLISHED'
        $summary.ChannelCount | Should -Be 6
        @($summary.ChannelGuides).Count | Should -Be 6
        @($summary.ChannelGuides | Where-Object { $null -eq $_.guide }).Count | Should -Be 5
        (Get-TestGuide -Summary $summary -Name 'Real').guide | Should -Be 'real.us'
        @($summary.CollisionGroups).Count | Should -Be 2
        $m3u = Get-Content -LiteralPath (Join-Path $fixture.Root 'output\guided-setup\accepted\lineup.m3u') -Raw
        ([regex]::Matches($m3u, '#EXTINF')).Count | Should -Be 6
        $m3u | Should -Not -Match 'tvg-id="(a|b)\.us"'
    }

    It 'strict mode stops on the same input and publishes nothing' {
        $fixture = New-SharedIdFixture -Name 'strict-mode'

        $run = Invoke-NoKeyboardBuild -Fixture $fixture -Extra @('-AmbiguousAction', 'Cancel')

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -Match 'strict mode stopped'
        Test-Path -LiteralPath (Join-Path $fixture.Root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'applies each remembered choice on a second run, even for a renamed channel' {
        $fixture = New-SharedIdFixture -Name 'remembered'
        Invoke-NoKeyboardBuild -Fixture $fixture | Out-Null
        Set-TestDecisions -Root $fixture.Root -Record @(
            @{ Stream = 'a1'; Choice = 'ShareOnPurpose'; GuideId = 'a.us' }
            @{ Stream = 'a2'; Choice = 'ShareOnPurpose'; GuideId = 'a.us' }
            @{ Stream = 'b1'; Choice = 'OwnPlaceholder' }
            @{ Stream = 'b2'; Choice = 'KeepWithoutGuide' }
            @{ Stream = 'b3'; Choice = 'BindTrueMatch'; GuideId = 'real.us' })
        $renamed = New-SharedIdFixture -Name 'remembered' -Rename @{ 'B One' = 'Renamed B1' }

        $run = Invoke-NoKeyboardBuild -Fixture $renamed

        $run.ExitCode | Should -Be 0
        $summary = Read-GuidedSetupSummary -Root $renamed.Root
        $summary.Status | Should -Be 'PUBLISHED'
        (Get-TestGuide -Summary $summary -Name 'A One').guide | Should -Be 'a.us'
        (Get-TestGuide -Summary $summary -Name 'A Two').guide | Should -Be 'a.us'
        (Get-TestGuide -Summary $summary -Name 'Renamed B1').guide | Should -Match '^ChannelForge-[0-9a-f]{32}$'
        (Get-TestGuide -Summary $summary -Name 'B Two').guide | Should -BeNullOrEmpty
        (Get-TestGuide -Summary $summary -Name 'B Three').guide | Should -Be 'real.us'
        $guideXml = Get-Content -LiteralPath (Join-Path $renamed.Root 'output\guided-setup\accepted\guide.xml') -Raw
        $guideXml | Should -Match '<display-name>Renamed B1</display-name>'
        $guideXml | Should -Match '<programme [^>]*channel="ChannelForge-[0-9a-f]{32}"><title>Renamed B1</title>'
        $m3u = @(Get-Content -LiteralPath (Join-Path $renamed.Root 'output\guided-setup\accepted\lineup.m3u'))
        ($m3u | Where-Object { $_ -like '*,B Two' }) | Should -Not -Match 'tvg-id'
        ($m3u | Where-Object { $_ -like '*,B Three' }) | Should -Match 'tvg-id="real\.us"'
    }

    It 'treats a ShareOnPurpose record that covers only part of a group as a collision' {
        $fixture = New-SharedIdFixture -Name 'partial-share'
        Set-TestDecisions -Root $fixture.Root -Record @(@{ Stream = 'a1'; Choice = 'ShareOnPurpose'; GuideId = 'a.us' })

        $normal = Invoke-NoKeyboardBuild -Fixture $fixture
        $strict = Invoke-NoKeyboardBuild -Fixture $fixture -Extra @('-AmbiguousAction', 'Cancel')

        $normal.ExitCode | Should -Be 0
        $summary = Read-GuidedSetupSummary -Root $fixture.Root
        (Get-TestGuide -Summary $summary -Name 'A One').guide | Should -BeNullOrEmpty
        (Get-TestGuide -Summary $summary -Name 'A Two').guide | Should -BeNullOrEmpty
        $strict.ExitCode | Should -Not -Be 0
    }

    It 'falls back to no guide, with a reason, when BindTrueMatch names a guide ID that does not exist' {
        $fixture = New-SharedIdFixture -Name 'bind-missing'
        Set-TestDecisions -Root $fixture.Root -Record @(@{ Stream = 'b3'; Choice = 'BindTrueMatch'; GuideId = 'nowhere.us' })

        $normal = Invoke-NoKeyboardBuild -Fixture $fixture
        $strict = Invoke-NoKeyboardBuild -Fixture $fixture -Extra @('-AmbiguousAction', 'Cancel')

        $normal.ExitCode | Should -Be 0
        $normal.Output | Should -Match "'B Three' was kept without a guide because the guide ID named in the decisions file is not in the guide"
        (Get-TestGuide -Summary (Read-GuidedSetupSummary -Root $fixture.Root) -Name 'B Three').guide | Should -BeNullOrEmpty
        $strict.ExitCode | Should -Not -Be 0
    }

    It 'stops every run when the decisions file is damaged' {
        $fixture = New-SharedIdFixture -Name 'bad-decisions'
        New-Item -ItemType Directory -Force -Path (Join-Path $fixture.Root 'state') | Out-Null
        '{ not json' | Set-Content -LiteralPath (Join-Path $fixture.Root 'state\channel-decisions.json') -Encoding utf8

        $run = Invoke-NoKeyboardBuild -Fixture $fixture

        $run.ExitCode | Should -Not -Be 0
        $run.Output | Should -Match 'decisions file could not be read'
        Test-Path -LiteralPath (Join-Path $fixture.Root 'state\accepted-lineup.json') | Should -BeFalse
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

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -XMLTVPath $script:GuideFixture -Accept -AmbiguousAction Cancel } | Should -Throw '*strict mode stopped*'

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'FAILED'
        $summary.WhatHappened | Should -Match 'strict mode stopped'
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
    It 'keeps event-pattern preview disabled by default' {
        $root = New-GuidedSetupRoot -Name 'event-preview-disabled'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PROPOSAL_READY'
        $summary.EventPatternPreview.Enabled | Should -BeFalse
        $summary.EventPatternPreview.InferenceRan | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'output\reports\guided-event-pattern-preview.json') | Should -BeFalse
    }
    It 'keeps insufficient event examples blocked and report-only' {
        $root = New-GuidedSetupRoot -Name 'event-preview-insufficient'

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -EventPatternPreview -EventPatternExamples @(
            'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm'
            'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm'
        )

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.EventPatternPreview.Status | Should -Be 'BLOCKED'
        $summary.EventPatternPreview.ReviewState | Should -Be 'NeedsReview'
        $summary.EventPatternPreview.InferenceRan | Should -BeFalse
        $summary.EventPatternPreview.Safety.CanPublish | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'runs event-pattern inference and review as a report-only beginner step' {
        $root = New-GuidedSetupRoot -Name 'event-preview-enabled'
        $examples = @(
            'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm'
            'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm'
            'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
        )

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -EventPatternPreview -EventPatternExamples $examples -EventPatternType Fight -EventPatternReferenceInstantUtc '2024-04-15T00:00:00Z'
        $summary = Read-GuidedSetupSummary -Root $root
        $summary.Status | Should -Be 'PROPOSAL_READY'
        $summary.EventPatternPreview.Enabled | Should -BeTrue
        $summary.EventPatternPreview.InferenceRan | Should -BeTrue
        $summary.EventPatternPreview.Safety.PublicationState | Should -Be 'CandidateOnly'
        $summary.EventPatternPreview.Safety.CanPublish | Should -BeFalse
        $summary.EventPatternPreview.Safety.AcceptedStateMutation | Should -Be 'None'
        $summary.EventPatternPreview.Output.MarkdownPath | Should -Be 'output/reports/guided-event-pattern-preview.md'
        foreach ($name in @(
                'guided-event-pattern-preview.json'
                'guided-event-pattern-preview.md'
                'guided-event-pattern-preview.txt'
            )) {
            Test-Path -LiteralPath (Join-Path $root "output\reports\$name") -PathType Leaf | Should -BeTrue
        }
        $json = Get-Content -LiteralPath (Join-Path $root 'output\reports\guided-event-pattern-preview.json') -Raw | ConvertFrom-Json
        $json.ReviewState | Should -Be 'Confirmed'
        $json.Safety.CanPublish | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $root 'output\reports\guided-event-pattern-preview.md') -Raw) | Should -Match 'What ChannelForge found'
        (Get-Content -LiteralPath (Join-Path $root 'output\reports\guided-event-pattern-preview.txt') -Raw) | Should -Match 'Inference ran: true'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }
    It 'accepts Stage A evidence as an event-pattern preview input' {
        $root = New-GuidedSetupRoot -Name 'event-preview-evidence'
        $evidence = @(
            (New-ChannelForgeGuideEvidence -EvidenceType ProviderDisplayText -SourceId provider-a -DisplayName 'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm' -EventType Fight -ConfidenceState Confirmed -ConfidenceScore 90 -FreshnessState Current)
            (New-ChannelForgeGuideEvidence -EvidenceType XMLTV -SourceId epg-a -DisplayName 'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm' -EventType Fight -ConfidenceState Confirmed -ConfidenceScore 90 -FreshnessState Current)
            (New-ChannelForgeGuideEvidence -EvidenceType ScheduleSource -SourceId schedule-a -DisplayName 'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm' -EventType Fight -ConfidenceState Confirmed -ConfidenceScore 90 -FreshnessState Current)
        )

        & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -EventPatternPreview -EventPatternEvidence $evidence -EventPatternType Fight -EventPatternReferenceInstantUtc '2024-04-15T00:00:00Z'

        $summary = Read-GuidedSetupSummary -Root $root
        $summary.EventPatternPreview.InferenceRan | Should -BeTrue
        $summary.EventPatternPreview.ReviewState | Should -Be 'NeedsReview'
        $summary.EventPatternPreview.Safety.AcceptedStateMutation | Should -Be 'None'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }


    It 'refuses acceptance when event-pattern preview is enabled' {
        $root = New-GuidedSetupRoot -Name 'event-preview-accept-blocked'
        $examples = @(
            'UFC 01: Fight Night // UTC Sat 13 Apr 5:00pm'
            'UFC 02: Fight Night // UTC Sat 20 Apr 5:00pm'
            'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
        )

        { & $script:WorkflowPath -Root $root -M3UPath $script:PlaylistFixture -EventPatternPreview -EventPatternExamples $examples -Accept } |
            Should -Throw '*report-only*'
        Test-Path -LiteralPath (Join-Path $root 'state\accepted-lineup.json') | Should -BeFalse
    }

    It 'keeps event preview output deterministic and redacted for equivalent inputs' {
        $examples = @(
            'UFC 01: https://example.invalid/REDACTED // UTC Sat 13 Apr 5:00pm'
            'UFC 02: C:\private\provider\guide.json // UTC Sat 20 Apr 5:00pm'
            'UFC 03: Fight Night // UTC Sat 27 Apr 5:00pm'
        )
        $firstRoot = New-GuidedSetupRoot -Name 'event-preview-deterministic-a'
        $secondRoot = New-GuidedSetupRoot -Name 'event-preview-deterministic-b'
        & $script:WorkflowPath -Root $firstRoot -M3UPath $script:PlaylistFixture -EventPatternPreview -EventPatternExamples $examples -EventPatternType Fight -EventPatternReferenceInstantUtc '2024-04-15T00:00:00Z'
        & $script:WorkflowPath -Root $secondRoot -M3UPath $script:PlaylistFixture -EventPatternPreview -EventPatternExamples @($examples | Sort-Object -Descending) -EventPatternType Fight -EventPatternReferenceInstantUtc '2024-04-15T00:00:00Z'

        foreach ($name in @(
                'guided-event-pattern-preview.json'
                'guided-event-pattern-preview.md'
                'guided-event-pattern-preview.txt'
            )) {
            $first = [IO.File]::ReadAllBytes((Join-Path $firstRoot "output\reports\$name"))
            $second = [IO.File]::ReadAllBytes((Join-Path $secondRoot "output\reports\$name"))
            [Convert]::ToBase64String($first) | Should -Be ([Convert]::ToBase64String($second))
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($first)
            $text | Should -Not -Match 'fixture-token|C:\\private|https?://'
        }
        $firstSummary = Read-GuidedSetupSummary -Root $firstRoot
        $firstSummary.EventPatternPreview.Safety.FilesystemMutation | Should -BeFalse
        $firstSummary.EventPatternPreview.Safety.ProviderMutation | Should -BeFalse
        $firstSummary.EventPatternPreview.Safety.DownstreamMutation | Should -BeFalse
    }
}

Describe 'OwnPlaceholder guide across daylight saving changes' {
    It 'gives one programme per local day with no gap or overlap (<Day>)' -ForEach @(
        @{ From = '20261030230000'; To = '20261104010000'; Day = '2026-11-01'; DayHours = 25 }
        @{ From = '20260306230000'; To = '20260310010000'; Day = '2026-03-08'; DayHours = 23 }
    ) {
        $zone = try { [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time') } catch { [TimeZoneInfo]::FindSystemTimeZoneById('America/New_York') }
        $source = "<?xml version=`"1.0`"?><tv><channel id=`"x`"/><programme start=`"$From +0000`" stop=`"$To +0000`" channel=`"x`"><title>t</title></programme></tv>"
        $bytes = & (Get-Module ChannelForge) { param($b, $z) Add-ChannelForgePlaceholderGuide -XmltvBytes $b -Channel @([pscustomobject]@{ Id = 'own'; Name = 'Own' }) -TimeZone $z } ([Text.Encoding]::UTF8.GetBytes($source)) $zone

        $parse = { param($v) [datetime]::SpecifyKind([datetime]::ParseExact($v.Substring(0, 14), 'yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture), 'Utc') }
        $doc = [xml][Text.Encoding]::UTF8.GetString($bytes)
        $blocks = @($doc.tv.programme | Where-Object { $_.channel -eq 'own' } | ForEach-Object { , @((& $parse $_.start), (& $parse $_.stop)) })

        $blocks.Count | Should -BeGreaterThan 3
        $blocks[0][0] | Should -Be (& $parse $From)
        $blocks[-1][1] | Should -Be (& $parse $To)
        for ($i = 1; $i -lt $blocks.Count; $i++) {
            $blocks[$i][0] | Should -Be $blocks[$i - 1][1]
            [TimeZoneInfo]::ConvertTimeFromUtc($blocks[$i][0], $zone).TimeOfDay | Should -Be ([timespan]::Zero)
        }
        $dstDay = @($blocks | Where-Object { [TimeZoneInfo]::ConvertTimeFromUtc($_[0], $zone).Date -eq [datetime]$Day })[0]
        ($dstDay[1] - $dstDay[0]).TotalHours | Should -Be $DayHours
    }
}

Describe 'Real ETV playlist regression' {
    # Set CHANNELFORGE_ETV_DIR to a folder holding a copy of ETV.m3u and ETV.xml. The build takes about 12 minutes.
    It 'keeps all 482 channels in and out' -Skip:(-not $env:CHANNELFORGE_ETV_DIR) {
        $root = New-GuidedSetupRoot -Name 'etv'
        $pwshExe = (Get-Command -Name pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        '' | & $pwshExe -NoProfile -File $script:WorkflowPath -Root $root -M3UPath (Join-Path $env:CHANNELFORGE_ETV_DIR 'ETV.m3u') -XMLTVPath (Join-Path $env:CHANNELFORGE_ETV_DIR 'ETV.xml') -Accept 2>&1 | Out-Null

        $LASTEXITCODE | Should -Be 0
        $summary = Read-GuidedSetupSummary -Root $root
        $summary.ChannelCount | Should -Be 482
        @($summary.ChannelGuides).Count | Should -Be 482
        $m3u = Get-Content -LiteralPath (Join-Path $root 'output\guided-setup\accepted\lineup.m3u') -Raw
        ([regex]::Matches($m3u, '#EXTINF')).Count | Should -Be 482
    }
}
