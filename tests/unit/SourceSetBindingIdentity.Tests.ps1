BeforeAll {
    $script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:Repo 'src/ChannelForge/ChannelForge.psd1') -Force -WarningAction SilentlyContinue
    function script:New-Fixture {
        $root = Join-Path $TestDrive ('f-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force "$root/data/rules", "$root/data/lineup", "$root/in" | Out-Null
        Copy-Item (Join-Path $script:Repo 'data/rules/aliases.json') "$root/data/rules"
        Copy-Item (Join-Path $script:Repo 'data/lineup/numbering_blocks.json') "$root/data/lineup"
        $utf8 = [Text.UTF8Encoding]::new($false)
        foreach ($n in 'alpha', 'beta') {
            [IO.File]::WriteAllText("$root/in/$n.m3u", "#EXTM3U`n#EXTINF:-1 tvg-id=`"$n`",$n`nhttps://example.invalid/$n`n", $utf8)
        }
        $both = '<?xml version="1.0"?><tv><channel id="alpha"><display-name>alpha</display-name></channel><channel id="beta"><display-name>beta</display-name></channel>' +
        '<programme start="20260101000000 +0000" stop="20260101010000 +0000" channel="alpha"><title>A</title></programme>' +
        '<programme start="20260101000000 +0000" stop="20260101010000 +0000" channel="beta"><title>B</title></programme></tv>'
        $onlyBeta = '<?xml version="1.0"?><tv><channel id="beta"><display-name>beta</display-name></channel>' +
        '<programme start="20260101000000 +0000" stop="20260101010000 +0000" channel="beta"><title>B2</title></programme></tv>'
        [IO.File]::WriteAllText("$root/in/one.xml", $both, $utf8)
        [IO.File]::WriteAllText("$root/in/two.xml", $onlyBeta, $utf8)
        $root
    }
    function script:New-Pl([string]$Root, [string]$Name, [int]$Priority = 1) {
        [pscustomobject]@{ SourceId = "p-$Name"; SourceKey = "p-$Name"; Label = $Name; Priority = $Priority; Path = "$Root/in/$Name.m3u" }
    }
    function script:New-Gd([string]$Root, [string]$Name, [string]$File, [int]$Priority = 1) {
        [pscustomobject]@{ SourceId = "g-$Name"; SourceKey = "g-$Name"; Label = $Name; Priority = $Priority; Path = "$Root/in/$File.xml"; Url = $null }
    }
    function script:New-Bd([string]$Guide, [string[]]$Playlists = @(), [bool]$All = $false, [bool]$Unbound = $false, [int]$Revision = 1, [bool]$Enabled = $true) {
        [pscustomobject]@{ GuideId = "g-$Guide"; PlaylistIds = @($Playlists | ForEach-Object { "p-$_" }); AppliesToAll = $All; ExplicitlyUnbound = $Unbound; Revision = $Revision; Enabled = $Enabled }
    }
    function script:Build($Root, $Playlists, $Guides, $Bindings) {
        New-ChannelForgeSourceSetCandidateProposal -Root $Root -PlaylistSources @($Playlists) -GuideSources @($Guides) -Bindings @($Bindings) `
            -OutputRoot (Join-Path $Root ('out-' + [guid]::NewGuid().ToString('N'))) -WarningAction SilentlyContinue 3>$null
    }
    # Recorded from the code before slice 5a, with this fixture.
    $script:GoldenBuildIdentity = '09667b8cac2c3f5103c774f9dcf1869316a5398789b4a89332afbdd96c46da33'
    $script:GoldenManifestHash = '78cf8c32373957438705157b93dd378be9b89d275d23cd01d819a2441471dbd2'
    $script:GoldenSingleBuildIdentity = 'dcdad87d332b6b3d43a9b19728c2c6bf3582fe3223a0e11eae050d632edc02a1'
    $script:GoldenSingleManifestHash = 'a906918f80400fc8e45c779bf38e539dab981f7a713a234d5f50c36be1a2c29a'
}

Describe 'Source set binding identity' {
    BeforeEach {
        $script:R = New-Fixture
        $script:PA = New-Pl $script:R 'alpha'
        $script:PB = New-Pl $script:R 'beta' 2
        $script:G1 = New-Gd $script:R 'one' 'one'
        $script:G2 = New-Gd $script:R 'two' 'two' 2
    }

    Context 'simple set keeps today''s hash' {
        It 'source-set route gives the recorded values every time' {
            foreach ($i in 1, 2) {
                $c = Build $script:R @($script:PA) @($script:G1) @(New-Bd 'one' @('alpha'))
                $c.BuildIdentity | Should -Be $script:GoldenBuildIdentity
                $c.CandidateManifestHash | Should -Be $script:GoldenManifestHash
            }
        }
        It 'ALL with one playlist is the same simple set' {
            $c = Build $script:R @($script:PA) @($script:G1) @(New-Bd 'one' -All $true)
            $c.CandidateManifestHash | Should -Be $script:GoldenManifestHash
        }
        It 'single-source route gives its recorded values' {
            $c = New-ChannelForgeCandidateProposal -Root $script:R -M3UPath "$script:R/in/alpha.m3u" -XMLTVPath "$script:R/in/one.xml" `
                -OutputRoot "$script:R/out-single" -CandidateContractVersion 'blocker-2-contract/v8' -WarningAction SilentlyContinue 3>$null 6>$null
            $c.BuildIdentity | Should -Be $script:GoldenSingleBuildIdentity
            $c.CandidateManifestHash | Should -Be $script:GoldenSingleManifestHash
        }
    }

    Context 'binding changes show up in the hash' {
        It 'changing the binding target changes the hash' {
            $a = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('alpha'))
            $b = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('beta') -Revision 2)
            $b.BuildIdentity | Should -Not -Be $a.BuildIdentity
            $b.CandidateManifestHash | Should -Not -Be $a.CandidateManifestHash
        }
        It 'ALL and the same explicit list differ only by revision (mode is the same)' {
            $all = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' -All $true)
            $list = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('alpha', 'beta'))
            $list.CandidateManifestHash | Should -Be $all.CandidateManifestHash
            $listRev2 = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('alpha', 'beta') -Revision 2)
            $listRev2.CandidateManifestHash | Should -Not -Be $all.CandidateManifestHash
        }
        It 'disabling a binding changes the hash and the guide is not applied' {
            $on = Build $script:R @($script:PA) @($script:G1) @(New-Bd 'one' @('alpha'))
            $off = Build $script:R @($script:PA) @($script:G1) @(New-Bd 'one' @('alpha') -Revision 2 -Enabled $false)
            $off.CandidateManifestHash | Should -Not -Be $on.CandidateManifestHash
            Test-Path (Join-Path $off.CandidateDirectory 'merged.xml') | Should -BeFalse
            Test-Path (Join-Path $on.CandidateDirectory 'merged.xml') | Should -BeTrue
        }
        It 'Enabled flipped at the same revision still changes the hash' {
            $on = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('alpha'))
            $off = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('alpha') -Enabled $false)
            $off.CandidateManifestHash | Should -Not -Be $on.CandidateManifestHash
        }
        It 'a no-op binding call leaves the hash unchanged' {
            $a = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('alpha'))
            $b = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('alpha'))
            $b.CandidateManifestHash | Should -Be $a.CandidateManifestHash
        }
        It 'enumeration order of sources does not change the hash' {
            $bindings = @((New-Bd 'one' @('alpha')), (New-Bd 'two' @('beta')))
            $a = Build $script:R @($script:PA, $script:PB) @($script:G1, $script:G2) $bindings
            $b = Build $script:R @($script:PB, $script:PA) @($script:G2, $script:G1) @($bindings[1], $bindings[0])
            $b.CandidateManifestHash | Should -Be $a.CandidateManifestHash
        }
    }

    Context 'guides stay with their own playlists' {
        It 'a guide bound only to alpha does not enrich beta' {
            $c = Build $script:R @($script:PA, $script:PB) @($script:G1) @(New-Bd 'one' @('alpha'))
            $m3u = @($c.Manifest.BindingRecords | Where-Object { [string]$_.BindingKind -eq 'M3U' })
            @($m3u | Where-Object { [string]$_.Status -eq 'ExactBound' }).Count | Should -Be 1
            @($m3u | Where-Object { [string]$_.Status -eq 'Unbound' }).Count | Should -Be 1
        }
        It 'two guides bound to different playlists keep their own matches' {
            $c = Build $script:R @($script:PA, $script:PB) @($script:G1, $script:G2) @((New-Bd 'one' @('alpha')), (New-Bd 'two' @('beta')))
            $m3u = @($c.Manifest.BindingRecords | Where-Object { [string]$_.BindingKind -eq 'M3U' })
            @($m3u | Where-Object { [string]$_.Status -eq 'ExactBound' }).Count | Should -Be 2
        }
    }
}
