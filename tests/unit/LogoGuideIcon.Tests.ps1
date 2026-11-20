BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'

    function Export-GuideText {
        param([hashtable]$Icons)
        $source = [pscustomobject]@{ Name = 'fixture'; Path = $script:FixturePath; Url = ''; Format = 'xmltv'; Supported = $true }
        $result = Merge-ChannelForgeXmltvProgrammes -Programme @(Import-ChannelForgeConfiguredXmltvSource -Source $source)
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.xml')
        if ($Icons) { Export-ChannelForgeXmltv -MergeResult $result -Path $path -AllowedRoot $TestDrive -IconByChannelRef $Icons }
        else { Export-ChannelForgeXmltv -MergeResult $result -Path $path -AllowedRoot $TestDrive }
        [pscustomobject]@{ Path = $path; Text = [IO.File]::ReadAllText($path); Bytes = [IO.File]::ReadAllBytes($path) }
    }

    # Guide icon map from exact bindings, using fixture channels (example.invalid only).
    function Get-IconMap {
        param([hashtable]$Logos, [hashtable]$Default = @{})
        $bindings = foreach ($id in $Logos.Keys) {
            $ch = New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName $id -DisplayName $id -TvgId $id -Url "https://stream.example.invalid/$id" -Group 'Sports' -Logo $Logos[$id]
            [pscustomobject]@{ M3UChannel = $ch; XmltvChannelId = $id }
        }
        InModuleScope ChannelForge -Parameters @{ B = @($bindings); D = $Default } { param($B, $D) Get-ChannelForgeGuideIconMap -ExactBinding $B -GroupDefaultLogo $D -WarningAction SilentlyContinue }
    }
}

Describe 'Guide file logos' {
    It 'is byte-identical to today when there is no icon map or no entry' {
        $plain = Export-GuideText
        (Export-GuideText -Icons @{}).Bytes | Should -Be $plain.Bytes
        (Export-GuideText -Icons @{ 'other.us' = 'https://img.example.invalid/o.png' }).Bytes | Should -Be $plain.Bytes
        $plain.Text | Should -Not -Match '<icon'
    }

    It 'writes a public https icon after display-name and keeps every channel' {
        $r = Export-GuideText -Icons @{ 'news.us' = 'https://img.example.invalid/news.png' }
        ([regex]::Matches($r.Text, '<icon ')).Count | Should -Be 1
        $r.Text | Should -Match '<display-name>news.us</display-name>\s*<icon src="https://img.example.invalid/news.png" />'
        ([regex]::Matches($r.Text, '<channel id=')).Count | Should -Be 2
    }

    It 'never writes an http or private-address icon' {
        $r = Export-GuideText -Icons @{ 'news.us' = 'http://img.example.invalid/n.png'; 'sports.us' = 'https://192.168.1.9/s.png' }
        $r.Text | Should -Not -Match '<icon'
        ([regex]::Matches($r.Text, '<channel id=')).Count | Should -Be 2
    }

    It 'maps a public logo, and replaces http, private and missing logos with the group default' {
        $default = @{ Sports = 'https://img.example.invalid/sports.png' }
        $map = Get-IconMap -Logos @{ pub = 'https://img.example.invalid/pub.png'; web = 'http://img.example.invalid/w.png'; lan = 'https://10.0.0.5/l.png'; none = '' } -Default $default
        $map['pub'] | Should -Be 'https://img.example.invalid/pub.png'
        'web', 'lan', 'none' | ForEach-Object { $map[$_] | Should -Be 'https://img.example.invalid/sports.png' }
    }

    It 'leaves a channel with no usable logo and no group default without an icon' {
        $map = Get-IconMap -Logos @{ web = 'http://img.example.invalid/w.png'; none = '' }
        $map.Count | Should -Be 0
    }

    It 'gives a name-only placeholder channel its icon and drops no channel' {
        $source = [pscustomobject]@{ Name = 'fixture'; Path = $script:FixturePath; Url = ''; Format = 'xmltv'; Supported = $true }
        $base = Export-GuideText
        $channels = @([pscustomobject]@{ Id = 'own.1'; Name = 'Own One' }, [pscustomobject]@{ Id = 'own.2'; Name = 'Own Two' })
        $bytes = InModuleScope ChannelForge -Parameters @{ X = $base.Bytes; C = $channels } {
            param($X, $C)
            [byte[]](Add-ChannelForgePlaceholderGuide -XmltvBytes $X -Channel $C -TimeZone ([TimeZoneInfo]::Utc) -IconByChannelRef @{ 'own.1' = 'https://img.example.invalid/own.png'; 'own.2' = 'http://img.example.invalid/x.png' } | Select-Object -Last 1)
        }
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        $text | Should -Match '<channel id="own.1"><display-name>Own One</display-name><icon src="https://img.example.invalid/own.png"/></channel>'
        $text | Should -Match '<channel id="own.2"><display-name>Own Two</display-name></channel>'
        ([regex]::Matches($text, '<channel id=')).Count | Should -Be 4
    }
}
