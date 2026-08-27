BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildLineupPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    $script:Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

    function Write-Utf8Fixture {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Content
        )
        $parent = Split-Path -Parent $Path
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8Strict)
    }

    function New-DeterministicComparisonRoot {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$PlaylistRelativePath,
            [Parameter(Mandatory)][string]$AlphaGuideRelativePath,
            [Parameter(Mandatory)][string]$ZetaGuideRelativePath,
            [switch]$ReverseEpgSourceOrder
        )

        $root = Join-Path $TestDrive $Name
        $data = Join-Path $root 'data'
        $playlistPath = Join-Path $data ('playlists\' + ($PlaylistRelativePath -replace '/', '\'))
        $alphaGuidePath = Join-Path $data ('epg\' + ($AlphaGuideRelativePath -replace '/', '\'))
        $zetaGuidePath = Join-Path $data ('epg\' + ($ZetaGuideRelativePath -replace '/', '\'))

        $playlist = @'
#EXTM3U
#EXTINF:-1 tvg-id="alpha.us" tvg-name="Alpha" group-title="News",Alpha
https://example.invalid/live/alpha
#EXTINF:-1 tvg-id="zeta.us" tvg-name="Zeta" group-title="News",Zeta
https://example.invalid/live/zeta
'@
        $alphaGuide = @'
<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="deterministic-comparison">
  <channel id="alpha.us"><display-name>Alpha</display-name></channel>
  <programme start="20260824080000 +0000" stop="20260824090000 +0000" channel="alpha.us"><title>Alpha Morning</title></programme>
</tv>
'@
        $zetaGuide = @'
<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="deterministic-comparison">
  <channel id="zeta.us"><display-name>Zeta</display-name></channel>
  <programme start="20260824090000 +0000" stop="20260824100000 +0000" channel="zeta.us"><title>Zeta Morning</title></programme>
</tv>
'@

        Write-Utf8Fixture -Path $playlistPath -Content $playlist
        Write-Utf8Fixture -Path $alphaGuidePath -Content $alphaGuide
        Write-Utf8Fixture -Path $zetaGuidePath -Content $zetaGuide

        $epgSources = @(
            @{ name = 'Alpha Guide'; priority = 10; path = $AlphaGuideRelativePath; enabled = $true; role = 'primary' }
            @{ name = 'Zeta Guide'; priority = 10; path = $ZetaGuideRelativePath; enabled = $true; role = 'primary' }
        )
        if ($ReverseEpgSourceOrder) {
            [array]::Reverse($epgSources)
        }

        Write-Utf8Fixture -Path (Join-Path $data 'providers\mybunny.json') -Content (
            @{ provider = 'deterministic-fixture'; sources = @(
                    @{ name = 'Playlist'; group = 'News'; url = 'https://example.invalid/fixture'; enabled = $true; local_playlist = ('data/playlists/' + $PlaylistRelativePath) }
                ) } | ConvertTo-Json -Depth 10)
        Write-Utf8Fixture -Path (Join-Path $data 'epg\epg_sources.json') -Content (
            @{ epg_sources = $epgSources } | ConvertTo-Json -Depth 10)
        Write-Utf8Fixture -Path (Join-Path $data 'lineup\locals.json') -Content (
            @{ locals = @() } | ConvertTo-Json -Depth 10)
        Write-Utf8Fixture -Path (Join-Path $data 'lineup\numbering_blocks.json') -Content (
            @{ blocks = @(@{ start = 1; end = 9999; category = 'News'; notes = 'deterministic comparison' }) } | ConvertTo-Json -Depth 10)
        Write-Utf8Fixture -Path (Join-Path $data 'rules\aliases.json') -Content (
            @{ aliases = @() } | ConvertTo-Json -Depth 10)

        return $root
    }

    function Get-DeterministicBuildSnapshot {
        param([Parameter(Mandatory)][string]$Root)

        & $script:BuildLineupPath -Root $Root | Out-Null
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw | ConvertFrom-Json
        $namespace = Join-Path $Root ($summary.CandidateNamespacePath -replace '/', '\')
        $artifactNames = @('merged.m3u', 'merged.xml', 'lineup-change-review.json', 'lineup-change-review.md', 'manifest.json')
        $artifacts = [ordered]@{}
        foreach ($name in $artifactNames) {
            $path = Join-Path $namespace $name
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $artifacts[$name] = [ordered]@{
                Bytes = $bytes
                Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }

        $manifest = $script:Utf8Strict.GetString($artifacts['manifest.json'].Bytes) | ConvertFrom-Json
        [pscustomobject]@{
            Summary = $summary
            Namespace = $namespace
            NamespaceIdentity = Split-Path -Leaf $namespace
            Artifacts = $artifacts
            Manifest = $manifest
            ManifestText = $script:Utf8Strict.GetString($artifacts['manifest.json'].Bytes)
            ReviewJsonText = $script:Utf8Strict.GetString($artifacts['lineup-change-review.json'].Bytes)
            ReviewMarkdownText = $script:Utf8Strict.GetString($artifacts['lineup-change-review.md'].Bytes)
        }
    }

    function Assert-NoUtf8Bom {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $Bytes.Length | Should -BeGreaterThan 3
        $Bytes[0] | Should -Not -Be ([byte]0xEF)
        $Bytes[1] | Should -Not -Be ([byte]0xBB)
        $Bytes[2] | Should -Not -Be ([byte]0xBF)
    }
}

Describe 'candidate build determinism across source order and fixture paths' {
    It 'keeps identity, guide evidence, candidate bytes, manifest, namespace, and review encoding identical' {
        $firstRoot = New-DeterministicComparisonRoot `
            -Name 'deterministic-first' `
            -PlaylistRelativePath 'one/playlist.m3u' `
            -AlphaGuideRelativePath 'guides/alpha.xml' `
            -ZetaGuideRelativePath 'guides/zeta.xml'
        $secondRoot = New-DeterministicComparisonRoot `
            -Name 'deterministic-second' `
            -PlaylistRelativePath 'renamed/source.m3u' `
            -AlphaGuideRelativePath 'alternate/alpha-guide.xml' `
            -ZetaGuideRelativePath 'alternate/zeta-guide.xml' `
            -ReverseEpgSourceOrder

        $first = Get-DeterministicBuildSnapshot -Root $firstRoot
        $second = Get-DeterministicBuildSnapshot -Root $secondRoot

        $second.Summary.CandidateBuildIdentity | Should -Be $first.Summary.CandidateBuildIdentity
        $second.Summary.CandidateManifestHash | Should -Be $first.Summary.CandidateManifestHash
        $second.Summary.CandidateNamespacePath | Should -Be $first.Summary.CandidateNamespacePath
        $second.NamespaceIdentity | Should -Be $first.NamespaceIdentity

        $firstGuideDigests = @($first.Manifest.GuideOccurrences | ForEach-Object GuideCandidateEvidenceDigest)
        $secondGuideDigests = @($second.Manifest.GuideOccurrences | ForEach-Object GuideCandidateEvidenceDigest)
        $secondGuideDigests | Should -Be $firstGuideDigests
        $second.Manifest.GuideOccurrences | ConvertTo-Json -Depth 10 -Compress | Should -Be ($first.Manifest.GuideOccurrences | ConvertTo-Json -Depth 10 -Compress)

        foreach ($name in @('merged.m3u', 'merged.xml', 'lineup-change-review.json', 'lineup-change-review.md', 'manifest.json')) {
            [Convert]::ToBase64String($second.Artifacts[$name].Bytes) | Should -Be ([Convert]::ToBase64String($first.Artifacts[$name].Bytes))
            $second.Artifacts[$name].Sha256 | Should -Be $first.Artifacts[$name].Sha256
        }
        $second.Summary.M3USha256 | Should -Be $first.Summary.M3USha256
        $second.Summary.XMLTVSha256 | Should -Be $first.Summary.XMLTVSha256
        @($second.Manifest.ArtifactRecords | ForEach-Object ContentHash) | Should -Be @($first.Manifest.ArtifactRecords | ForEach-Object ContentHash)

        $reviewJsonBytes = $first.Artifacts['lineup-change-review.json'].Bytes
        $reviewMarkdownBytes = $first.Artifacts['lineup-change-review.md'].Bytes
        Assert-NoUtf8Bom -Bytes $reviewJsonBytes
        Assert-NoUtf8Bom -Bytes $reviewMarkdownBytes
        $first.ReviewJsonText.Contains("`r") | Should -BeFalse
        $first.ReviewJsonText.Contains("`n") | Should -BeFalse
        $first.ReviewMarkdownText.EndsWith("`n", [System.StringComparison]::Ordinal) | Should -BeTrue
        $first.ReviewMarkdownText.EndsWith("`r`n", [System.StringComparison]::Ordinal) | Should -BeFalse
        $first.ReviewMarkdownText.Contains("`r") | Should -BeFalse
        $expectedReviewMarkdown = @(
            '# ChannelForge Lineup Change Review'
            ''
            "Build identity: $($first.Summary.CandidateBuildIdentity)"
            'Exact bindings: 2'
            'Unbound M3U channels: 0'
            'Review-needed identities: 0'
            'XMLTV-only channels: 0'
            ''
            'This is a candidate-only report. Accepted state and public merged artifacts are unchanged.'
            ''
        ) -join "`n"
        $first.ReviewMarkdownText | Should -Be $expectedReviewMarkdown

        $review = $first.ReviewJsonText | ConvertFrom-Json
        @($review.PSObject.Properties.Name) | Should -Be @(
            'Version', 'BuildIdentity', 'ReviewRecords', 'M3UIdentityCollisions',
            'RawM3UOccurrenceCount', 'RawXMLTVOccurrenceCount', 'ExactBindingCount',
            'UnboundCount', 'ReviewNeededCount', 'XMLTVOnlyCount'
        )
        $review.Version | Should -Be 'blocker-2-contract/v7'
        $review.BuildIdentity | Should -Be $first.Summary.CandidateBuildIdentity

        $first.ManifestText | Should -Be $second.ManifestText
        [Convert]::ToBase64String($first.Artifacts['manifest.json'].Bytes) | Should -Be ([Convert]::ToBase64String($second.Artifacts['manifest.json'].Bytes))
    }
}
