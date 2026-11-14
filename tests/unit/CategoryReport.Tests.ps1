BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    # Builds a real candidate with the existing scripts\Build-Candidate.ps1 (the same
    # way CandidateNamespaceEvidence.Tests.ps1 does), then reports on it.
    $script:Root = Join-Path $TestDrive 'repo'
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Root 'state'), (Join-Path $script:Root 'output') | Out-Null
    $lines = @(
        '#EXTM3U'
        '#EXTINF:-1 tvg-id="wwe.us" tvg-name="WWE" group-title="Sports",WWE Network'
        'https://example.com/secret/wwe'
        '#EXTINF:-1 tvg-id="bally.us" tvg-name="Bally" group-title="Sports",Bally Plus'
        'https://example.com/secret/bally'
        '#EXTINF:-1 tvg-id="misc.us" tvg-name="Misc" group-title="Misc",Mystery Channel'
        'https://example.com/secret/misc'
        '#EXTINF:-1 tvg-id="ufc.us" tvg-name="UFC" group-title="Boxing",UFC Fight Pass'
        'https://example.com/secret/ufc'
    )
    $source = Join-Path $script:Root 'source.m3u'
    [IO.File]::WriteAllText($source, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    $built = & (Join-Path $script:RepoRoot 'scripts\Build-Candidate.ps1') -Root $script:Root -M3UPath $source -OutputRoot (Join-Path $script:Root 'output')
    $script:Candidate = [string]$built.CandidateDirectory
    $script:Hash = [string]$built.CandidateManifestHash
    $script:OverridePath = Join-Path $script:Root 'state\category-overrides.json'

    function Get-Report { Get-ChannelForgeCategoryReport -CandidateDirectory $script:Candidate -RepositoryRoot $script:Root }
    function Get-Row { param($Report, [string]$Name) @($Report.Rows | Where-Object { $_.DisplayName -eq $Name })[0] }
    function Get-CandidateSnapshot {
        @(Get-ChildItem -LiteralPath $script:Candidate -File | Sort-Object Name | ForEach-Object { "$($_.Name):$((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join '|'
    }
}

Describe 'Category report: what the owner sees' {
    BeforeEach {
        Remove-Item -LiteralPath $script:OverridePath -Force -ErrorAction SilentlyContinue
    }

    It 'explains each channel with a category, confidence and plain reason' {
        $report = Get-Report
        $wwe = Get-Row $report 'WWE Network'
        $wwe.Category | Should -Be 'wrestling'
        $wwe.Confidence | Should -Be 'high'
        $wwe.Reason | Should -BeLike '*WWE*'
        $wwe.Reason | Should -BeLike '*Sports*'

        $generic = Get-Row $report 'Bally Plus'
        $generic.Category | Should -Be 'other-sports'
        $generic.Confidence | Should -Be 'medium'
        $generic.Reason | Should -BeLike '*generic*'

        $none = Get-Row $report 'Mystery Channel'
        $none.Category | Should -BeNullOrEmpty
        $none.Confidence | Should -Be 'none'
        $none.Decision | Should -Be 'no-rule'

        $conflict = Get-Row $report 'UFC Fight Pass'
        $conflict.Category | Should -BeNullOrEmpty
        $conflict.Confidence | Should -Be 'none'
        $conflict.Decision | Should -Be 'conflict'
        $conflict.Reason | Should -BeLike '*mma*'
        $conflict.Reason | Should -BeLike '*boxing*'
    }

    It 'counts every channel and leaves the candidate untouched' {
        $before = Get-CandidateSnapshot
        $report = Get-Report
        $report.ChannelCount | Should -Be 4
        $report.Rows.Count | Should -Be 4
        Get-CandidateSnapshot | Should -Be $before
        & (Get-Module ChannelForge) { param($d, $h) Test-ChannelForgeCandidateNamespace -Directory $d -ManifestHash $h } $script:Candidate $script:Hash | Should -BeTrue
    }

    It 'saves a report with no stream address, byte-identical on a second run' {
        Get-Report | Out-Null
        $path = Join-Path $script:Root "output\category-reports\$($script:Hash).json"
        $first = [IO.File]::ReadAllBytes($path)
        Get-Report | Out-Null
        [IO.File]::ReadAllBytes($path) | Should -Be $first
        $text = [Text.Encoding]::UTF8.GetString($first)
        $text | Should -Not -Match 'https?://'
        $text | Should -Not -Match 'secret'
    }
}

Describe 'Category overrides: corrections the owner keeps' {
    BeforeEach {
        Remove-Item -LiteralPath $script:OverridePath -Force -ErrorAction SilentlyContinue
    }

    It 'applies a correction as high and keeps applying it on the next report' {
        $key = (Get-Row (Get-Report) 'Mystery Channel').ChannelKey
        Set-ChannelForgeCategoryOverride -ChannelKey $key -Category 'movies' -Name 'Mystery Channel' -RepositoryRoot $script:Root
        foreach ($run in 1..2) {
            $row = Get-Row (Get-Report) 'Mystery Channel'
            $row.Category | Should -Be 'movies'
            $row.Confidence | Should -Be 'high'
            $row.Decision | Should -Be 'override'
        }
    }

    It 'keeps a correction for a channel not in the candidate and lists it as stale' {
        $stale = 'a' * 64
        Set-ChannelForgeCategoryOverride -ChannelKey $stale -Category 'news' -Name 'Gone' -RepositoryRoot $script:Root
        $before = [IO.File]::ReadAllBytes($script:OverridePath)
        $report = Get-Report
        @($report.Overrides.Stale).Count | Should -Be 1
        $report.Overrides.Stale[0].Key | Should -Be $stale
        $report.Overrides.Stale[0].Category | Should -Be 'news'
        [IO.File]::ReadAllBytes($script:OverridePath) | Should -Be $before
    }

    It 'stops on a damaged overrides file and leaves it byte for byte' {
        [IO.File]::WriteAllText($script:OverridePath, '{ not json')
        $before = [IO.File]::ReadAllBytes($script:OverridePath)
        { Get-Report } | Should -Throw '*Nothing was written*'
        { Set-ChannelForgeCategoryOverride -ChannelKey ('b' * 64) -Category 'news' -RepositoryRoot $script:Root } | Should -Throw '*Nothing was written*'
        [IO.File]::ReadAllBytes($script:OverridePath) | Should -Be $before
    }
}
