BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $scriptPath = Join-Path $repoRoot 'scripts/Build-Candidate.ps1'
    $fixturePath = Join-Path $repoRoot 'tests/fixtures/tiny.m3u'
}

Describe 'PR1 candidate-only Build-Candidate' {
    It 'uses exact canonical JSON escaping and rejects unordered dictionaries' {
        . (Join-Path $repoRoot 'src/ChannelForge/Private/ConvertTo-ChannelForgeCanonicalJson.ps1')
        $ordered = [ordered]@{ Value = "quote`"slash\`n$([char]0xD83D)$([char]0xDE42)$([char]0x007F)" }
        ConvertTo-ChannelForgeCanonicalJson -InputObject $ordered | Should -Be '{"Value":"quote\"slash\\\n\ud83d\ude42\u007f"}'
        $unordered = @{ Value = 'x' }
        { ConvertTo-ChannelForgeCanonicalJson -InputObject $unordered } | Should -Throw
    }

    It 'publishes an immutable candidate without active output or accepted state' {
        $output = Join-Path $TestDrive 'output'
        $result = & $scriptPath -Root $repoRoot -M3UPath $fixturePath -OutputRoot $output
        Test-Path (Join-Path $output 'merged.m3u') | Should -BeFalse
        Test-Path (Join-Path $output 'merged.xml') | Should -BeFalse
        Test-Path (Join-Path $output 'candidates' $result.CandidateManifestHash) | Should -BeTrue
        $result.Manifest.CandidateManifestHash | Should -Be $result.CandidateManifestHash
    }

    It 'produces the same candidate hash for repeated equivalent builds' {
        $firstRoot = Join-Path $TestDrive 'first'
        $secondRoot = Join-Path $TestDrive 'second'
        $first = & $scriptPath -Root $repoRoot -M3UPath $fixturePath -OutputRoot $firstRoot
        $second = & $scriptPath -Root $repoRoot -M3UPath $fixturePath -OutputRoot $secondRoot
        $second.CandidateManifestHash | Should -Be $first.CandidateManifestHash
        $second.BuildIdentity | Should -Be $first.BuildIdentity
    }

    It 'rejects a final namespace with different bytes' {
        $output = Join-Path $TestDrive 'collision'
        $first = & $scriptPath -Root $repoRoot -M3UPath $fixturePath -OutputRoot $output
        $final = Join-Path $output ('candidates/' + $first.CandidateManifestHash)
        Add-Content -LiteralPath (Join-Path $final 'review.json') -Value 'collision'
        { & $scriptPath -Root $repoRoot -M3UPath $fixturePath -OutputRoot $output } | Should -Throw
    }

    It 'does not expose stream URLs in the candidate manifest' {
        $output = Join-Path $TestDrive 'privacy'
        $result = & $scriptPath -Root $repoRoot -M3UPath $fixturePath -OutputRoot $output
        $manifestPath = Join-Path $result.CandidateDirectory 'manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw
        $manifest | Should -Not -Match 'https?://'
    }

    It 'exposes deterministic Directory.Move before/after candidate hooks' {
        $helperPath = Join-Path $repoRoot 'src/ChannelForge/Private/Publish-ChannelForgeCandidateNamespace.ps1'
        . $helperPath
        $output = Join-Path $TestDrive 'hooks'
        $stage = Join-Path $output 'candidates/.staging/test'
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Value '{}' -NoNewline
        { Publish-ChannelForgeCandidateNamespace -OutputRoot $output -StagingPath $stage -CandidateManifestHash ('a' * 64) -FaultHook 'CandidateDirectoryMove.Before' } | Should -Throw
        Test-Path $stage | Should -BeTrue
    }
}
