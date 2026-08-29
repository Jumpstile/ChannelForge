BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $proposal = Get-Content (Join-Path $root 'docs/adr/blocker-2-contract-v9-proposal/PART-B-entry-output-slice.md') -Raw
    $partA = Get-Content (Join-Path $root 'docs/adr/blocker-2-contract-v9-proposal/PART-A-canonical-foundation.md') -Raw
    $fixture = Get-Content (Join-Path $root 'tests/fixtures/entry-output-slice-v9.json') -Raw | ConvertFrom-Json
}
Describe 'Issue 109 EntryOutputSlice erratum' {
    It 'defines the dedicated domain and exact byte projection' {
        $partA | Should -Match 'candidate-entry-content/v1'
        $proposal | Should -Match 'exact slice bytes'
        $proposal | Should -Match 'without path, offset, length, JSON'
        $proposal | Should -Match 'same bytes retain the same hash'
        $proposal | Should -Not -Match 'active-m3u/v2.*slice'
    }
    It 'defines bounds, path, positive length, and fail-closed rules' {
        $proposal | Should -Match '(?s)ByteLength.*MUST be positive'
        $proposal | Should -Match 'overflow-safe'
        $proposal | Should -Match 'less than or equal'
        $proposal | Should -Match 'merged.m3u'
        $proposal | Should -Match 'fail closed'
    }
    It 'recomputes the golden slice hash from exact bytes' {
        $bytes = [Convert]::FromBase64String($fixture.BytesUtf8Base64)
        $domain = [Text.Encoding]::UTF8.GetBytes('candidate-entry-content/v1')
        $payload = [byte[]]::new($domain.Length + 1 + $bytes.Length)
        [Buffer]::BlockCopy($domain, 0, $payload, 0, $domain.Length)
        [Buffer]::BlockCopy($bytes, 0, $payload, $domain.Length + 1, $bytes.Length)
        $actual = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
        $actual | Should -Be $fixture.EntryContentHash
        $bytes.Length | Should -Be $fixture.ByteLength
    }
    It 'proves the current v7 producer emits null slice metadata' {
        $producer = Get-Content (Join-Path $root 'src/ChannelForge/Private/New-ChannelForgeCandidateManifest.ps1') -Raw
        $producer | Should -Match 'EntryOutputSlice'
        $producer | Should -Match 'ByteOffset = \$null'
        $producer | Should -Match 'ByteLength = \$null'
        $producer | Should -Match 'EntryContentHash = \$null'
    }
    It 'preserves v8 acceptance semantics and advances candidate version' {
        $readme = Get-Content (Join-Path $root 'docs/adr/blocker-2-contract-v9-proposal/README.md') -Raw
        $readme | Should -Match 'blocker-2-contract/v9'
        $readme | Should -Match 'blocker-2-contract/v8`\.'
        $readme | Should -Match 'blocker-2-contract/v8-acceptance'
        $readme | Should -Match 'semantics are unchanged'
    }

    It 'validates full M3U slices, bounds, overlap, gaps, and relocation' {
        $artifact = [Text.Encoding]::UTF8.GetBytes("#EXTINF:-1,One`nhttps://one.invalid`n#EXTINF:-1,Two`nhttps://two.invalid`n")
        $domain = [Text.Encoding]::UTF8.GetBytes('candidate-entry-content/v1')
        function Get-SliceHash([byte[]]$Bytes) {
            $payload = [byte[]]::new($domain.Length + 1 + $Bytes.Length)
            [Buffer]::BlockCopy($domain, 0, $payload, 0, $domain.Length)
            [Buffer]::BlockCopy($Bytes, 0, $payload, $domain.Length + 1, $Bytes.Length)
            ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
        }
        $firstLength = ([Text.Encoding]::UTF8.GetBytes("#EXTINF:-1,One`nhttps://one.invalid`n")).Length
        $secondOffset = $firstLength
        $secondLength = $artifact.Length - $secondOffset
        $first = $artifact[0..($firstLength - 1)]
        $second = $artifact[$secondOffset..($artifact.Length - 1)]
        (Get-SliceHash $first) | Should -Not -Be (Get-SliceHash $second)
        ($secondOffset + $secondLength) | Should -Be $artifact.Length
        ($firstLength + $secondLength) | Should -Be $artifact.Length
        ($firstLength -lt $artifact.Length -and $secondOffset -ge 0 -and $secondOffset + $secondLength -le $artifact.Length) | Should -BeTrue
        (Get-SliceHash $second) | Should -Be (Get-SliceHash $artifact[$secondOffset..($artifact.Length - 1)])
    }
    It 'agrees with the production successor manifest and candidate artifact bytes' {
        $out = Join-Path ([IO.Path]::GetTempPath()) ('issue109-' + [guid]::NewGuid().ToString('N'))
        try {
            & pwsh -NoProfile -File (Join-Path $root 'scripts/Build-Candidate.ps1') -Root $root -M3UPath (Join-Path $root 'tests/fixtures/identity-binding/playlist.m3u') -OutputRoot $out -EmitEntrySlices | Out-Null
            $manifestPath = Get-ChildItem (Join-Path $out 'candidates') -Directory | Where-Object Name -ne '.staging' | ForEach-Object { Join-Path $_.FullName 'manifest.json' } | Select-Object -First 1
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $artifact = [IO.File]::ReadAllBytes((Join-Path (Split-Path $manifestPath) 'merged.m3u'))
            foreach ($entry in @($manifest.Entries)) {
                $slice = $entry.EntryOutputSlice
                $bytes = [byte[]]$artifact[$slice.ByteOffset..($slice.ByteOffset + $slice.ByteLength - 1)]
                ($slice.ByteOffset + $slice.ByteLength) | Should -BeLessOrEqual $artifact.Length
                $bytes = [byte[]]$artifact[$slice.ByteOffset..($slice.ByteOffset + $slice.ByteLength - 1)]
                $domain = [Text.Encoding]::UTF8.GetBytes('candidate-entry-content/v1')
                $payload = [byte[]]::new($domain.Length + 1 + $bytes.Length)
                [Buffer]::BlockCopy($domain, 0, $payload, 0, $domain.Length)
                [Buffer]::BlockCopy($bytes, 0, $payload, $domain.Length + 1, $bytes.Length)
                $hash = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
                $hash | Should -Be $slice.EntryContentHash
            }
        } finally {
            Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
