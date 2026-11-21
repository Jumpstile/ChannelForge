BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    $script:Fixture = @'
#EXTM3U
#EXTINF:-1 tvg-id="a.test" catchup="flussonic" catchup-source="http://h.invalid/arch-{utc}-{duration}/index.m3u8" catchup-days="3",Alpha
http://h.invalid/alpha/user/secret
#EXTINF:-1 tvg-id="b.test" catchup="append" catchup-source="?offset=-${offset}&token=hunter2" catchup-days="7",Beta
http://h.invalid/beta
#EXTINF:-1 tvg-id="c.test" timeshift="2",Gamma
http://h.invalid/gamma
#EXTINF:-1 tvg-id="d.test",Delta
# comment between record and stream
http://h.invalid/delta
'@
}

Describe 'Get-ChannelForgeCatchupReport' {
    BeforeAll {
        $script:Rows = & (Get-Module ChannelForge) {
            param($Text)
            Get-ChannelForgeCatchupReport -Reader ([System.IO.StringReader]::new($Text))
        } $script:Fixture
    }

    It 'gives one row per stream with the right shape and days' {
        @($script:Rows).Count | Should -Be 4
        ($script:Rows | ForEach-Object Shape) -join ',' | Should -Be 'path-template,query-template,declared-only,none'
        ($script:Rows | ForEach-Object { [string]$_.DeclaredDays }) -join ',' | Should -Be '3,7,2,'
        $script:Rows[0].Family | Should -Be 'flussonic'
    }

    It 'says XMLTV history is not proof on every row' {
        @($script:Rows | Where-Object XmltvHistoryIsProof).Count | Should -Be 0
    }

    It 'never shows a URL, user, password or query text' {
        $text = $script:Rows | ConvertTo-Json -Depth 3
        $text | Should -Not -Match 'invalid|secret|hunter2|token|offset'
    }
}
