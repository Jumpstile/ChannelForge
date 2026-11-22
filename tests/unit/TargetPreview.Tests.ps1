BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function script:New-PreviewChannels {
        $a = New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'Alpha' -DisplayName 'Alpha' -TvgId 'alpha.invalid' -Url 'https://example.invalid/a' -Group 'News' -Logo 'https://example.invalid/a.png'
        $a.AssignedNumber = 101
        $b = New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'Beta' -DisplayName 'Beta' -TvgId 'beta.invalid' -Url 'https://example.invalid/b' -Group ''
        @($a, $b)
    }
    function script:Get-Preview {
        param([string]$Profile, $Channel)
        & (Get-Module ChannelForge) { param($p, $c) Get-ChannelForgeTargetPreview -Profile $p -Channel $c } $Profile $Channel
    }
}

Describe 'Get-ChannelForgeTargetPreview' {
    It 'reports <p> with unknown, never supported, where the profile has no evidence' -ForEach @(
        @{ p = 'plex' }, @{ p = 'iptvboss' }, @{ p = 'dispatcharr' }
    ) {
        $report = Get-Preview $p (New-PreviewChannels)
        $report.Profile | Should -Be $p
        $report.ChannelCount | Should -Be 2
        $chno = $report.Attributes | Where-Object Attribute -eq 'tvg-chno'
        $chno.Status | Should -Be 'unknown'
        $chno.ChannelsWithValue | Should -Be 1
        ($report.Attributes | Where-Object Attribute -eq 'group-title').ChannelsWithValue | Should -Be 1
        ($report.Attributes.Status -contains 'supported') | Should -BeFalse
    }

    It 'repeats the profile words and evidence when the profile has a claim' {
        $logo = (Get-Preview 'plex' (New-PreviewChannels)).Attributes | Where-Object Attribute -eq 'tvg-logo'
        $logo.Evidence | Should -Be 'reported'
        $logo.ProfileSays | Should -BeLike '*public https*'
    }

    It 'reports would-be-ignored when the profile says a field is ignored' {
        $p = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'data\compatibility\plex.profile.json') -Raw | ConvertFrom-Json
        $p.capabilities.tvg_chno.value = 'Ignored by this target.'
        $p.capabilities.tvg_chno.evidence.state = 'documented'
        $path = Join-Path $TestDrive 'ignored.json'
        $p | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
        $report = & (Get-Module ChannelForge) { param($f, $c) Get-ChannelForgeTargetPreview -Profile 'plex' -Channel $c -ProfilePath $f } $path (New-PreviewChannels)
        $chno = $report.Attributes | Where-Object Attribute -eq 'tvg-chno'
        $chno.Status | Should -Be 'would-be-ignored'
        $chno.ChannelsWithValue | Should -Be 1
    }

    It 'fails with a plain message for a profile that does not exist' {
        { Get-Preview 'nope' (New-PreviewChannels) } | Should -Throw '*not found*'
    }

    It 'leaves the published M3U bytes identical with and without the preview' {
        $before = Join-Path $TestDrive 'before.m3u'
        $after = Join-Path $TestDrive 'after.m3u'
        $channels = New-PreviewChannels
        $channels | Export-ChannelForgeM3UPlaylist -Path $before
        foreach ($name in 'plex', 'iptvboss', 'dispatcharr') { $null = Get-Preview $name $channels }
        $channels | Export-ChannelForgeM3UPlaylist -Path $after
        (Get-FileHash -LiteralPath $after).Hash | Should -Be (Get-FileHash -LiteralPath $before).Hash
    }
}
