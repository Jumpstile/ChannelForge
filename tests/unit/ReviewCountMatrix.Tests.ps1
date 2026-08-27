BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    $script:PlaylistFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\playlist.m3u'
    $script:GuideFixture = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\guide.xml'

    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\ConvertTo-ChannelForgeCanonicalJson.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeDomainHash.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeLogicalSourceId.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeRawM3UProjection.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeRawXmltvProjection.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\New-ChannelForgeCandidateManifest.ps1')

    function New-ReviewCountInputs {
        $channels = @(Import-ChannelForgeM3UPlaylist `
            -Path $script:PlaylistFixture `
            -Provider 'fixture-provider' `
            -Playlist 'identity-fixture')
        $programmes = @(Import-ChannelForgeXmltvSource `
            -Path $script:GuideFixture `
            -SourceId 'fixture-guide')

        # This second zeta record represents a raw duplicate retained for
        # evidence, while the identity result intentionally contains only the
        # post-dedup survivor set.
        $duplicate = New-ChannelForgeChannel `
            -Provider 'fixture-provider' `
            -Playlist 'identity-fixture' `
            -OriginalName 'Zeta' `
            -DisplayName 'Zeta Exact' `
            -TvgId 'zeta.us' `
            -Url 'https://example.invalid/live/zeta'
        $duplicate.IsDuplicate = $true
        $rawChannels = @($channels + $duplicate)

        $rawM3U = @(Get-ChannelForgeRawM3UProjection `
            -Channel $rawChannels `
            -LogicalSourceId 'm3u-source')
        $rawXmltv = @(Get-ChannelForgeRawXmltvProjection -Programme $programmes)
        $binding = Resolve-ChannelForgeM3UXmltvBinding `
            -Channel $channels `
            -Programme $programmes

        return [pscustomobject]@{
            RawM3U = $rawM3U
            RawXmltv = $rawXmltv
            Binding = $binding
        }
    }

    function New-ReviewCountBuildRoot {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive $Name
        $data = Join-Path $root 'data'
        $playlistDir = Join-Path $data 'playlists'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $data 'providers'), (Join-Path $data 'epg'),
            (Join-Path $data 'lineup'), (Join-Path $data 'rules'),
            $playlistDir | Out-Null

        Copy-Item -LiteralPath $script:PlaylistFixture -Destination (Join-Path $playlistDir 'playlist.m3u')
        Copy-Item -LiteralPath $script:GuideFixture -Destination (Join-Path $data 'epg\guide.xml')
        @{ provider = 'review-count-fixture'; sources = @(@{
                name = 'Playlist'; group = 'General'; url = 'https://example.invalid/fixture'; enabled = $true
                local_playlist = 'data/playlists/playlist.m3u'
            }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'providers\mybunny.json') -Encoding UTF8
        @{ epg_sources = @(@{
                name = 'Guide'; priority = 10; path = 'guide.xml'; enabled = $true; role = 'primary'
            }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $data 'epg\epg_sources.json') -Encoding UTF8
        @{ locals = @() } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'lineup\locals.json') -Encoding UTF8
        @{ blocks = @(@{ start = 1; end = 9999; category = 'General'; notes = 'review count fixture' }) } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $data 'lineup\numbering_blocks.json') -Encoding UTF8
        @{ aliases = @() } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $data 'rules\aliases.json') -Encoding UTF8
        return $root
    }

    function Get-CandidateArtifact {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$Name
        )
        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw |
            ConvertFrom-Json
        return Join-Path $Root (Join-Path ($summary.CandidateNamespacePath -replace '/', '\') $Name)
    }
}

Describe 'Frozen v7 candidate-manifest review counts' {
    It 'counts the pre-dedup raw M3U matrix and excludes RawProgramme records' {
        $input = New-ReviewCountInputs
        $manifest = ConvertTo-ChannelForgeCandidateManifest `
            -RawM3UOccurrences $input.RawM3U `
            -RawXmltvOccurrences $input.RawXmltv `
            -IdentityBindingResult $input.Binding `
            -SelectedSourceIds @('m3u-source', 'fixture-guide')

        # Six raw M3U occurrences include the duplicate; only five canonical
        # entries are emitted. XMLTV projection has five channels plus three
        # programmes, but the count is channels only.
        @($input.RawM3U).Count | Should -Be 6
        @($manifest.Manifest.Entries).Count | Should -Be 5
        @($input.RawXmltv).Count | Should -Be 8
        @($input.RawXmltv | Where-Object RawProgrammeChannelIdPresence).Count | Should -Be 3
        @($manifest.Manifest.RawProgrammes).Count | Should -Be 3
        $manifest.ReviewCounts.RawM3UOccurrenceCount | Should -Be 6
        $manifest.ReviewCounts.RawXMLTVOccurrenceCount | Should -Be 5
    }

    It 'reports each frozen v7 binding count category from the binding projection' {
        $input = New-ReviewCountInputs
        # Use the canonical survivor population for status categories; the
        # separate raw-count test above proves duplicate evidence is retained.
        $manifest = ConvertTo-ChannelForgeCandidateManifest `
            -RawM3UOccurrences @($input.RawM3U | Where-Object { -not $_.Channel.IsDuplicate }) `
            -RawXmltvOccurrences $input.RawXmltv `
            -IdentityBindingResult $input.Binding `
            -SelectedSourceIds @('m3u-source', 'fixture-guide')

        $manifest.ReviewCounts.ExactBindingCount | Should -Be 2
        $manifest.ReviewCounts.UnboundCount | Should -Be 2
        $manifest.ReviewCounts.ReviewNeededCount | Should -Be 1
        $manifest.ReviewCounts.XMLTVOnlyCount | Should -Be 3

        @($manifest.Manifest.BindingRecords | Where-Object BindingKind -eq 'M3U').Count | Should -Be 5
        @($manifest.Manifest.BindingRecords | Where-Object Status -eq 'ExactBound').Count | Should -Be 2
        @($manifest.Manifest.BindingRecords | Where-Object { $_.BindingKind -eq 'M3U' -and $_.Status -eq 'Unbound' }).Count | Should -Be 2
        @($manifest.Manifest.BindingRecords | Where-Object Status -eq 'ReviewNeeded').Count | Should -Be 1
        @($manifest.Manifest.BindingRecords | Where-Object BindingKind -eq 'XMLTVOnly').Count | Should -Be 3
    }

    It 'excludes RejectedXMLTV binding records from both unbound and XMLTV-only counts' {
        $input = New-ReviewCountInputs
        $manifest = ConvertTo-ChannelForgeCandidateManifest `
            -RawM3UOccurrences $input.RawM3U `
            -RawXmltvOccurrences $input.RawXmltv `
            -IdentityBindingResult $input.Binding `
            -SelectedSourceIds @('m3u-source', 'fixture-guide')
        $rejectedXmltv = [pscustomobject][ordered]@{
            BindingKind = 'RejectedXMLTV'
            Status = 'Unbound'
        }
        $projectionWithRejected = @($manifest.Manifest.BindingRecords) + $rejectedXmltv

        # Frozen-v7 count domains are intentionally disjoint: an unbound count
        # is M3U-kind only, while XMLTV-only count is XMLTVOnly-kind only.
        @($projectionWithRejected | Where-Object {
                $_.BindingKind -eq 'M3U' -and $_.Status -eq 'Unbound'
            }).Count | Should -Be $manifest.ReviewCounts.UnboundCount
        @($projectionWithRejected | Where-Object {
                $_.BindingKind -eq 'XMLTVOnly'
            }).Count | Should -Be $manifest.ReviewCounts.XMLTVOnlyCount
        @($projectionWithRejected | Where-Object BindingKind -eq 'RejectedXMLTV').Count | Should -Be 1
    }
}

Describe 'Build-Lineup frozen v7 review artifacts' {
    It 'shares every review count value between JSON and Markdown through the build path' {
        $root = New-ReviewCountBuildRoot -Name 'review-count-build'
        & $script:BuildPath -Root $root

        $reviewJsonPath = Get-CandidateArtifact -Root $root -Name 'lineup-change-review.json'
        $reviewMarkdownPath = Get-CandidateArtifact -Root $root -Name 'lineup-change-review.md'
        $reviewJson = Get-Content -LiteralPath $reviewJsonPath -Raw | ConvertFrom-Json
        $reviewMarkdown = Get-Content -LiteralPath $reviewMarkdownPath -Raw

        $expected = [ordered]@{
            ExactBindingCount = 2
            UnboundCount = 2
            ReviewNeededCount = 1
            XMLTVOnlyCount = 3
        }
        foreach ($name in $expected.Keys) {
            [int]$reviewJson.$name | Should -Be $expected[$name] -Because $name
        }
        $reviewMarkdown | Should -Match 'Exact bindings: 2'
        $reviewMarkdown | Should -Match 'Unbound M3U channels: 2'
        $reviewMarkdown | Should -Match 'Review-needed identities: 1'
        $reviewMarkdown | Should -Match 'XMLTV-only channels: 3'
        foreach ($name in $expected.Keys) {
            $reviewMarkdown | Should -Match ([regex]::Escape(([string]$expected[$name]))) -Because "$name value is present"
        }
    }
}
