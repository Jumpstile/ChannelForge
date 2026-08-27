BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildCandidatePath = Join-Path $script:RepoRoot 'scripts\Build-Candidate.ps1'
    $script:PlaylistPath = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\playlist.m3u'
    $script:GuidePath = Join-Path $script:RepoRoot 'tests\fixtures\identity-binding\guide.xml'
    $script:RegistryVersion = 'blocker-2-contract/v7'

    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\ConvertTo-ChannelForgeCanonicalJson.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeDomainHash.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeLogicalSourceId.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeRawM3UProjection.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeRawXmltvProjection.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\New-ChannelForgeCandidateManifest.ps1')

    # Candidate-side frozen-v7 Version registry. Location is deliberately a
    # symbol, rather than a line number, so this remains useful as code moves.
    # Hash input rows (SafeTvgNameInput, EntryId input, StructuralEvidenceInput,
    # and CollisionIdentity) are domain-specific inputs, not registry objects;
    # their enclosing emitted projections are asserted below.
    $script:CandidateVersionRegistry = @(
        [pscustomobject]@{ Name = 'SafeTvgNameInput'; Symbol = 'New-ChannelForgeCandidateManifest::Get-PresentationFingerprint / entries.PresentationFingerprint'; Location = 'src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1'; RegistryObject = $false; Enclosing = 'CandidateManifest' }
        [pscustomobject]@{ Name = 'RawM3UOccurrence'; Symbol = 'Read-ChannelForgeM3UReader::RawM3UOccurrence; Get-ChannelForgeRawM3UProjection::projection'; Location = 'src/ChannelForge/Private/Read-ChannelForgeM3UReader.ps1; src/ChannelForge/Private/Get-ChannelForgeRawM3UProjection.ps1'; RegistryObject = $true; Enclosing = 'RawM3UOccurrence' }
        [pscustomobject]@{ Name = 'EntryId input'; Symbol = 'Get-ChannelForgeRawM3UProjection::$entryInput'; Location = 'src/ChannelForge/Private/Get-ChannelForgeRawM3UProjection.ps1'; RegistryObject = $false; Enclosing = 'RawM3UOccurrence' }
        [pscustomobject]@{ Name = 'M3UIdentityCollisions'; Symbol = 'New-ChannelForgeCandidateManifest::$collisionProjection'; Location = 'src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1'; RegistryObject = $true; Enclosing = 'M3UIdentityCollisions' }
        [pscustomobject]@{ Name = 'RawXMLTVChannelOccurrence'; Symbol = 'Read-ChannelForgeXmltvDocument::rawChannelOccurrences; Get-ChannelForgeRawXmltvProjection::$projection'; Location = 'src/ChannelForge/Private/Read-ChannelForgeXmltvDocument.ps1; src/ChannelForge/Private/Get-ChannelForgeRawXmltvProjection.ps1'; RegistryObject = $true; Enclosing = 'RawXMLTVChannelOccurrence' }
        [pscustomobject]@{ Name = 'RawProgrammeOccurrence'; Symbol = 'Read-ChannelForgeXmltvDocument::rawProgrammeOccurrences; Get-ChannelForgeRawXmltvProjection::$projection'; Location = 'src/ChannelForge/Private/Read-ChannelForgeXmltvDocument.ps1; src/ChannelForge/Private/Get-ChannelForgeRawXmltvProjection.ps1'; RegistryObject = $true; Enclosing = 'RawProgrammeOccurrence' }
        [pscustomobject]@{ Name = 'GuideCandidateOccurrence'; Symbol = 'New-ChannelForgeCandidateManifest::$guideOccurrences'; Location = 'src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1'; RegistryObject = $true; Enclosing = 'GuideOccurrences' }
        [pscustomobject]@{ Name = 'review JSON'; Symbol = 'Build-Candidate.ps1::$review'; Location = 'scripts/Build-Candidate.ps1'; RegistryObject = $true; Enclosing = 'ReviewJSON' }
        [pscustomobject]@{ Name = 'BindingRecord'; Symbol = 'New-ChannelForgeCandidateManifest::New-BindingRecord / $bindingProjection'; Location = 'src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1'; RegistryObject = $true; Enclosing = 'BindingRecords' }
        [pscustomobject]@{ Name = 'CandidateManifest'; Symbol = 'New-ChannelForgeCandidateManifest::$manifest'; Location = 'src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1'; RegistryObject = $true; Enclosing = 'CandidateManifest' }
        [pscustomobject]@{ Name = 'StructuralEvidenceInput'; Symbol = 'Get-ChannelForgeRawXmltvProjection::Get-Digest'; Location = 'src/ChannelForge/Private/Get-ChannelForgeRawXmltvProjection.ps1'; RegistryObject = $false; Enclosing = 'RawXMLTVChannelOccurrence/RawProgrammeOccurrence' }
        [pscustomobject]@{ Name = 'CollisionIdentity'; Symbol = 'Merge-ChannelForgeLineup::IdentityCollisions'; Location = 'src/ChannelForge/Public/Merge-ChannelForgeLineup.ps1'; RegistryObject = $false; Enclosing = 'M3UIdentityCollisions' }
        [pscustomobject]@{ Name = 'CollisionEvidenceInput'; Symbol = 'New-ChannelForgeCandidateManifest::$base / CollisionEvidenceDigest'; Location = 'src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1'; RegistryObject = $true; Enclosing = 'M3UIdentityCollisions' }
    )

    $script:Channels = @(Import-ChannelForgeM3UPlaylist `
        -Path $script:PlaylistPath `
        -Provider 'fixture-provider' `
        -Playlist 'identity-fixture')
    $script:Programmes = @(Import-ChannelForgeXmltvSource `
        -Path $script:GuidePath `
        -SourceId 'fixture-guide')
    $script:RawM3U = @(Get-ChannelForgeRawM3UProjection `
        -Channel $script:Channels `
        -LogicalSourceId 'm3u-source')
    $script:RawXMLTV = @(Get-ChannelForgeRawXmltvProjection -Programme $script:Programmes)
    $script:Binding = Resolve-ChannelForgeM3UXmltvBinding `
        -Channel $script:Channels `
        -Programme $script:Programmes
    function Assert-RegistryVersion {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][object[]]$Values
        )

        $Values.Count | Should -BeGreaterThan 0 -Because "$Name must emit at least one value"
        foreach ($value in $Values) {
            [string]$value | Should -BeExactly $script:RegistryVersion -Because "$Name is frozen to $script:RegistryVersion"
        }
    }
}


Describe 'candidate-side frozen-v7 Version registry evidence' {
    It 'maps every requested candidate symbol and asserts emitted projection versions' {
        @($script:CandidateVersionRegistry.Name) | Should -Be @(
            'SafeTvgNameInput',
            'RawM3UOccurrence',
            'EntryId input',
            'M3UIdentityCollisions',
            'RawXMLTVChannelOccurrence',
            'RawProgrammeOccurrence',
            'GuideCandidateOccurrence',
            'review JSON',
            'BindingRecord',
            'CandidateManifest',
            'StructuralEvidenceInput',
            'CollisionIdentity',
            'CollisionEvidenceInput'
        )
        $script:CandidateVersionRegistry | ForEach-Object {
            $_.Symbol | Should -Not -BeNullOrEmpty
            $_.Location | Should -Not -BeNullOrEmpty
        }

        # Make a collision projection from fixture channel references so the
        # manifest exercises the same collision/evidence path as production.
        $collision = [pscustomobject][ordered]@{
            IdentityKey = 'id:fixture-collision'
            Channels = @($script:Channels[0], $script:Channels[1])
        }
        $manifestResult = ConvertTo-ChannelForgeCandidateManifest `
            -RawM3UOccurrences $script:RawM3U `
            -M3UIdentityCollisions @($collision) `
            -RawXmltvOccurrences $script:RawXMLTV `
            -IdentityBindingResult $script:Binding `
            -SelectedSourceIds @('m3u-source', 'fixture-guide')
        $manifest = $manifestResult.Manifest

        # RawM3UOccurrence is emitted by the reader and by its canonical
        # projection; both are checked because the reader object is input
        # evidence while the projection is candidate evidence.
        Assert-RegistryVersion 'RawM3UOccurrence reader objects' @($script:Channels | ForEach-Object { $_.RawM3UOccurrence.Version })
        Assert-RegistryVersion 'RawM3UOccurrence projections' @($script:RawM3U | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'RawXMLTVChannelOccurrence reader objects' @($script:Programmes[0].Evidence.RawChannelOccurrences | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'RawProgrammeOccurrence reader objects' @($script:Programmes[0].Evidence.RawProgrammeOccurrences | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'RawXMLTVChannelOccurrence projections' @($script:RawXMLTV | Where-Object { $null -ne $_.RawChannelIdPresence } | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'RawProgrammeOccurrence projections' @($script:RawXMLTV | Where-Object { $null -ne $_.RawProgrammeChannelIdPresence } | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'M3UIdentityCollisions' @($manifest.M3UIdentityCollisions | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'GuideCandidateOccurrence' @($manifest.GuideOccurrences | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'BindingRecord' @($manifest.BindingRecords | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'CollisionEvidenceInput enclosing projection' @($manifest.M3UIdentityCollisions | ForEach-Object { $_.Version })
        [string]$manifest.Version | Should -BeExactly $script:RegistryVersion
        [string]$manifest.ContractVersion | Should -BeExactly $script:RegistryVersion
    }

    It 'emits frozen-v7 versions in review JSON and the published candidate manifest' {
        $outputRoot = Join-Path $TestDrive 'candidate-version-registry'
        $result = & $script:BuildCandidatePath `
            -Root $script:RepoRoot `
            -M3UPath $script:PlaylistPath `
            -XMLTVPath $script:GuidePath `
            -OutputRoot $outputRoot

        $reviewPath = Join-Path $result.CandidateDirectory 'lineup-change-review.json'
        $manifestPath = Join-Path $result.CandidateDirectory 'manifest.json'
        Test-Path -LiteralPath $reviewPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $manifestPath -PathType Leaf | Should -BeTrue

        $review = Get-Content -LiteralPath $reviewPath -Raw | ConvertFrom-Json
        $diskManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        [string]$review.Version | Should -BeExactly $script:RegistryVersion
        [string]$diskManifest.Version | Should -BeExactly $script:RegistryVersion
        [string]$diskManifest.ContractVersion | Should -BeExactly $script:RegistryVersion
        if (@($diskManifest.M3UIdentityCollisions).Count -gt 0) {
            Assert-RegistryVersion 'published M3UIdentityCollisions' @($diskManifest.M3UIdentityCollisions | ForEach-Object { $_.Version })
        }
        Assert-RegistryVersion 'published GuideCandidateOccurrence' @($diskManifest.GuideOccurrences | ForEach-Object { $_.Version })
        Assert-RegistryVersion 'published BindingRecord' @($diskManifest.BindingRecords | ForEach-Object { $_.Version })
    }
}
