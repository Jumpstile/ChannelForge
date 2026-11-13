BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    # Returns the presentation fingerprint of one channel in a one-channel lineup.
    function Get-Fingerprint {
        param([string]$Logo, [hashtable]$Default = @{})
        $channel = New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'A' -DisplayName 'A' -TvgId 'a.us' -Url 'https://stream.example.com/a' -Group 'Sports' -Logo $Logo
        & (Get-Module ChannelForge) {
            param($ch, $def)
            $raw = @(Get-ChannelForgeRawM3UProjection -Channel @($ch) -LogicalSourceId ('a' * 64) -CandidateContractVersion 'blocker-2-contract/v7')
            $r = ConvertTo-ChannelForgeCandidateManifest -RawM3UOccurrences $raw -GroupDefaultLogo $def -WarningAction SilentlyContinue
            $r.Manifest.Entries[0].PresentationFingerprint
        } $channel $Default
    }
    $script:Pub = 'https://img.example.com/a.png'
    $script:Def = @{ Sports = 'https://img.example.com/sports.png' }
}

Describe 'Presentation fingerprint uses the published logo' {
    It 'is unchanged for a public logo, with or without a group default' {
        $legacy = & (Get-Module ChannelForge) {
            param($logo)
            Get-ChannelForgeDomainHash -Domain 'safe-tvg-name-fingerprint/v2' -InputObject ([ordered]@{
                Version = 'safe-tvg-name-fingerprint-v2'; TvgName = ''; DisplayName = 'A'; GroupTitle = 'Sports'; Logo = $logo; ChannelNumber = $null
            })
        } $script:Pub
        Get-Fingerprint $script:Pub | Should -Be $legacy
        Get-Fingerprint $script:Pub $script:Def | Should -Be $legacy
    }

    It 'changes when a private logo is replaced by a group default' {
        Get-Fingerprint 'https://10.0.0.5/a.png' $script:Def | Should -Not -Be (Get-Fingerprint 'https://10.0.0.5/a.png')
    }

    It 'changes when the group default changes' {
        $other = @{ Sports = 'https://img.example.com/other.png' }
        Get-Fingerprint '' $script:Def | Should -Not -Be (Get-Fingerprint '' $other)
    }

    It 'treats a private logo with no group default as left out (same as an empty logo)' {
        Get-Fingerprint 'https://10.0.0.5/a.png' | Should -Be (Get-Fingerprint '')
    }
}
