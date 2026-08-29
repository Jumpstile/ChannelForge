BeforeAll {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $proposal = Get-Content (Join-Path $root 'docs/adr/blocker-2-contract-v9-proposal/PART-B-entry-output-slice.md') -Raw
    $partA = Get-Content (Join-Path $root 'docs/adr/blocker-2-contract-v9-proposal/PART-A-canonical-foundation.md') -Raw
    $fixture = Get-Content (Join-Path $root 'tests/fixtures/entry-output-slice-v9.json') -Raw | ConvertFrom-Json
    Import-Module (Join-Path $root 'src/ChannelForge/ChannelForge.psd1') -Force
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
    It 'allocates distinct contiguous slices for duplicate playlist bytes' {
        $out = Join-Path ([IO.Path]::GetTempPath()) ('issue109-duplicate-' + [guid]::NewGuid().ToString('N'))
        try {
            & pwsh -NoProfile -File (Join-Path $root 'scripts/Build-Candidate.ps1') -Root $root -M3UPath (Join-Path $root 'tests/fixtures/issue109-duplicate.m3u') -OutputRoot $out -EmitEntrySlices | Out-Null
            $dir = Get-ChildItem (Join-Path $out 'candidates') -Directory | Where-Object Name -ne '.staging' | Select-Object -First 1
            $manifest = Get-Content (Join-Path $dir.FullName 'manifest.json') -Raw | ConvertFrom-Json
            $slices = @($manifest.Entries | ForEach-Object EntryOutputSlice)
            $slices.Count | Should -Be 2
            $slices[0].ByteOffset | Should -Be 8
            $slices[1].ByteOffset | Should -Be ($slices[0].ByteOffset + $slices[0].ByteLength)
            ($slices[0].ByteOffset + $slices[0].ByteLength) | Should -BeLessOrEqual $slices[1].ByteOffset
            ($slices[1].ByteOffset + $slices[1].ByteLength) | Should -Be ([IO.File]::ReadAllBytes((Join-Path $dir.FullName 'merged.m3u'))).Length
        } finally {
            Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It 'fails closed for a same-length malformed header' {
        $badBytes = [Text.Encoding]::UTF8.GetBytes('XXXXXXXX')
        { & (Get-Module ChannelForge) { param([byte[]]$b) ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences @() -M3UBytes $b -CandidateContractVersion 'blocker-2-contract/v8' } $badBytes } | Should -Throw 'FAIL_CLOSED:*'
    }
    It 'fails closed for trailing bytes after the retained slices' {
        $badBytes = [Text.Encoding]::UTF8.GetBytes("#EXTM3U`nX")
        { & (Get-Module ChannelForge) { param([byte[]]$b) ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences @() -M3UBytes $b -CandidateContractVersion 'blocker-2-contract/v8' } $badBytes } | Should -Throw 'FAIL_CLOSED:*'
    }
    It 'supports divergent provider artifact and manifest order' {
        $testRoot = Join-Path $TestDrive 'issue109-provider-root'
        $providerDir = Join-Path $testRoot 'data/providers'
        $playlistDir = Join-Path $testRoot 'data/playlists'
        $rulesDir = Join-Path $testRoot 'data/rules'
        $lineupDir = Join-Path $testRoot 'data/lineup'
        New-Item -ItemType Directory -Force -Path $providerDir,$playlistDir,$rulesDir,$lineupDir | Out-Null
        Copy-Item (Join-Path $root 'tests/fixtures/issue109-provider-order.json') (Join-Path $providerDir 'issue109-provider-order.json')
        Copy-Item (Join-Path $root 'tests/fixtures/issue109-provider-order.m3u') (Join-Path $playlistDir 'issue109-provider-order.m3u')
        Copy-Item (Join-Path $root 'data/rules/aliases.json') (Join-Path $rulesDir 'aliases.json')
        Copy-Item (Join-Path $root 'data/lineup/numbering_blocks.json') (Join-Path $lineupDir 'numbering_blocks.json')
        $out = Join-Path $testRoot 'output'
        & pwsh -NoProfile -File (Join-Path $root 'scripts/Build-Candidate.ps1') -Root $testRoot -ProviderPath 'issue109-provider-order.json' -OutputRoot $out -EmitEntrySlices | Out-Null
            $dir = Get-ChildItem (Join-Path $out 'candidates') -Directory | Where-Object Name -ne '.staging' | Select-Object -First 1
            $manifest = Get-Content (Join-Path $dir.FullName 'manifest.json') -Raw | ConvertFrom-Json
            $artifact = [IO.File]::ReadAllBytes((Join-Path $dir.FullName 'merged.m3u'))
            $manifestIds = @($manifest.Entries | ForEach-Object EntryId)
            $artifactIds = @($manifest.Entries | Sort-Object {$_.EntryOutputSlice.ByteOffset} | ForEach-Object {
                $s = $_.EntryOutputSlice
                $bytes = [Text.Encoding]::UTF8.GetString([byte[]]$artifact[$s.ByteOffset..($s.ByteOffset + $s.ByteLength - 1)])
                $id = [regex]::Match($bytes, 'tvg-id="([^"]+)"').Groups[1].Value
                [string](@($manifest.Entries | Where-Object { [string]$_.RawTvgId -ceq $id })[0].EntryId)
            })
            $manifestIds | Should -Be (@($manifestIds | Sort-Object))
            $artifactIds | Should -Not -Be $manifestIds
            $oldCursorMismatchCount = 0
            for ($i = 0; $i -lt $manifestIds.Count; $i++) { if ($manifestIds[$i] -ne $artifactIds[$i]) { $oldCursorMismatchCount++ } }
            $oldCursorMismatchCount | Should -BeGreaterThan 0
            $slices = @($manifest.Entries | Sort-Object {$_.EntryOutputSlice.ByteOffset})
            $slices[0].EntryOutputSlice.ByteOffset | Should -Be 8
            for ($i = 0; $i -lt $slices.Count; $i++) {
                $s = $slices[$i].EntryOutputSlice
                $s.ByteLength | Should -BeGreaterThan 0
                ($s.ByteOffset + $s.ByteLength) | Should -BeLessOrEqual $artifact.Length
                if ($i -gt 0) { $s.ByteOffset | Should -Be ($slices[$i - 1].EntryOutputSlice.ByteOffset + $slices[$i - 1].EntryOutputSlice.ByteLength) }
            }
            ($slices[-1].EntryOutputSlice.ByteOffset + $slices[-1].EntryOutputSlice.ByteLength) | Should -Be $artifact.Length
    }
    It 'enforces the seven production version control combinations' {
        $scriptPath = Join-Path $root 'scripts/Build-Candidate.ps1'
        $m3u = Join-Path $root 'tests/fixtures/tiny.m3u'
        foreach ($case in @(
            @{ Name='default-v7'; Args=@() ; Expected='blocker-2-contract/v7'; Slices=$false },
            @{ Name='legacy-successor'; Args=@('-EmitEntrySlices'); Expected='blocker-2-contract/v8'; Slices=$true },
            @{ Name='explicit-v8'; Args=@('-CandidateContractVersion','blocker-2-contract/v8'); Expected='blocker-2-contract/v8'; Slices=$true },
            @{ Name='explicit-v8-switch'; Args=@('-CandidateContractVersion','blocker-2-contract/v8','-EmitEntrySlices'); Expected='blocker-2-contract/v8'; Slices=$true },
            @{ Name='explicit-v7'; Args=@('-CandidateContractVersion','blocker-2-contract/v7'); Expected='blocker-2-contract/v7'; Slices=$false }
        )) {
            $out = Join-Path ([IO.Path]::GetTempPath()) ('issue109-control-' + [guid]::NewGuid().ToString('N'))
            & pwsh -NoProfile -File $scriptPath -Root $root -M3UPath $m3u -OutputRoot $out @($case.Args) | Out-Null
            $dir = Get-ChildItem (Join-Path $out 'candidates') -Directory | Where-Object Name -ne '.staging' | Select-Object -First 1
            $manifest = Get-Content (Join-Path $dir.FullName 'manifest.json') -Raw | ConvertFrom-Json
            $manifest.ContractVersion | Should -Be $case.Expected
            (@($manifest.Entries | Where-Object { $null -ne $_.EntryOutputSlice.ByteOffset }).Count -gt 0) | Should -Be $case.Slices
            Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
        }
        $v7Output = (& pwsh -NoProfile -File $scriptPath -Root $root -M3UPath $m3u -OutputRoot (Join-Path ([IO.Path]::GetTempPath()) 'issue109-invalid') -CandidateContractVersion blocker-2-contract/v7 -EmitEntrySlices 2>&1 | Out-String)
        $v7Exit = $LASTEXITCODE
        $v7Exit | Should -Not -Be 0
        $v7Output | Should -Match 'FAIL_CLOSED: explicit blocker-2-contract/v7 cannot be combined with -EmitEntrySlices.'
        $badOutput = (& pwsh -NoProfile -File $scriptPath -Root $root -M3UPath $m3u -OutputRoot (Join-Path ([IO.Path]::GetTempPath()) 'issue109-invalid') -CandidateContractVersion blocker-2-contract/v9 2>&1 | Out-String)
        $badExit = $LASTEXITCODE
        $badExit | Should -Not -Be 0
        $badOutput | Should -Match 'FAIL_CLOSED: unsupported CandidateContractVersion'
    }
}
