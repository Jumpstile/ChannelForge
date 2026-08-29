BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:PlaylistPath = Join-Path $script:RepoRoot 'tests/fixtures/identity-binding/playlist.m3u'
    $script:GuidePath = Join-Path $script:RepoRoot 'tests/fixtures/identity-binding/guide.xml'
    $script:BuildCandidatePath = Join-Path $script:RepoRoot 'scripts/Build-Candidate.ps1'
    $script:V7 = 'blocker-2-contract/v7'
    $script:V8 = 'blocker-2-contract/v8'
    Import-Module (Join-Path $script:RepoRoot 'src/ChannelForge/ChannelForge.psd1') -Global -Force
    . (Join-Path $script:RepoRoot 'src/ChannelForge/Private/ConvertTo-ChannelForgeCanonicalJson.ps1')
    . (Join-Path $script:RepoRoot 'src/ChannelForge/Private/Get-ChannelForgeDomainHash.ps1')
    . (Join-Path $script:RepoRoot 'src/ChannelForge/Private/Get-ChannelForgeRawM3UProjection.ps1')
    . (Join-Path $script:RepoRoot 'src/ChannelForge/Private/Get-ChannelForgeRawXmltvProjection.ps1')
}

Describe 'Issue 110 CandidateContractVersion registry migration' {
    It 'propagates v8 through parser evidence and candidate projections' {
        $channels = @(Import-ChannelForgeM3UPlaylist -Path $script:PlaylistPath -Provider 'fixture-provider' -Playlist 'identity-fixture' -CandidateContractVersion $script:V8)
        $programmes = @(Import-ChannelForgeXmltvSource -Path $script:GuidePath -SourceId 'fixture-guide' -CandidateContractVersion $script:V8)
        @($channels.RawM3UOccurrence.Version) | Should -Not -BeNullOrEmpty
        @($channels.RawM3UOccurrence.Version | Select-Object -Unique) | Should -Be @($script:V8)
        @($programmes[0].Evidence.RawChannelOccurrences.Version) | Should -Not -BeNullOrEmpty
        @($programmes[0].Evidence.RawProgrammeOccurrences.Version) | Should -Not -BeNullOrEmpty
        @($programmes[0].Evidence.RawChannelOccurrences.Version | Select-Object -Unique) | Should -Be @($script:V8)
        @($programmes[0].Evidence.RawProgrammeOccurrences.Version | Select-Object -Unique) | Should -Be @($script:V8)

        $rawM3U = @(Get-ChannelForgeRawM3UProjection -Channel $channels -LogicalSourceId 'm3u-source' -CandidateContractVersion $script:V8)
        $rawXMLTV = @(Get-ChannelForgeRawXmltvProjection -Programme $programmes -CandidateContractVersion $script:V8)
        @($rawM3U.Version | Select-Object -Unique) | Should -Be @($script:V8)
        @($rawXMLTV.Version | Select-Object -Unique) | Should -Be @($script:V8)
    }

    It 'fails closed when candidate inputs mix registry versions' {
        $channels = @(Import-ChannelForgeM3UPlaylist -Path $script:PlaylistPath -Provider 'fixture-provider' -Playlist 'identity-fixture' -CandidateContractVersion $script:V7)
        $rawM3U = @(Get-ChannelForgeRawM3UProjection -Channel $channels -LogicalSourceId 'm3u-source' -CandidateContractVersion $script:V7)
        $bytes = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`n")
        {
            & (Get-Module ChannelForge) {
                param($raw, $artifactBytes)
                ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences $raw -M3UBytes $artifactBytes -CandidateContractVersion 'blocker-2-contract/v8'
            } $rawM3U $bytes
        } | Should -Throw 'FAIL_CLOSED: mixed candidate versions in RawM3UOccurrences.'
    }

    It 'builds repeatable v8 candidate identity, manifest, review, and slices' {
        $firstRoot = Join-Path $TestDrive 'issue110-v8-first'
        $secondRoot = Join-Path $TestDrive 'issue110-v8-second'
        $first = & $script:BuildCandidatePath -Root $script:RepoRoot -M3UPath $script:PlaylistPath -XMLTVPath $script:GuidePath -OutputRoot $firstRoot -CandidateContractVersion $script:V8
        $second = & $script:BuildCandidatePath -Root $script:RepoRoot -M3UPath $script:PlaylistPath -XMLTVPath $script:GuidePath -OutputRoot $secondRoot -CandidateContractVersion $script:V8

        [string]$first.BuildIdentity | Should -BeExactly ([string]$second.BuildIdentity)
        [string]$first.CandidateManifestHash | Should -BeExactly ([string]$second.CandidateManifestHash)
        $firstManifest = Get-Content (Join-Path $first.CandidateDirectory 'manifest.json') -Raw | ConvertFrom-Json
        $secondManifest = Get-Content (Join-Path $second.CandidateDirectory 'manifest.json') -Raw | ConvertFrom-Json
        $firstReview = Get-Content (Join-Path $first.CandidateDirectory 'lineup-change-review.json') -Raw | ConvertFrom-Json
        [string]$firstManifest.Version | Should -BeExactly $script:V8
        [string]$firstManifest.ContractVersion | Should -BeExactly $script:V8
        [string]$firstReview.Version | Should -BeExactly $script:V8
        @($firstManifest.Entries | Where-Object { $null -ne $_.EntryOutputSlice.ByteOffset }).Count | Should -Be @($firstManifest.Entries).Count
        (Get-FileHash (Join-Path $first.CandidateDirectory 'merged.m3u')).Hash | Should -Be (Get-FileHash (Join-Path $second.CandidateDirectory 'merged.m3u')).Hash
        (Get-FileHash (Join-Path $first.CandidateDirectory 'merged.xml')).Hash | Should -Be (Get-FileHash (Join-Path $second.CandidateDirectory 'merged.xml')).Hash
        (Get-FileHash (Join-Path $first.CandidateDirectory 'manifest.json')).Hash | Should -Be (Get-FileHash (Join-Path $second.CandidateDirectory 'manifest.json')).Hash
        (Get-FileHash (Join-Path $first.CandidateDirectory 'lineup-change-review.json')).Hash | Should -Be (Get-FileHash (Join-Path $second.CandidateDirectory 'lineup-change-review.json')).Hash
        (ConvertTo-Json $firstManifest -Depth 100 -Compress) | Should -Be (ConvertTo-Json $secondManifest -Depth 100 -Compress)
    }
}
