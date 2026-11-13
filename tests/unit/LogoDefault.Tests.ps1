BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function New-TestChannel {
        param([string]$Name, [string]$Logo, [string]$Group = 'Sports')
        New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName $Name -DisplayName $Name -TvgId "$Name.us" -Url "https://stream.example.com/$Name" -Group $Group -Logo $Logo
    }
    function Export-Test {
        param([object[]]$Channel, [hashtable]$Default = @{})
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.m3u')
        $Channel | Export-ChannelForgeM3UPlaylist -Path $path -GroupDefaultLogo $Default -WarningVariable w -WarningAction SilentlyContinue
        [pscustomobject]@{ Text = [IO.File]::ReadAllText($path); Warnings = @($w) }
    }
    $script:Default = @{ Sports = 'https://img.example.com/sports.png' }
}

Describe 'Group default logo' {
    It 'keeps a public logo and replaces empty, http and private logos with the group default' {
        $channels = @(
            New-TestChannel 'Pub' 'https://img.example.com/pub.png'
            New-TestChannel 'Empty' ''
            New-TestChannel 'Http' 'http://img.example.com/a.png'
            New-TestChannel 'Lan' 'https://192.168.1.9/a.png'
        )
        $r = Export-Test $channels $script:Default
        $lines = $r.Text -split "`n" | Where-Object { $_ -like '#EXTINF*' }
        $lines.Count | Should -Be 4
        $lines[0] | Should -Match 'tvg-logo="https://img.example.com/pub.png"'
        $lines[1..3] | ForEach-Object { $_ | Should -Match 'tvg-logo="https://img.example.com/sports.png"' }
        $r.Warnings -join ' ' | Should -Match '3 channels use their group default'
        $channels[3].Logo | Should -Be 'https://192.168.1.9/a.png'
    }

    It 'writes no tvg-logo for a non-public logo when the group has no default, and lists it' {
        $r = Export-Test @(New-TestChannel 'Lan' 'https://10.0.0.5/a.png' 'News') $script:Default
        $r.Text | Should -Not -Match 'tvg-logo'
        $r.Text | Should -Match 'Lan'
        $r.Warnings -join ' ' | Should -Match 'Empty: Lan'
    }

    It 'ignores a bad group default with a warning and keeps every channel' {
        $r = Export-Test @(New-TestChannel 'A' '' ; New-TestChannel 'B' 'https://img.example.com/b.png') @{ Sports = 'http://10.0.0.1/x.png' }
        ($r.Text -split "`n" | Where-Object { $_ -like '#EXTINF*' }).Count | Should -Be 2
        $r.Text | Should -Not -Match 'x\.png'
        $r.Warnings -join ' ' | Should -Match "Group default logo for 'Sports' ignored"
    }

    It 'leaves the M3U bytes of an all-public lineup identical with or without a default' {
        $channels = @(New-TestChannel 'A' 'https://img.example.com/a.png'; New-TestChannel 'B' 'https://img.example.com/b.png')
        (Export-Test $channels $script:Default).Text | Should -BeExactly (Export-Test $channels).Text
    }
}
