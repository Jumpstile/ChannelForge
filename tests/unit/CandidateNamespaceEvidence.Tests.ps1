BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuildCandidatePath = Join-Path $script:RepoRoot 'scripts\Build-Candidate.ps1'
    $script:TinyPlaylistPath = Join-Path $script:RepoRoot 'tests\fixtures\tiny.m3u'

    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\ConvertTo-ChannelForgeCanonicalJson.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\Get-ChannelForgeDomainHash.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\New-ChannelForgeCandidateManifest.ps1')
    . (Join-Path $script:RepoRoot 'src\ChannelForge\Private\ConvertTo-ChannelForgeCandidateCanonical.ps1')

    function Get-NamespaceEvidenceProtectedSurfaceSnapshot {
        param([Parameter(Mandatory)][string]$Root)

        $snapshot = [ordered]@{}
        $protectedDirectories = @('data', 'config', 'state')
        foreach ($relativeDirectory in $protectedDirectories) {
            $directory = Join-Path $Root $relativeDirectory
            if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
                continue
            }

            foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Recurse | Sort-Object FullName)) {
                $relativePath = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
                $snapshot[$relativePath] = [ordered]@{
                    Length = $file.Length
                    Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        }

        foreach ($relativePath in @(
                'output/merged.m3u',
                'output/merged.xml',
                'output/m3u-rollback/merged.m3u.previous',
                'output/xmltv-rollback/merged.xml.previous'
            )) {
            $path = Join-Path $Root ($relativePath -replace '/', '\')
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $file = Get-Item -LiteralPath $path
                $snapshot[$relativePath] = [ordered]@{
                    Length = $file.Length
                    Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        }

        return ConvertTo-Json -InputObject $snapshot -Depth 8 -Compress
    }
}

Describe 'candidate namespace boundary evidence' {
    It 'leaves the protected surface byte-identical across a candidate-only build' {
        $root = Join-Path $TestDrive 'protected-surface'
        $output = Join-Path $root 'output'
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $root 'data/providers'),
            (Join-Path $root 'config'),
            (Join-Path $root 'state'),
            (Join-Path $output 'm3u-rollback'),
            (Join-Path $output 'xmltv-rollback') | Out-Null
        Copy-Item -LiteralPath $script:TinyPlaylistPath -Destination (Join-Path $root 'source.m3u')

        [IO.File]::WriteAllText((Join-Path $root 'data/providers/credentials.json'), '{"provider":"fixture","token":"must-survive"}')
        [IO.File]::WriteAllText((Join-Path $root 'config/settings.json'), '{"mode":"protected"}')
        [IO.File]::WriteAllText((Join-Path $root 'state/accepted-lineup.json'), '{"generation":"accepted"}')
        [IO.File]::WriteAllText((Join-Path $root 'state/accepted-lineup.json.previous'), '{"generation":"previous"}')
        [IO.File]::WriteAllText((Join-Path $output 'merged.m3u'), 'protected public m3u')
        [IO.File]::WriteAllText((Join-Path $output 'merged.xml'), 'protected public xml')
        [IO.File]::WriteAllText((Join-Path $output 'm3u-rollback/merged.m3u.previous'), 'protected m3u rollback')
        [IO.File]::WriteAllText((Join-Path $output 'xmltv-rollback/merged.xml.previous'), 'protected xml rollback')

        $before = Get-NamespaceEvidenceProtectedSurfaceSnapshot -Root $root
        $result = & $script:BuildCandidatePath `
            -Root $root `
            -M3UPath (Join-Path $root 'source.m3u') `
            -OutputRoot $output
        $after = Get-NamespaceEvidenceProtectedSurfaceSnapshot -Root $root

        $after | Should -Be $before
        Test-Path -LiteralPath (Join-Path $result.CandidateDirectory 'manifest.json') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $result.CandidateDirectory 'merged.m3u') -PathType Leaf | Should -BeTrue
        Test-ChannelForgeCandidateNamespace `
            -Directory $result.CandidateDirectory `
            -ManifestHash $result.CandidateManifestHash | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $output 'merged.m3u') -Raw) | Should -Be 'protected public m3u'
        (Get-Content -LiteralPath (Join-Path $output 'merged.xml') -Raw) | Should -Be 'protected public xml'
    }

    It 'rejects a namespace containing only review artifacts without a merged output' {
        $root = Join-Path $TestDrive 'review-only-namespace'
        $directory = Join-Path $root 'candidates/review-only'
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $reviewJsonBytes = $utf8.GetBytes('{"ReviewRecords":[]}')
        $reviewMarkdownBytes = $utf8.GetBytes("# Review`n")

        $manifestResult = ConvertTo-ChannelForgeCandidateManifest `
            -RawM3UOccurrences @() `
            -M3UBytes $null `
            -XMLTVBytes $null `
            -ReviewJSONBytes $reviewJsonBytes `
            -ReviewMarkdownBytes $reviewMarkdownBytes
        $manifest = [ordered]@{}
        foreach ($property in @($manifestResult.Manifest.PSObject.Properties)) {
            $manifest[$property.Name] = $property.Value
        }
        $manifest.CandidateManifestHash = [string]$manifestResult.CandidateManifestHash
        $directory = Join-Path $root ('candidates/' + $manifest.CandidateManifestHash)
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        [IO.File]::WriteAllBytes(
            (Join-Path $directory 'lineup-change-review.json'),
            $reviewJsonBytes)
        [IO.File]::WriteAllBytes(
            (Join-Path $directory 'lineup-change-review.md'),
            $reviewMarkdownBytes)
        [IO.File]::WriteAllText(
            (Join-Path $directory 'manifest.json'),
            (ConvertTo-ChannelForgeCandidateJson -InputObject ([pscustomobject]$manifest)),
            $utf8)

        @($manifest.ArtifactRecords | ForEach-Object RelativePath) |
            Should -Be @('lineup-change-review.json', 'lineup-change-review.md')
        Test-Path -LiteralPath (Join-Path $directory 'merged.m3u') -PathType Leaf | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $directory 'merged.xml') -PathType Leaf | Should -BeFalse
        Test-ChannelForgeCandidateNamespace -Directory $directory -ManifestHash $manifest.CandidateManifestHash |
            Should -BeFalse
    }
}
