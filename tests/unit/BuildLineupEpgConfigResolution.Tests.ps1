BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildLineupPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'

    function New-EpgSelectionFixture {
        param(
            [Parameter(Mandatory)]
            [string]$BaseRoot,

            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [object[]]$DefaultSources,

            [object[]]$LocalSources,

            [switch]$CreateLocal,

            [string]$LocalRaw
        )

        $fixtureRoot = Join-Path $BaseRoot $Name
        $dataDir = Join-Path $fixtureRoot 'data'
        $epgDir = Join-Path $dataDir 'epg'
        $playlistDir = Join-Path $dataDir 'playlists'

        New-Item -ItemType Directory -Force -Path @(
            (Join-Path $dataDir 'providers')
            $epgDir
            (Join-Path $dataDir 'lineup')
            (Join-Path $dataDir 'rules')
            $playlistDir
        ) | Out-Null

        @'
#EXTM3U
#EXTINF:-1 tvg-id="fixture.us" group-title="News",Fixture Channel
https://example.invalid/live/fixture
'@ | Set-Content -LiteralPath (Join-Path $playlistDir 'fixture.m3u') -Encoding utf8NoBOM

        @{
            provider = 'fixture-provider'
            sources  = @(
                @{
                    name           = 'Fixture'
                    group          = 'News'
                    url            = 'https://example.invalid/iptv/fixture'
                    enabled        = $false
                    local_playlist = 'data/playlists/fixture.m3u'
                }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding utf8NoBOM

        @{
            epg_sources = @($DefaultSources)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $epgDir 'epg_sources.json') -Encoding utf8NoBOM

        if ($CreateLocal) {
            $localPath = Join-Path $epgDir 'epg_sources.local.json'
            if ($PSBoundParameters.ContainsKey('LocalRaw')) {
                Set-Content -LiteralPath $localPath -Value $LocalRaw -Encoding utf8NoBOM
            }
            else {
                @{
                    epg_sources = @($LocalSources)
                } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $localPath -Encoding utf8NoBOM
            }
        }

        @{ locals = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding utf8NoBOM
        @{ blocks = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding utf8NoBOM
        @{ aliases = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding utf8NoBOM

        return $fixtureRoot
    }

    function Invoke-BuildFailure {
        param([Parameter(Mandatory)][string]$Root)

        $message = $null
        try {
            & $script:BuildLineupPath -Root $Root *> $null
        }
        catch {
            $message = $_.Exception.Message
        }

        return $message
    }

    function Get-BuildReports {
        param([Parameter(Mandatory)][string]$Root)

        $summaryPath = Join-Path $Root 'output\reports\build-summary.json'
        $planPath = Join-Path $Root 'output\reports\lineup-plan.md'
        $summaryRaw = Get-Content -LiteralPath $summaryPath -Raw
        $planRaw = Get-Content -LiteralPath $planPath -Raw

        return [pscustomobject]@{
            Summary    = $summaryRaw | ConvertFrom-Json
            SummaryRaw = $summaryRaw
            PlanRaw    = $planRaw
        }
    }

    function Assert-NoPrivateConfigurationData {
        param([Parameter(Mandatory)][string[]]$Text)

        foreach ($value in $Text) {
            $value | Should -Not -Match 'https?://'
            $value | Should -Not -Match 'ACCOUNT_ID|API_TOKEN|PASSWORD|SECRET|TOKEN'
            $value | Should -Not -Match '[A-Z]:\\|^\\\\'
        }
    }
}

Describe 'Build-Lineup.ps1 EPG configuration selection (#91)' {
    It 'uses the default configuration when no local override exists and reports a safe deterministic label' {
        $root = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'default-only' -DefaultSources @(
            @{ name = 'Default Guide'; priority = 10; path = 'default.xml'; enabled = $false; role = 'primary' }
        )

        & $script:BuildLineupPath -Root $root
        $reports = Get-BuildReports -Root $root

        $reports.Summary.EPGConfigSource | Should -Be 'Default'
        $reports.Summary.EPGSources | Should -Be 1
        $reports.PlanRaw | Should -Match 'EPG configuration: Default'
        $reports.PlanRaw | Should -Match 'Default Guide'
        $reports.PlanRaw | Should -Not -Match 'Local Guide'
        Assert-NoPrivateConfigurationData -Text @($reports.SummaryRaw, $reports.PlanRaw)
    }

    It 'uses a valid local override when it is the only available user-owned choice' {
        $root = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'local-override' -DefaultSources @(
            @{ name = 'Default Guide'; priority = 10; path = 'default.xml'; enabled = $false; role = 'primary' }
        ) -CreateLocal -LocalSources @(
            @{ name = 'Local Guide'; priority = 10; path = 'local.xml'; enabled = $false; role = 'primary' }
        )

        & $script:BuildLineupPath -Root $root
        $reports = Get-BuildReports -Root $root

        $reports.Summary.EPGConfigSource | Should -Be 'LocalOverride'
        $reports.Summary.EPGSources | Should -Be 1
        $reports.PlanRaw | Should -Match 'EPG configuration: LocalOverride'
        $reports.PlanRaw | Should -Match 'Local Guide'
        $reports.PlanRaw | Should -Not -Match 'Default Guide'
    }

    It 'prefers the local override when both local and default files exist' {
        $root = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'local-wins' -DefaultSources @(
            @{ name = 'Tracked Guide'; priority = 10; path = 'tracked.xml'; enabled = $false; role = 'primary' }
        ) -CreateLocal -LocalSources @(
            @{ name = 'User Guide'; priority = 10; path = 'user.xml'; enabled = $false; role = 'primary' }
        )

        Test-Path -LiteralPath (Join-Path $root 'data\epg\epg_sources.json') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'data\epg\epg_sources.local.json') -PathType Leaf | Should -BeTrue
        & $script:BuildLineupPath -Root $root
        $reports = Get-BuildReports -Root $root

        $reports.Summary.EPGConfigSource | Should -Be 'LocalOverride'
        $reports.PlanRaw | Should -Match 'User Guide'
        $reports.PlanRaw | Should -Not -Match 'Tracked Guide'
    }

    It 'fails closed on malformed local JSON without falling back to the default' {
        $root = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'malformed-local' -DefaultSources @(
            @{ name = 'Default Guide'; priority = 10; path = 'default.xml'; enabled = $false; role = 'primary' }
        ) -CreateLocal -LocalRaw '{ "epg_sources": ['

        $message = Invoke-BuildFailure -Root $root

        $message | Should -Match 'Local EPG configuration is invalid'
        $message | Should -Not -Match 'Default Guide|epg_sources\.json|https?://|ACCOUNT_ID|API_TOKEN'
        Test-Path -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -PathType Leaf | Should -BeFalse
    }

    It 'fails closed on schema-invalid local configuration without falling back to the default' {
        $root = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'schema-invalid-local' -DefaultSources @(
            @{ name = 'Default Guide'; priority = 10; path = 'default.xml'; enabled = $false; role = 'primary' }
        ) -CreateLocal -LocalRaw '{"epg_sources":[{"name":"Invalid Guide","priority":"not-an-integer","path":"invalid.xml","enabled":false,"role":"primary"}]}'

        $message = Invoke-BuildFailure -Root $root

        $message | Should -Match 'Local EPG configuration is invalid'
        $message | Should -Not -Match 'Default Guide|invalid.xml|epg_sources\.json|https?://|ACCOUNT_ID|API_TOKEN'
        Test-Path -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -PathType Leaf | Should -BeFalse
    }

    It 'does not fall back when the local override is empty' {
        $root = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'empty-local' -DefaultSources @(
            @{ name = 'Default Guide'; priority = 10; path = 'default.xml'; enabled = $false; role = 'primary' }
        ) -CreateLocal -LocalSources @()

        $message = Invoke-BuildFailure -Root $root

        $message | Should -Match 'Local EPG configuration is invalid'
        $message | Should -Not -Match 'Default Guide|epg_sources\.json|https?://|ACCOUNT_ID|API_TOKEN'
        Test-Path -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -PathType Leaf | Should -BeFalse
    }

    It 'applies the existing reader policy to an unsupported local source without falling back' {
        $root = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'unsupported-local' -DefaultSources @(
            @{ name = 'Default Guide'; priority = 10; path = 'default.xml'; enabled = $false; role = 'primary' }
        ) -CreateLocal -LocalSources @(
            @{ name = 'Unsupported Guide'; priority = 10; url = 'ftp://example.invalid/guide.xml'; enabled = $false; role = 'primary' }
        )

        $message = Invoke-BuildFailure -Root $root

        $message | Should -Match 'unsupported URL'
        $message | Should -Not -Match 'ftp://|example\.invalid|Default Guide|epg_sources\.json|ACCOUNT_ID|API_TOKEN'
        Test-Path -LiteralPath (Join-Path $root 'output\reports\build-summary.json') -PathType Leaf | Should -BeFalse
    }

    It 'keeps the safe source label stable across repeated default and local selections' {
        $defaultRoot = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'repeat-default' -DefaultSources @(
            @{ name = 'Default Guide'; priority = 10; path = 'default.xml'; enabled = $false; role = 'primary' }
        )
        & $script:BuildLineupPath -Root $defaultRoot
        $defaultFirst = (Get-BuildReports -Root $defaultRoot).Summary.EPGConfigSource
        & $script:BuildLineupPath -Root $defaultRoot
        $defaultSecond = (Get-BuildReports -Root $defaultRoot).Summary.EPGConfigSource

        $localRoot = New-EpgSelectionFixture -BaseRoot $TestDrive -Name 'repeat-local' -DefaultSources @(
            @{ name = 'Default Guide'; priority = 10; path = 'default.xml'; enabled = $false; role = 'primary' }
        ) -CreateLocal -LocalSources @(
            @{ name = 'Local Guide'; priority = 10; path = 'local.xml'; enabled = $false; role = 'primary' }
        )
        & $script:BuildLineupPath -Root $localRoot
        $localFirst = (Get-BuildReports -Root $localRoot).Summary.EPGConfigSource
        & $script:BuildLineupPath -Root $localRoot
        $localSecond = (Get-BuildReports -Root $localRoot).Summary.EPGConfigSource

        $defaultFirst | Should -Be 'Default'
        $defaultSecond | Should -Be $defaultFirst
        $localFirst | Should -Be 'LocalOverride'
        $localSecond | Should -Be $localFirst
    }
}
