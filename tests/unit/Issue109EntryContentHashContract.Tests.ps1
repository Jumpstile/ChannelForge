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
        $playlistPath = Join-Path $root 'tests/fixtures/identity-binding/playlist.m3u'
        $channels = @(Import-ChannelForgeM3UPlaylist -Path $playlistPath -Provider 'candidate' -Playlist 'playlist')
        $logicalSourceId = & (Get-Module ChannelForge) {
            Get-ChannelForgeLogicalSourceId -ProviderName 'candidate' -SourceName 'playlist' -SourceKind 'M3U' -SourceOrdinal 0
        }
        $raw = @(& (Get-Module ChannelForge) {
            param($inputChannels, $sourceId)
            Get-ChannelForgeRawM3UProjection -Channel $inputChannels -LogicalSourceId $sourceId -CandidateContractVersion 'blocker-2-contract/v8'
        } $channels $logicalSourceId)
        $raw = @($raw | Sort-Object EntryId)
        $serializedChannels = @($raw | ForEach-Object Channel)
        $artifactPath = Join-Path $TestDrive 'issue109-identity-binding.m3u'
        $serializedChannels | Export-ChannelForgeM3UPlaylist -Path $artifactPath
        $m3uBytes = [IO.File]::ReadAllBytes($artifactPath)
        $serializedEntryOrder = @($serializedChannels | ForEach-Object {
            $channel = $_
            @($raw | Where-Object { $_.Channel -eq $channel } | Select-Object -First 1 | ForEach-Object EntryId)
        })
        $result = & (Get-Module ChannelForge) {
            param($rawOccurrences, $bytes, $entryOrder)
            ConvertTo-ChannelForgeCandidateManifest `
                -RawM3UOccurrences $rawOccurrences `
                -M3UBytes $bytes `
                -SerializedM3UEntryOrder $entryOrder `
                -CandidateContractVersion 'blocker-2-contract/v8'
        } $raw $m3uBytes $serializedEntryOrder
        $result.Manifest.Entries.Count | Should -Be $serializedChannels.Count
        foreach ($entry in @($result.Manifest.Entries)) {
            $slice = $entry.EntryOutputSlice
            $slice.RelativePath | Should -Be 'merged.m3u'
            $slice.ByteOffset | Should -BeGreaterOrEqual 8
            $slice.ByteLength | Should -BeGreaterThan 0
            ($slice.ByteOffset + $slice.ByteLength) | Should -BeLessOrEqual $m3uBytes.Length
            $sliceBytes = [byte[]]$m3uBytes[$slice.ByteOffset..($slice.ByteOffset + $slice.ByteLength - 1)]
            $domain = [Text.Encoding]::UTF8.GetBytes('candidate-entry-content/v1')
            $payload = [byte[]]::new($domain.Length + 1 + $sliceBytes.Length)
            [Buffer]::BlockCopy($domain, 0, $payload, 0, $domain.Length)
            [Buffer]::BlockCopy($sliceBytes, 0, $payload, $domain.Length + 1, $sliceBytes.Length)
            $hash = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
            $hash | Should -Be $slice.EntryContentHash
        }
    }
    It 'allocates distinct contiguous slices for duplicate playlist bytes' {
        $playlistPath = Join-Path $root 'tests/fixtures/issue109-duplicate.m3u'
        $channels = @(Import-ChannelForgeM3UPlaylist -Path $playlistPath -Provider 'candidate' -Playlist 'duplicate')
        $logicalSourceId = & (Get-Module ChannelForge) {
            Get-ChannelForgeLogicalSourceId -ProviderName 'candidate' -SourceName 'duplicate' -SourceKind 'M3U' -SourceOrdinal 0
        }
        $raw = @(& (Get-Module ChannelForge) {
            param($inputChannels, $sourceId)
            Get-ChannelForgeRawM3UProjection -Channel $inputChannels -LogicalSourceId $sourceId -CandidateContractVersion 'blocker-2-contract/v8'
        } $channels $logicalSourceId)
        $raw = @($raw | Sort-Object EntryId)
        $serializedChannels = @($raw | ForEach-Object Channel)
        $artifactPath = Join-Path $TestDrive 'issue109-duplicate.m3u'
        $serializedChannels | Export-ChannelForgeM3UPlaylist -Path $artifactPath
        $m3uBytes = [IO.File]::ReadAllBytes($artifactPath)
        $serializedEntryOrder = @($serializedChannels | ForEach-Object {
            $channel = $_
            @($raw | Where-Object { $_.Channel -eq $channel } | Select-Object -First 1 | ForEach-Object EntryId)
        })
        $result = & (Get-Module ChannelForge) {
            param($rawOccurrences, $bytes, $entryOrder)
            ConvertTo-ChannelForgeCandidateManifest `
                -RawM3UOccurrences $rawOccurrences `
                -M3UBytes $bytes `
                -SerializedM3UEntryOrder $entryOrder `
                -CandidateContractVersion 'blocker-2-contract/v8'
        } $raw $m3uBytes $serializedEntryOrder
        $slices = @($result.Manifest.Entries | ForEach-Object EntryOutputSlice)
        $slices.Count | Should -Be 2
        $slices[0].ByteOffset | Should -Be 8
        $slices[1].ByteOffset | Should -Be ($slices[0].ByteOffset + $slices[0].ByteLength)
        ($slices[0].ByteOffset + $slices[0].ByteLength) | Should -Be $slices[1].ByteOffset
        ($slices[1].ByteOffset + $slices[1].ByteLength) | Should -Be $m3uBytes.Length
        $firstBytes = [byte[]]$m3uBytes[$slices[0].ByteOffset..($slices[0].ByteOffset + $slices[0].ByteLength - 1)]
        $secondBytes = [byte[]]$m3uBytes[$slices[1].ByteOffset..($slices[1].ByteOffset + $slices[1].ByteLength - 1)]
        [Convert]::ToBase64String($firstBytes) | Should -Be ([Convert]::ToBase64String($secondBytes))
        $hashes = foreach ($sliceBytes in @($firstBytes, $secondBytes)) {
            $domain = [Text.Encoding]::UTF8.GetBytes('candidate-entry-content/v1')
            $payload = [byte[]]::new($domain.Length + 1 + $sliceBytes.Length)
            [Buffer]::BlockCopy($domain, 0, $payload, 0, $domain.Length)
            [Buffer]::BlockCopy($sliceBytes, 0, $payload, $domain.Length + 1, $sliceBytes.Length)
            ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
        }
        $hashes[0] | Should -Be $slices[0].EntryContentHash
        $hashes[1] | Should -Be $slices[1].EntryContentHash
        $slices[0].EntryContentHash | Should -Be $slices[1].EntryContentHash
        $slices[0].ByteOffset | Should -Not -Be $slices[1].ByteOffset
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
        $providerPath = Join-Path $providerDir 'issue109-provider-order.json'
        $providerConfig = Get-Content $providerPath -Raw | ConvertFrom-Json
        $providerSources = @(& (Get-Module ChannelForge) {
            param($path)
            Read-ChannelForgeProvider -Path $path
        } $providerPath | Where-Object Enabled)
        $sourceRecords = foreach ($source in $providerSources) {
            $sourcePath = Join-Path $testRoot ([string]$source.LocalPlaylist)
            $channels = @(Import-ChannelForgeM3UPlaylist -Path $sourcePath -Provider $providerConfig.provider -Playlist $source.Name)
            $logicalSourceId = & (Get-Module ChannelForge) {
                param($providerName, $sourceName)
                Get-ChannelForgeLogicalSourceId -ProviderName $providerName -SourceName $sourceName -SourceKind 'M3U' -SourceOrdinal 0
            } $providerConfig.provider $source.Name
            $raw = @(& (Get-Module ChannelForge) {
                param($inputChannels, $sourceId)
                Get-ChannelForgeRawM3UProjection -Channel $inputChannels -LogicalSourceId $sourceId -CandidateContractVersion 'blocker-2-contract/v8'
            } $channels $logicalSourceId)
            [pscustomobject]@{
                LogicalSourceId = $logicalSourceId
                Channels = @($raw | Sort-Object EntryId | ForEach-Object Channel)
                Raw = @($raw | Sort-Object EntryId)
                SourceName = [string]$source.Name
            }
        }
        $mergeSources = @($sourceRecords | Sort-Object LogicalSourceId | ForEach-Object {
            [pscustomobject]@{
                Channels = $_.Channels
                Provider = $providerConfig.provider
                Playlist = $_.SourceName
                OrderKey = $_.LogicalSourceId
            }
        })
        $merge = Merge-ChannelForgeLineup `
            -Source $mergeSources `
            -AliasPath (Join-Path $rulesDir 'aliases.json') `
            -NumberingBlocksPath (Join-Path $lineupDir 'numbering_blocks.json')
        $artifactPath = Join-Path $TestDrive 'issue109-provider-merged.m3u'
        @($merge.Channels) | Export-ChannelForgeM3UPlaylist -Path $artifactPath
        $m3uBytes = [IO.File]::ReadAllBytes($artifactPath)
        $raw = @($sourceRecords | ForEach-Object Raw)
        $serializedEntryOrder = @($merge.Channels | ForEach-Object {
            $channel = $_
            @($raw | Where-Object { $_.Channel -eq $channel } | Select-Object -First 1 | ForEach-Object EntryId)
        })
        $result = & (Get-Module ChannelForge) {
            param($rawOccurrences, $bytes, $entryOrder)
            ConvertTo-ChannelForgeCandidateManifest `
                -RawM3UOccurrences $rawOccurrences `
                -M3UBytes $bytes `
                -SerializedM3UEntryOrder $entryOrder `
                -CandidateContractVersion 'blocker-2-contract/v8'
        } $raw $m3uBytes $serializedEntryOrder
        $manifestEntries = @($result.Manifest.Entries)
        $manifestOrderIds = @($manifestEntries | ForEach-Object EntryId)
        $manifestOrderIds | Should -Be (@($manifestOrderIds | Sort-Object))
        $rawByEntryId = @{}
        foreach ($record in $raw) { $rawByEntryId[[string]$record.EntryId] = $record }
        $artifactOrderIds = @($manifestEntries | Sort-Object { $_.EntryOutputSlice.ByteOffset } | ForEach-Object {
            $slice = $_.EntryOutputSlice
            $sliceBytes = [byte[]]$m3uBytes[$slice.ByteOffset..($slice.ByteOffset + $slice.ByteLength - 1)]
            $text = [Text.Encoding]::UTF8.GetString($sliceBytes)
            $text | Should -Match '(?s)^#EXTINF:[^\r\n]*\n[^\r\n]*\n$'
            $rawRecord = $raw | Where-Object { [string]$_.RawTvgId -ceq ([regex]::Match($text, 'tvg-id="([^"]+)"').Groups[1].Value) } | Select-Object -First 1
            [string]$rawRecord.EntryId
        })
        $artifactOrderIds | Should -Not -Be $manifestOrderIds
        $oldCursorMismatchCount = 0
        for ($i = 0; $i -lt $manifestOrderIds.Count; $i++) { if ($manifestOrderIds[$i] -ne $artifactOrderIds[$i]) { $oldCursorMismatchCount++ } }
        $oldCursorMismatchCount | Should -BeGreaterThan 0
        $sortedEntries = @($manifestEntries | Sort-Object { $_.EntryOutputSlice.ByteOffset })
        $slices = @($sortedEntries | ForEach-Object EntryOutputSlice)
        $slices[0].ByteOffset | Should -Be 8
        for ($i = 0; $i -lt $slices.Count; $i++) {
            $entry = $sortedEntries[$i]
            $slice = $entry.EntryOutputSlice
            $slice.ByteLength | Should -BeGreaterThan 0
            ($slice.ByteOffset + $slice.ByteLength) | Should -BeLessOrEqual $m3uBytes.Length
            if ($i -gt 0) { $slice.ByteOffset | Should -Be ($slices[$i - 1].ByteOffset + $slices[$i - 1].ByteLength) }
        }
        foreach ($entry in $sortedEntries) {
            $slice = $entry.EntryOutputSlice
            $sliceBytes = [byte[]]$m3uBytes[$slice.ByteOffset..($slice.ByteOffset + $slice.ByteLength - 1)]
            $text = [Text.Encoding]::UTF8.GetString($sliceBytes)
            $text | Should -Match '(?s)^#EXTINF:[^\r\n]*\n[^\r\n]*\n$'
            $tvgId = [regex]::Match($text, 'tvg-id="([^"]+)"').Groups[1].Value
            $rawByEntryId[[string]$entry.EntryId].RawTvgId | Should -Be $tvgId
            $domain = [Text.Encoding]::UTF8.GetBytes('candidate-entry-content/v1')
            $payload = [byte[]]::new($domain.Length + 1 + $sliceBytes.Length)
            [Buffer]::BlockCopy($domain, 0, $payload, 0, $domain.Length)
            [Buffer]::BlockCopy($sliceBytes, 0, $payload, $domain.Length + 1, $sliceBytes.Length)
            $hash = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
            $hash | Should -Be $slice.EntryContentHash
        }
        ($slices[-1].ByteOffset + $slices[-1].ByteLength) | Should -Be $m3uBytes.Length
    }
    It 'enforces the seven production version control combinations' {
        $scriptPath = Join-Path $root 'scripts/Build-Candidate.ps1'
        $m3u = Join-Path $root 'tests/fixtures/tiny.m3u'
        foreach ($case in @(
            @{ Name = 'default-v7'; Args = @(); ExpectedVersion = 'blocker-2-contract/v7'; ExpectedSlices = 0; ExpectedError = $null },
            @{ Name = 'explicit-v7'; Args = @('-CandidateContractVersion','blocker-2-contract/v7'); ExpectedVersion = 'blocker-2-contract/v7'; ExpectedSlices = 0; ExpectedError = $null },
            @{ Name = 'explicit-v7-slices'; Args = @('-CandidateContractVersion','blocker-2-contract/v7','-EmitEntrySlices'); ExpectedVersion = $null; ExpectedSlices = $null; ExpectedError = 'FAIL_CLOSED: explicit blocker-2-contract/v7 cannot be combined with -EmitEntrySlices.' },
            @{ Name = 'explicit-v8'; Args = @('-CandidateContractVersion','blocker-2-contract/v8'); ExpectedVersion = 'blocker-2-contract/v8'; ExpectedSlices = 3; ExpectedError = $null },
            @{ Name = 'explicit-v8-slices'; Args = @('-CandidateContractVersion','blocker-2-contract/v8','-EmitEntrySlices'); ExpectedVersion = 'blocker-2-contract/v8'; ExpectedSlices = 3; ExpectedError = $null },
            @{ Name = 'implicit-v8-slices'; Args = @('-EmitEntrySlices'); ExpectedVersion = $null; ExpectedSlices = $null; ExpectedError = 'FAIL_CLOSED: candidate-v8 registry migration requires explicit -CandidateContractVersion blocker-2-contract/v8.' },
            @{ Name = 'unsupported-version'; Args = @('-CandidateContractVersion','blocker-2-contract/v9'); ExpectedVersion = $null; ExpectedSlices = $null; ExpectedError = 'FAIL_CLOSED: unsupported CandidateContractVersion' }
        )) {
            $out = Join-Path $TestDrive ('issue109-control-' + $case.Name)
            $processOutput = (& pwsh -NoProfile -File $scriptPath -Root $root -M3UPath $m3u -OutputRoot $out @($case.Args) 2>&1 | Out-String)
            $exitCode = $LASTEXITCODE
            if ($null -eq $case.ExpectedError) {
                $exitCode | Should -Be 0
                $dir = Get-ChildItem (Join-Path $out 'candidates') -Directory | Where-Object Name -ne '.staging' | Select-Object -First 1
                $manifest = Get-Content (Join-Path $dir.FullName 'manifest.json') -Raw | ConvertFrom-Json
                $manifest.ContractVersion | Should -Be $case.ExpectedVersion
                (@($manifest.Entries | Where-Object { $null -ne $_.EntryOutputSlice.ByteOffset }).Count) | Should -Be $case.ExpectedSlices
            }
            else {
                $exitCode | Should -Not -Be 0
                $processOutput | Should -Match ([regex]::Escape($case.ExpectedError))
            }
        }
    }
}
