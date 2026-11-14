BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Pub = 'https://img.example.com/a.png'
    $script:Pinned = 'https://img.example.com/pinned.png'
    $script:Def = @{ Sports = 'https://img.example.com/sports.png' }

    function New-TestChannel {
        param([string]$Name, [string]$Logo, [string]$TvgId = "$Name.us")
        New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName $Name -DisplayName $Name -TvgId $TvgId -Url "https://stream.example.com/$Name" -Group 'Sports' -Logo $Logo
    }
    function Get-Lines {
        param([object[]]$Channel, [hashtable]$Pin = @{}, [hashtable]$Default = @{})
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.m3u')
        $Channel | Export-ChannelForgeM3UPlaylist -Path $path -GroupDefaultLogo $Default -LogoPin $Pin -WarningAction SilentlyContinue
        [IO.File]::ReadAllText($path)
    }
    function Get-Manifest {
        param([object[]]$Channel, [hashtable]$Pin = @{})
        & (Get-Module ChannelForge) {
            param($ch, $pin)
            $raw = @(Get-ChannelForgeRawM3UProjection -Channel @($ch) -LogicalSourceId ('a' * 64) -CandidateContractVersion 'blocker-2-contract/v7')
            ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences $raw -LogoPin $pin -WarningAction SilentlyContinue
        } $Channel $Pin
    }
    function New-Root { $r = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $r | Out-Null; $r }
}

Describe 'Logo pins at the publish step' {
    It 'replaces a good public source logo' {
        $text = Get-Lines @(New-TestChannel 'A' $script:Pub) @{ 'A.us' = $script:Pinned }
        $text | Should -Match ([regex]::Escape("tvg-logo=`"$($script:Pinned)`""))
        $text | Should -Not -Match ([regex]::Escape($script:Pub))
    }

    It 'fills a channel that has no logo, and beats the group default' {
        $text = Get-Lines @(New-TestChannel 'A' '') @{ 'A.us' = $script:Pinned } $script:Def
        $text | Should -Match ([regex]::Escape("tvg-logo=`"$($script:Pinned)`""))
        $text | Should -Not -Match 'sports.png'
    }

    It 'matches the TvgId exactly (case-sensitive) and never pins an empty TvgId' {
        $channels = @((New-TestChannel 'A' $script:Pub), (New-TestChannel 'B' $script:Pub -TvgId ''))
        $map = [hashtable]::new([System.StringComparer]::Ordinal)
        $map['a.us'] = $script:Pinned
        $map[''] = $script:Pinned
        $text = Get-Lines $channels $map
        $text | Should -Not -Match 'pinned.png'
    }

    It 'a pin for an unknown TvgId changes nothing' {
        $channels = @(New-TestChannel 'A' $script:Pub)
        Get-Lines $channels @{ 'Nope.us' = $script:Pinned } | Should -Be (Get-Lines $channels)
    }

    It 'no pin or a pin for no channel gives the same M3U bytes, fingerprints and manifest hash' {
        $channels = @(New-TestChannel 'A' $script:Pub; New-TestChannel 'B' '')
        $miss = @{ 'Nope.us' = $script:Pinned }
        Get-Lines $channels $miss | Should -Be (Get-Lines $channels)
        $a = Get-Manifest $channels
        $b = Get-Manifest $channels $miss
        $b.CandidateManifestHash | Should -Be $a.CandidateManifestHash
        @($b.Manifest.Entries.PresentationFingerprint) | Should -Be @($a.Manifest.Entries.PresentationFingerprint)
    }

    It 'a pinned build changes only the pinned channel logo value and fingerprint' {
        $channels = @(New-TestChannel 'A' $script:Pub; New-TestChannel 'B' $script:Pub)
        $pin = @{ 'A.us' = $script:Pinned }
        $before = Get-Lines $channels
        $after = Get-Lines $channels $pin
        $b = @($before -split "`n"); $a = @($after -split "`n")
        $b.Count | Should -Be $a.Count
        $diff = @(0..($b.Count - 1) | Where-Object { $b[$_] -ne $a[$_] })
        $diff.Count | Should -Be 1
        $a[$diff[0]] | Should -Match 'A\b.*pinned.png|pinned.png.*A\b'
        $m0 = Get-Manifest $channels
        $m1 = Get-Manifest $channels $pin
        $m1.CandidateManifestHash | Should -Not -Be $m0.CandidateManifestHash
        $f0 = @($m0.Manifest.Entries.PresentationFingerprint); $f1 = @($m1.Manifest.Entries.PresentationFingerprint)
        $f1[0] | Should -Not -Be $f0[0]
        $f1[1] | Should -Be $f0[1]
    }
}

Describe 'Logo pin file at build time' {
    It 'reads a good pin file into an exact map' {
        $r = New-Root
        Set-ChannelForgeLogoPin -TvgId 'A.us' -Logo $script:Pinned -RepositoryRoot $r | Out-Null
        $map = & (Get-Module ChannelForge) { param($r) Get-ChannelForgeLogoPinMap -RepositoryRoot $r } $r
        $map['A.us'] | Should -Be $script:Pinned
        $map.ContainsKey('a.us') | Should -BeFalse
    }

    It 'a missing file gives no pins and no warning' {
        $r = New-Root
        $map = & (Get-Module ChannelForge) { param($r) Get-ChannelForgeLogoPinMap -RepositoryRoot $r } $r 3>&1
        @($map | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
    }

    It 'a corrupt file applies nothing, warns loudly, leaves the file alone, and every channel still builds' {
        $r = New-Root
        New-Item -ItemType Directory -Path (Join-Path $r 'state') | Out-Null
        $file = Join-Path $r 'state\logo-pins.json'
        [IO.File]::WriteAllText($file, '{ not json')
        $bytes = [IO.File]::ReadAllBytes($file)
        $out = & (Get-Module ChannelForge) { param($r) Get-ChannelForgeLogoPinMap -RepositoryRoot $r } $r 3>&1
        $warn = @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        "$($warn[0])" | Should -Match 'Logo pins unreadable: .* No pin was applied\.'
        $map = @($out | Where-Object { $_ -is [hashtable] })[0]
        $map.Count | Should -Be 0
        $channels = @(New-TestChannel 'A' $script:Pub; New-TestChannel 'B' '')
        (Get-Lines $channels $map) | Should -Be (Get-Lines $channels)
        @((Get-Lines $channels $map) -split "`n" | Where-Object { $_ -like '#EXTINF*' }).Count | Should -Be 2
        [IO.File]::ReadAllBytes($file) | Should -Be $bytes
    }
}
