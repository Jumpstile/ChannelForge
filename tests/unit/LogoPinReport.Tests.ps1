BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:Pub = 'https://img.example.com/a.png'
    $script:Pinned = 'https://img.example.com/pinned.png'

    function New-TestChannel {
        param([string]$Name, [string]$Logo, [string]$TvgId = "$Name.us")
        New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName $Name -DisplayName $Name -TvgId $TvgId -Url "https://stream.example.com/$Name" -Group 'Sports' -Logo $Logo
    }
    function Get-Report {
        param([object[]]$Channel, [hashtable]$Pin = @{}, [string]$Root = '')
        & (Get-Module ChannelForge) {
            param($ch, $pin, $root)
            $published = @(Get-ChannelForgePublishLogo -Channel @($ch) -LogoPin $pin)
            if ($root) { Get-ChannelForgeLogoReport -Channel $published -LogoPin $pin -PinRead (Read-ChannelForgeLogoPin -RepositoryRoot $root) }
            else { Get-ChannelForgeLogoReport -Channel $published -LogoPin $pin }
        } $Channel $Pin $Root
    }
    function New-Root { $r = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $r | Out-Null; $r }
}

Describe 'Logo report: pins' {
    It 'counts pinned channels and lists an unused pin by TvgId' {
        $r = Get-Report @((New-TestChannel 'A' ''), (New-TestChannel 'B' $script:Pub)) @{ 'A.us' = $script:Pinned; 'ESPN2.us' = $script:Pinned }
        $r.Pinned | Should -Be 1
        @($r.PinsUnused) | Should -Be @('ESPN2.us')
        $r.PinsStatus | Should -Be 'Ok'
        $r.Warning | Should -Be 'Logo pins: 1 applied, 1 unused (ESPN2.us).'
        $r.Warning | Should -Not -Match 'pinned\.png'
    }

    It 'reports a corrupt pin file as Corrupt with the problem and no link' {
        $root = New-Root
        New-Item -ItemType Directory -Path (Join-Path $root 'state') | Out-Null
        $doc = '{"Version":"logo-identity/v1","Pins":[{"TvgId":"A.us","Logo":"http://secret.example.com/x.png","Source":"user","PinnedAtUtc":"2026-01-01T00:00:00Z"}]}'
        [IO.File]::WriteAllText((Join-Path $root 'state\logo-pins.json'), $doc)
        $r = Get-Report @(New-TestChannel 'A' $script:Pub) @{} $root
        $r.PinsStatus | Should -Be 'Corrupt'
        @($r.PinsIgnored).Count | Should -Be 1
        $r.Pinned | Should -Be 0
        ($r | ConvertTo-Json -Depth 5) | Should -Not -Match 'secret\.example'
        $r.Warning | Should -Match '^Logo pins: file unreadable, none applied \('
    }

    It 'puts the pin hint once on the Logo check warning, not once per channel' {
        $r = Get-Report @((New-TestChannel 'A' ''), (New-TestChannel 'B' ''), (New-TestChannel 'C' 'http://x.example.com/c.png'))
        $r.Warning | Should -Match '^Logo check: 3 of 3 channels'
        ([regex]::Matches($r.Warning, [regex]::Escape('Pin one with Set-ChannelForgeLogoPin.'))).Count | Should -Be 1
    }

    It 'adds no pin line and no hint when all logos are public and there are no pins' {
        $r = Get-Report @(New-TestChannel 'A' $script:Pub)
        $r.Warning | Should -BeNullOrEmpty
        $r.PinsStatus | Should -Be 'Missing'
        $r.Pinned | Should -Be 0
        @($r.PinsUnused).Count | Should -Be 0
    }
}

Describe 'Logo report reaches the review before accept' {
    It 'returns the report on the single-source proposal and does not change the candidate hash' {
        $root = New-Root
        foreach ($d in 'data\rules', 'data\lineup') { New-Item -ItemType Directory -Force -Path (Join-Path $root $d) | Out-Null }
        Copy-Item (Join-Path $RepoRoot 'data\rules\aliases.json') (Join-Path $root 'data\rules')
        Copy-Item (Join-Path $RepoRoot 'data\lineup\numbering_blocks.json') (Join-Path $root 'data\lineup')
        $m3u = Join-Path $root 'data\one.m3u'
        $text = "#EXTM3U`n#EXTINF:-1 tvg-id=`"A.us`" group-title=`"Sports`",A`nhttps://stream.example.com/A`n"
        [IO.File]::WriteAllText($m3u, $text)

        $first = New-ChannelForgeCandidateProposal -Root $root -M3UPath $m3u -OutputRoot (Join-Path $root 'out1') -WarningAction SilentlyContinue
        $first.LogoReport.Warning | Should -Match 'Logo check: 1 of 1 channels have no public https logo'
        $first.LogoReport.Warning | Should -Match 'Pin one with Set-ChannelForgeLogoPin\.'

        # A pin that matches no channel is reported but must not change any byte of the build.
        Set-ChannelForgeLogoPin -TvgId 'ESPN2.us' -Logo $script:Pinned -RepositoryRoot $root | Out-Null
        $second = New-ChannelForgeCandidateProposal -Root $root -M3UPath $m3u -OutputRoot (Join-Path $root 'out2') -WarningAction SilentlyContinue
        $second.CandidateManifestHash | Should -Be $first.CandidateManifestHash
        $second.LogoReport.Warning | Should -Match 'Logo pins: 1 unused \(ESPN2\.us\)\.'
    }
}
