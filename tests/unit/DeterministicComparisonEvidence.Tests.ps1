BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildLineupPath = Join-Path $script:RepoRoot 'scripts\Build-Lineup.ps1'
    $script:Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    function Get-IndependentSha256Hex {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }

    function Get-IndependentDomainHashHex {
        param(
            [Parameter(Mandatory)][string]$Domain,
            [Parameter(Mandatory)][byte[]]$CanonicalBytes
        )
        [byte[]]$domainBytes = $script:Utf8Strict.GetBytes($Domain)
        [byte[]]$payload = [byte[]]::new($domainBytes.Length + 1 + $CanonicalBytes.Length)
        [System.Buffer]::BlockCopy($domainBytes, 0, $payload, 0, $domainBytes.Length)
        $payload[$domainBytes.Length] = 0
        [System.Buffer]::BlockCopy($CanonicalBytes, 0, $payload, $domainBytes.Length + 1, $CanonicalBytes.Length)
        return Get-IndependentSha256Hex -Bytes $payload
    }


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

        $playlist = @(
            '#EXTM3U'
            '#EXTINF:-1 tvg-id="alpha.us" tvg-name="Alpha" group-title="News",Alpha'
            'https://example.invalid/live/alpha'
            '#EXTINF:-1 tvg-id="zeta.us" tvg-name="Zeta" group-title="News",Zeta'
            'https://example.invalid/live/zeta'
        ) -join "`n"
        $playlist += "`n"

        $alphaGuide = @(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<tv generator-info-name="deterministic-comparison">'
            '  <channel id="alpha.us"><display-name>Alpha</display-name></channel>'
            '  <programme start="20260824080000 +0000" stop="20260824090000 +0000" channel="alpha.us"><title>Alpha Morning</title></programme>'
            '</tv>'
        ) -join "`n"
        $alphaGuide += "`n"

        $zetaGuide = @(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<tv generator-info-name="deterministic-comparison">'
            '  <channel id="zeta.us"><display-name>Zeta</display-name></channel>'
            '  <programme start="20260824090000 +0000" stop="20260824100000 +0000" channel="zeta.us"><title>Zeta Morning</title></programme>'
            '</tv>'
        ) -join "`n"
        $zetaGuide += "`n"

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

        $identityInputPath = Join-Path $Root 'build-identity-input.json'
        $previousIdentityInputPath = [System.Environment]::GetEnvironmentVariable('CHANNELFORGE_BUILD_IDENTITY_INPUT_OUTPUT', 'Process')
        try {
            $env:CHANNELFORGE_BUILD_IDENTITY_INPUT_OUTPUT = $identityInputPath
            & $script:BuildLineupPath -Root $Root | Out-Null
        }
        finally {
            if ($null -eq $previousIdentityInputPath) {
                Remove-Item Env:CHANNELFORGE_BUILD_IDENTITY_INPUT_OUTPUT -ErrorAction SilentlyContinue
            }
            else {
                $env:CHANNELFORGE_BUILD_IDENTITY_INPUT_OUTPUT = $previousIdentityInputPath
            }
        }
        Test-Path -LiteralPath $identityInputPath -PathType Leaf | Should -BeTrue
        $identityInputBytes = [System.IO.File]::ReadAllBytes($identityInputPath)
        $identityInput = $script:Utf8Strict.GetString($identityInputBytes) | ConvertFrom-Json
        $identityCanonicalBytes = [System.Convert]::FromBase64String([string]$identityInput.CanonicalUtf8Base64)
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
        $manifestRecords = @($manifest.ArtifactRecords | ForEach-Object {
                [pscustomobject][ordered]@{
                    Role = [string]$_.Role
                    RelativePath = [string]$_.RelativePath
                    Status = [string]$_.Status
                    ByteLength = [int64]$_.ByteLength
                    ContentDomain = [string]$_.ContentDomain
                    ContentHash = [string]$_.ContentHash
                }
            })
        [pscustomobject]@{
            Summary = $summary
            Namespace = $namespace
            NamespaceIdentity = Split-Path -Leaf $namespace
            Artifacts = $artifacts
            Manifest = $manifest
            ArtifactRecords = $manifestRecords
            BuildIdentityInput = $identityInput
            BuildIdentityInputBytes = $identityInputBytes
            BuildIdentityInputCanonicalBytes = $identityCanonicalBytes
            ManifestByteLength = [int64]$artifacts['manifest.json'].Bytes.Length
            ManifestSha256 = [string]$artifacts['manifest.json'].Sha256
            ManifestHash = [string]$manifest.CandidateManifestHash
            ManifestText = $script:Utf8Strict.GetString($artifacts['manifest.json'].Bytes)
            ReviewJsonText = $script:Utf8Strict.GetString($artifacts['lineup-change-review.json'].Bytes)
            ReviewMarkdownText = $script:Utf8Strict.GetString($artifacts['lineup-change-review.md'].Bytes)
        }
    }

    function Get-ReviewEncodingProjection {
        param([Parameter(Mandatory)]$Snapshot)

        $jsonBytes = $Snapshot.Artifacts['lineup-change-review.json'].Bytes
        $markdownBytes = $Snapshot.Artifacts['lineup-change-review.md'].Bytes
        [pscustomobject][ordered]@{
            JsonByteLength = [int64]$jsonBytes.Length
            MarkdownByteLength = [int64]$markdownBytes.Length
            JsonHasUtf8Bom = ($jsonBytes.Length -ge 3 -and
                $jsonBytes[0] -eq [byte]0xEF -and
                $jsonBytes[1] -eq [byte]0xBB -and
                $jsonBytes[2] -eq [byte]0xBF)
            MarkdownHasUtf8Bom = ($markdownBytes.Length -ge 3 -and
                $markdownBytes[0] -eq [byte]0xEF -and
                $markdownBytes[1] -eq [byte]0xBB -and
                $markdownBytes[2] -eq [byte]0xBF)
            JsonHasCR = $Snapshot.ReviewJsonText.Contains("`r")
            JsonHasLF = $Snapshot.ReviewJsonText.Contains("`n")
            MarkdownHasCR = $Snapshot.ReviewMarkdownText.Contains("`r")
            MarkdownEndsWithLF = $Snapshot.ReviewMarkdownText.EndsWith("`n", [System.StringComparison]::Ordinal)
            MarkdownEndsWithCRLF = $Snapshot.ReviewMarkdownText.EndsWith("`r`n", [System.StringComparison]::Ordinal)
            JsonPropertyOrder = @(
                ($Snapshot.ReviewJsonText | ConvertFrom-Json).PSObject.Properties.Name
            )
        }
    }

    function Assert-NoUtf8Bom {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $Bytes.Length | Should -BeGreaterThan 3
        $Bytes[0] | Should -Not -Be ([byte]0xEF)
        $Bytes[1] | Should -Not -Be ([byte]0xBB)
        $Bytes[2] | Should -Not -Be ([byte]0xBF)
    }

    function Get-DeterministicEvidenceProjection {
        param([Parameter(Mandatory)]$Snapshot)

        $reviewRecords = @($Snapshot.ArtifactRecords | Where-Object {
                $_.Role -in @('CandidateReviewJSON', 'CandidateReviewMarkdown')
            })
        [pscustomobject][ordered]@{
            BuildIdentity = [string]$Snapshot.Summary.CandidateBuildIdentity
            BuildIdentityInput = $Snapshot.BuildIdentityInput
            GuideEvidenceDigests = @($Snapshot.Manifest.GuideOccurrences |
                ForEach-Object { [string]$_.GuideCandidateEvidenceDigest })
            ArtifactRecords = $Snapshot.ArtifactRecords
            ReviewDomainHashes = [ordered]@{
                Json = [string]($reviewRecords | Where-Object Role -eq 'CandidateReviewJSON').ContentHash
                Markdown = [string]($reviewRecords | Where-Object Role -eq 'CandidateReviewMarkdown').ContentHash
            }
            ManifestByteLength = $Snapshot.ManifestByteLength
            ManifestSha256 = $Snapshot.ManifestSha256
            ManifestHash = $Snapshot.ManifestHash
            NamespaceIdentity = [string]$Snapshot.NamespaceIdentity
            ReviewEncoding = Get-ReviewEncodingProjection -Snapshot $Snapshot
        }
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
        $identityA = $first.BuildIdentityInput
        $identityB = $second.BuildIdentityInput
        $identityA.Version | Should -BeExactly 'candidate-build-identity-input/v1'
        $identityA.Domain | Should -BeExactly 'candidate-manifest/v2'
        $identityA.CanonicalUtf8ByteLength | Should -Be ([int64]$first.BuildIdentityInputCanonicalBytes.Length)
        $identityB.CanonicalUtf8ByteLength | Should -Be ([int64]$second.BuildIdentityInputCanonicalBytes.Length)
        $identityA.CanonicalUtf8Base64 | Should -Be $identityB.CanonicalUtf8Base64
        [Convert]::ToBase64String($first.BuildIdentityInputCanonicalBytes) | Should -Be $identityA.CanonicalUtf8Base64
        [Convert]::ToBase64String($second.BuildIdentityInputCanonicalBytes) | Should -Be $identityB.CanonicalUtf8Base64
        $identityA.DirectSha256 | Should -Be (Get-IndependentSha256Hex -Bytes $first.BuildIdentityInputCanonicalBytes)
        $identityB.DirectSha256 | Should -Be (Get-IndependentSha256Hex -Bytes $second.BuildIdentityInputCanonicalBytes)
        $identityA.BuildIdentity | Should -Be $first.Summary.CandidateBuildIdentity
        $identityB.BuildIdentity | Should -Be $second.Summary.CandidateBuildIdentity
        $identityA.BuildIdentity | Should -Be (Get-IndependentDomainHashHex -Domain $identityA.Domain -CanonicalBytes $first.BuildIdentityInputCanonicalBytes)
        $identityB.BuildIdentity | Should -Be (Get-IndependentDomainHashHex -Domain $identityB.Domain -CanonicalBytes $second.BuildIdentityInputCanonicalBytes)
        $identityB.Fields | ConvertTo-Json -Depth 10 -Compress | Should -Be ($identityA.Fields | ConvertTo-Json -Depth 10 -Compress)
        $identityA.InputArtifactHashes | ConvertTo-Json -Depth 10 -Compress | Should -Be ($first.Manifest.InputArtifactHashes | ConvertTo-Json -Depth 10 -Compress)
        $identityB.InputArtifactHashes | ConvertTo-Json -Depth 10 -Compress | Should -Be ($second.Manifest.InputArtifactHashes | ConvertTo-Json -Depth 10 -Compress)
        @($identityA.Fields.PSObject.Properties.Name) | Should -Be @(
            'ContractVersion', 'IdentityRulesVersion', 'M3UParserContractVersion',
            'XMLTVParserContractVersion', 'M3USerializerVersion',
            'XMLTVSerializerVersion', 'GuideBindingContractVersion',
            'SelectedLogicalSourceIds', 'InputArtifactHashes'
        )
        @($identityA.InputArtifactHashes | ForEach-Object ArtifactHash) | Should -Be @(
            '492bb3208b87e7e1dee61f705d48a6b017c82fe4a811fd95a062fdee708844f7',
            '878f964fd71a5a309ec19821e3efe84b011a216b7ae700103e172fbd2376fc80',
            '9d537b6f00459798b141c1153dde167a274f097bce8fafdf49fbf89d887cbbb0'
        )

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
        $first.ArtifactRecords | Should -HaveCount 4
        foreach ($record in $first.ArtifactRecords) {
            $secondRecord = @($second.ArtifactRecords | Where-Object Role -eq $record.Role)[0]
            $secondRecord.RelativePath | Should -Be $record.RelativePath
            $secondRecord.Status | Should -Be 'Generated'
            $record.ByteLength | Should -Be ([int64]$first.Artifacts[$record.RelativePath].Bytes.Length)
            $record.ContentHash | Should -Match '^[0-9a-f]{64}$'
            $secondRecord.ByteLength | Should -Be $record.ByteLength
            $secondRecord.ContentDomain | Should -Be $record.ContentDomain
            $secondRecord.ContentHash | Should -Be $record.ContentHash
        }
        $first.ManifestHash | Should -Be $first.Summary.CandidateManifestHash
        $second.ManifestHash | Should -Be $second.Summary.CandidateManifestHash
        $second.ManifestHash | Should -Be $first.ManifestHash
        $first.ManifestByteLength | Should -Be ([int64]$first.Artifacts['manifest.json'].Bytes.Length)
        $second.ManifestByteLength | Should -Be $first.ManifestByteLength
        $second.ManifestSha256 | Should -Be $first.ManifestSha256
        $first.ManifestSha256 | Should -Match '^[0-9a-f]{64}$'
        $first.ManifestHash | Should -Match '^[0-9a-f]{64}$'

        $firstEncoding = Get-ReviewEncodingProjection -Snapshot $first
        $secondEncoding = Get-ReviewEncodingProjection -Snapshot $second
        $secondEncoding | ConvertTo-Json -Depth 10 -Compress | Should -Be ($firstEncoding | ConvertTo-Json -Depth 10 -Compress)
        $firstEncoding.JsonHasUtf8Bom | Should -BeFalse
        $firstEncoding.MarkdownHasUtf8Bom | Should -BeFalse
        $firstEncoding.JsonHasCR | Should -BeFalse
        $firstEncoding.JsonHasLF | Should -BeFalse
        $firstEncoding.MarkdownHasCR | Should -BeFalse
        $firstEncoding.MarkdownEndsWithLF | Should -BeTrue
        $firstEncoding.MarkdownEndsWithCRLF | Should -BeFalse
        [Convert]::ToBase64String($script:Utf8Strict.GetBytes($first.ReviewJsonText)) |
            Should -Be ([Convert]::ToBase64String($first.Artifacts['lineup-change-review.json'].Bytes))
        [Convert]::ToBase64String($script:Utf8Strict.GetBytes($first.ReviewMarkdownText)) |
            Should -Be ([Convert]::ToBase64String($first.Artifacts['lineup-change-review.md'].Bytes))

        @($firstEncoding.JsonPropertyOrder) | Should -Be @(
            'Version', 'BuildIdentity', 'ReviewRecords', 'M3UIdentityCollisions',
            'RawM3UOccurrenceCount', 'RawXMLTVOccurrenceCount', 'ExactBindingCount',
            'UnboundCount', 'ReviewNeededCount', 'XMLTVOnlyCount'
        )

        $evidenceA = Get-DeterministicEvidenceProjection -Snapshot $first
        $evidenceB = Get-DeterministicEvidenceProjection -Snapshot $second
        Write-Host ('BUILD-A-EVIDENCE ' + ($evidenceA | ConvertTo-Json -Depth 10 -Compress))
        Write-Host ('BUILD-B-EVIDENCE ' + ($evidenceB | ConvertTo-Json -Depth 10 -Compress))
        $evidenceB | ConvertTo-Json -Depth 10 -Compress | Should -Be ($evidenceA | ConvertTo-Json -Depth 10 -Compress)
        if (-not [string]::IsNullOrWhiteSpace($env:CHANNELFORGE_DETERMINISTIC_EVIDENCE_OUTPUT)) {
            $capture = [ordered]@{
                BuildA = $evidenceA
                BuildB = $evidenceB
            } | ConvertTo-Json -Depth 10
            $captureParent = Split-Path -Parent $env:CHANNELFORGE_DETERMINISTIC_EVIDENCE_OUTPUT
            New-Item -ItemType Directory -Force -Path $captureParent | Out-Null
            [System.IO.File]::WriteAllText(
                $env:CHANNELFORGE_DETERMINISTIC_EVIDENCE_OUTPUT,
                $capture,
                $script:Utf8Strict
            )
        }
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
    It 'materializes explicit LF fixture bytes independent of checkout EOL' {
        $root = New-DeterministicComparisonRoot -Name 'fixture-byte-portability' -PlaylistRelativePath 'playlist.m3u' -AlphaGuideRelativePath 'alpha.xml' -ZetaGuideRelativePath 'zeta.xml'
        $fixtureExpectations = @(
            @{ Name = 'data/playlists/playlist.m3u'; Length = 216; Sha256 = '960717803a0119ab2d2674e026cfaf7f3071405b78bf7004302a8954b840f306' }
            @{ Name = 'data/epg/alpha.xml'; Length = 297; Sha256 = 'b7ab0c30543f1870d6dc134591ba8510f110c064155bdef3da842bb5680d8c3a' }
            @{ Name = 'data/epg/zeta.xml'; Length = 293; Sha256 = '3f34ec55e9a87a71c43e2c4841b2765b30ac8d470648da4f5ad49b288dc923c1' }
        )
        foreach ($item in $fixtureExpectations) {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $root $item.Name))
            (Get-FileHash -LiteralPath (Join-Path $root $item.Name) -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $item.Sha256
            $bytes | Where-Object { $_ -eq 13 } | Should -BeNullOrEmpty
            $bytes[-1] | Should -Be 10
        }
    }
}
