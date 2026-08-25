BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildScriptPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'

    function Get-CandidateArtifactPath {
        param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name)
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        return Join-Path $Root (Join-Path ($summary.CandidateNamespacePath -replace '/', '\') $Name)
    }

    function New-RemoteBuildFixture {
        param([string]$Name)

        $root = Join-Path $TestDrive $Name
        $data = Join-Path $root 'data'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $data 'providers'), `
            (Join-Path $data 'epg'), `
            (Join-Path $data 'lineup'), `
            (Join-Path $data 'rules') | Out-Null

        @{ provider = 'fixture-provider'; sources = @() } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'providers\mybunny.json') -Encoding UTF8
        @{ epg_sources = @(
                @{ name = 'remote-guide'; priority = 10; url = 'https://example.invalid/guide.xml'; enabled = $true; role = 'primary' }
            ) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @() } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'rules\aliases.json') -Encoding UTF8

        return $root
    }

    function Invoke-BuildWithConfiguredImporterMock {
        param(
            [string]$Root,
            [object[]]$Programmes,
            [switch]$Fail
        )

        $global:ChannelForgeBuildRemoteProgrammes = @($Programmes)
        if ($Fail) {
            Mock -CommandName Import-ChannelForgeConfiguredXmltvSource `
                -MockWith { throw 'deterministic remote acquisition failure' }
        }
        else {
            Mock -CommandName Import-ChannelForgeConfiguredXmltvSource `
                -MockWith { $global:ChannelForgeBuildRemoteProgrammes }
        }

        # Build-Lineup imports the already-loaded module with -Force. Suppress
        # that reload only in this test so the deterministic module mock remains
        # installed; production has no test override or live-network path.
        Mock -CommandName Import-Module -MockWith { }
        return & $script:BuildScriptPath -Root $Root
    }
}

AfterAll {
    Remove-Variable -Name ChannelForgeBuildRemoteProgrammes -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Build-Lineup remote XMLTV wiring' {
    It 'publishes remote XMLTV only after the importer returns validated programmes' {
        $root = New-RemoteBuildFixture -Name 'remote-build-success'
        $programmes = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'remote-guide')

        Invoke-BuildWithConfiguredImporterMock -Root $root -Programmes $programmes | Out-Null

        $summaryPath = Join-Path $root 'output\reports\build-summary.json'
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        $outputPath = Join-Path $root (Join-Path ($summary.CandidateNamespacePath -replace '/', '\') 'merged.xml')

        $summary.XMLTVStatus | Should -Be 'GENERATED'
        $summary.XMLTVGenerated | Should -BeTrue
        $summary.XMLTVSourceCount | Should -Be 1
        $summary.XMLTVRemoteSourceCount | Should -Be 1
        $summary.XMLTVProgrammeCount | Should -Be 2
        Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $summaryPath -Raw) | Should -Not -Match 'https?://|example\.invalid'
    }

    It 'fails closed on remote acquisition failure and does not publish XMLTV' {
        $root = New-RemoteBuildFixture -Name 'remote-build-failure'
        $programmes = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'remote-guide')

        { Invoke-BuildWithConfiguredImporterMock -Root $root -Programmes $programmes -Fail | Out-Null } |
            Should -Throw '*Configured XMLTV input could not be imported*'

        $summary = Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $summary.XMLTVStatus | Should -Be 'FAILED'
        $summary.XMLTVGenerated | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'output\merged.xml') -PathType Leaf | Should -BeFalse
        (Get-Content -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -Raw) |
            Should -Not -Match 'https?://|example\.invalid'
    }
}
