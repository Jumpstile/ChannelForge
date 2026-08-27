BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildLineupPath = Join-Path $RepoRoot 'scripts\Build-Lineup.ps1'
    $script:FixturePlaylist = Join-Path $RepoRoot 'tests\fixtures\tiny.m3u'
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force

    function Get-InputArtifactHash {
        param([Parameter(Mandatory)][byte[]]$Bytes)

        $module = Get-Module ChannelForge
        return & $module {
            param([byte[]]$InputBytes)
            Get-ChannelForgeDomainHash -Domain 'input-m3u/v2' -Bytes $InputBytes
        } $Bytes
    }

    function New-MinimalArtifactHashRecord {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$ArtifactHash
        )

        return [pscustomobject][ordered]@{
            LogicalSourceId = ('1' * 64)
            ArtifactKind    = 'M3U'
            ArtifactHash    = $ArtifactHash
        }
    }

    function Invoke-MinimalCandidateManifest {
        param([Parameter(Mandatory)][object[]]$InputArtifactHashes)

        $arguments = @{
            RawM3UOccurrences     = @()
            M3UIdentityCollisions = @()
            M3UBytes              = [byte[]](0)
            IdentityBindingResult = $null
            XMLTVBytes            = $null
            InputArtifactHashes   = $InputArtifactHashes
            SelectedSourceIds     = @($InputArtifactHashes | ForEach-Object { [string]$_.LogicalSourceId })
        }
        $module = Get-Module ChannelForge
        return @(& $module {
                param([hashtable]$ManifestArguments)
                ConvertTo-ChannelForgeCandidateManifest @ManifestArguments
            } $arguments)
    }

    function New-BuildFixture {
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][object[]]$Sources,
            [switch]$IncludeLocalPlaylist
        )

        $dataDir = Join-Path $Root 'data'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $dataDir 'providers'),
            (Join-Path $dataDir 'epg'),
            (Join-Path $dataDir 'lineup'),
            (Join-Path $dataDir 'rules'),
            (Join-Path $dataDir 'playlists') | Out-Null

        if ($IncludeLocalPlaylist) {
            Copy-Item -LiteralPath $script:FixturePlaylist -Destination (Join-Path $dataDir 'playlists\local.m3u')
        }

        @{ provider = 'fixture-provider'; sources = $Sources } |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $dataDir 'providers\mybunny.json') -Encoding utf8NoBOM
        @{ epg_sources = @() } |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath (Join-Path $dataDir 'epg\epg_sources.json') -Encoding utf8NoBOM
        @{ locals = @() } |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath (Join-Path $dataDir 'lineup\locals.json') -Encoding utf8NoBOM
        @{ blocks = @(@{ start = 1; end = 9999; category = 'General'; notes = 'fixture' }) } |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath (Join-Path $dataDir 'lineup\numbering_blocks.json') -Encoding utf8NoBOM
        @{ aliases = @() } |
            ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath (Join-Path $dataDir 'rules\aliases.json') -Encoding utf8NoBOM
    }

    function Get-ManifestArtifactRecord {
        param([Parameter(Mandatory)][string]$Root)

        $summary = Get-Content -LiteralPath (Join-Path $Root 'output\reports\build-summary.json') -Raw |
            ConvertFrom-Json
        $manifestPath = Join-Path $Root (Join-Path ($summary.CandidateNamespacePath -replace '/', '\') 'manifest.json')
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return @($manifest.InputArtifactHashes)[0]
    }
}

Describe 'M3U input artifact hash evidence' {
    It 'is independent of the source path when the input bytes are identical' {
        $pathA = Join-Path $TestDrive 'source-a\playlist.m3u'
        $pathB = Join-Path $TestDrive 'source-b\playlist.m3u'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pathA), (Split-Path -Parent $pathB) | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($script:FixturePlaylist)
        [System.IO.File]::WriteAllBytes($pathA, $bytes)
        [System.IO.File]::WriteAllBytes($pathB, $bytes)

        $hashA = Get-InputArtifactHash -Bytes ([System.IO.File]::ReadAllBytes($pathA))
        $hashB = Get-InputArtifactHash -Bytes ([System.IO.File]::ReadAllBytes($pathB))

        $hashA | Should -Match '^[0-9a-f]{64}$'
        $hashB | Should -Be $hashA
    }

    It 'changes when one input byte is mutated' {
        $original = [System.IO.File]::ReadAllBytes($script:FixturePlaylist)
        $mutated = [byte[]]$original.Clone()
        $mutated[$mutated.Length - 1] = $mutated[$mutated.Length - 1] -bxor 1

        $originalHash = Get-InputArtifactHash -Bytes $original
        $mutatedHash = Get-InputArtifactHash -Bytes $mutated

        $mutatedHash | Should -Match '^[0-9a-f]{64}$'
        $mutatedHash | Should -Not -Be $originalHash
    }

    It 'records identical local and remote acquisitions with the same production hash' {
        $localRoot = Join-Path $TestDrive 'local-acquisition'
        New-BuildFixture -Root $localRoot -IncludeLocalPlaylist -Sources @(
            @{ name = 'Source'; group = 'General'; url = 'https://example.invalid/iptv/fixture'; enabled = $true; local_playlist = 'data/playlists/local.m3u' }
        )
        & $script:BuildLineupPath -Root $localRoot
        $localRecord = Get-ManifestArtifactRecord -Root $localRoot

        $remoteRoot = Join-Path $TestDrive 'remote-acquisition'
        New-BuildFixture -Root $remoteRoot -Sources @(
            @{ name = 'Source'; group = 'General'; url = 'https://example.invalid/iptv/fixture'; enabled = $true }
        )
        $global:ChannelForgeHashEvidenceFixturePath = $script:FixturePlaylist
        Mock -CommandName Import-ChannelForgeConfiguredM3USource -MockWith {
            param($Source, $Provider, $MaxDocumentBytes, $MaxRawResponseBytes, $CacheRoot, $AcquisitionStatus)
            $channels = @(Import-ChannelForgeM3UPlaylist -Path $global:ChannelForgeHashEvidenceFixturePath -Provider $Provider -Playlist $Source.Name)
            if ($null -ne $AcquisitionStatus) {
                $AcquisitionStatus['InputArtifactHash'] = & (Get-Module ChannelForge) {
                    param($InputBytes)
                    Get-ChannelForgeDomainHash -Domain 'input-m3u/v2' -Bytes $InputBytes
                } ([System.IO.File]::ReadAllBytes($global:ChannelForgeHashEvidenceFixturePath))
            }
            return $channels
        }
        & $script:BuildLineupPath -Root $remoteRoot
        $remoteRecord = Get-ManifestArtifactRecord -Root $remoteRoot

        $localRecord.ArtifactKind | Should -Be 'M3U'
        $remoteRecord.ArtifactKind | Should -Be 'M3U'
        $localRecord.ArtifactHash | Should -Match '^[0-9a-f]{64}$'
        $remoteRecord.ArtifactHash | Should -Be $localRecord.ArtifactHash
        $remoteRecord.LogicalSourceId | Should -Be $localRecord.LogicalSourceId
    }

    It 'accepts a lowercase 64-hex M3U ArtifactHashRecord in the candidate manifest' {
        $hash = 'abcdef0123456789' * 4
        $record = New-MinimalArtifactHashRecord -ArtifactHash $hash
        $result = @(Invoke-MinimalCandidateManifest -InputArtifactHashes @($record))[-1]

        $result.Manifest.InputArtifactHashes.Count | Should -Be 1
        $result.Manifest.InputArtifactHashes[0].LogicalSourceId | Should -Be ('1' * 64)
        $result.Manifest.InputArtifactHashes[0].ArtifactKind | Should -Be 'M3U'
        $result.Manifest.InputArtifactHashes[0].ArtifactHash | Should -Be $hash
    }

    It 'rejects an empty M3U input hash before returning a candidate manifest' {
        $record = New-MinimalArtifactHashRecord -ArtifactHash ''

        { Invoke-MinimalCandidateManifest -InputArtifactHashes @($record) } |
            Should -Throw '*InputArtifactHashes contains an invalid record*'
    }

    It 'rejects an empty remote hash before publishing candidate artifacts' {
        $root = Join-Path $TestDrive 'empty-remote-hash'
        New-BuildFixture -Root $root -Sources @(
            @{ name = 'Source'; group = 'General'; url = 'https://example.invalid/iptv/fixture'; enabled = $true }
        )
        $global:ChannelForgeHashEvidenceFixturePath = $script:FixturePlaylist
        Mock -CommandName Import-ChannelForgeConfiguredM3USource -MockWith {
            param($Source, $Provider, $MaxDocumentBytes, $MaxRawResponseBytes, $CacheRoot, $AcquisitionStatus)
            $channels = @(Import-ChannelForgeM3UPlaylist -Path $global:ChannelForgeHashEvidenceFixturePath -Provider $Provider -Playlist $Source.Name)
            if ($null -ne $AcquisitionStatus) {
                $AcquisitionStatus['InputArtifactHash'] = ''
            }
            return $channels
        }

        { & $script:BuildLineupPath -Root $root } |
            Should -Throw '*InputArtifactHashes contains an invalid record*'
        $candidateRoot = Join-Path $root 'output\candidates'
        @(Get-ChildItem -LiteralPath $candidateRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object Name -ne '.staging').Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $root 'output\merged.m3u') -PathType Leaf | Should -BeFalse
    }
}
