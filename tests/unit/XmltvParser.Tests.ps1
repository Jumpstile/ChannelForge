BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'

    function Get-CanonicalProgrammeJson {
        param([object[]]$Programmes)

        return @(
            $Programmes | ForEach-Object {
                [ordered]@{
                    ChannelId     = $_.ChannelId
                    Start         = $_.Start.ToString('o', [cultureinfo]::InvariantCulture)
                    End           = $_.End.ToString('o', [cultureinfo]::InvariantCulture)
                    Title         = $_.Title
                    Subtitle      = $_.Subtitle
                    Description   = $_.Description
                    Categories    = @($_.Categories)
                    EpisodeNumber = $_.EpisodeNumber
                    IsNew         = $_.IsNew
                    IsLive        = $_.IsLive
                    IsPremiere    = $_.IsPremiere
                    SourceId      = $_.SourceId
                } | ConvertTo-Json -Depth 5 -Compress
            }
        ) -join "`n"
    }
}

Describe 'Import-ChannelForgeXmltvSource' {
    It 'parses XMLTV programmes through the local-file entry point' {
        $programmes = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'fixture')

        $programmes.Count | Should -Be 2
        $programmes[0].ChannelId | Should -Be 'news.us'
        $programmes[0].Title | Should -Be 'Morning News'
        $programmes[0].Categories | Should -Be @('News')
        $programmes[0].IsNew | Should -BeTrue
        $programmes[1].ChannelId | Should -Be 'sports.us'
        $programmes[1].Subtitle | Should -Be 'Opening Match'
        $programmes[1].EpisodeNumber | Should -Be 'S01E01'
        $programmes[1].IsLive | Should -BeTrue
    }

    It 'produces identical programme structure and ordering on repeated parses' {
        $first = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'fixture')
        $second = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'fixture')

        (Get-CanonicalProgrammeJson $first) | Should -Be (Get-CanonicalProgrammeJson $second)
    }

    It 'accepts only local XMLTV file paths and exposes no URL parameter' {
        $parameterNames = @((Get-Command Import-ChannelForgeXmltvSource).Parameters.Keys)

        $parameterNames | Should -Not -Contain 'Url'
        $parameterNames | Should -Not -Contain 'Uri'
        { Import-ChannelForgeXmltvSource -Path 'https://example.invalid/guide.xml' } | Should -Throw '*local file paths*'
    }

    It 'rejects a DTD before parsing untrusted XML' {
        $path = Join-Path ([io.path]::GetTempPath()) "channelforge-dtd-$([guid]::NewGuid().ToString('N')).xml"
        $xml = @'
<?xml version="1.0"?>
<!DOCTYPE tv [<!ENTITY xxe "blocked">]>
<tv><channel id="x"><display-name>&xxe;</display-name></channel></tv>
'@

        try {
            Set-Content -LiteralPath $path -Value $xml -Encoding utf8
            { Import-ChannelForgeXmltvSource -Path $path -SourceId 'dtd-fixture' } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'enforces a bounded source document size' {
        { Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'fixture' -MaxDocumentBytes 128 } | Should -Throw '*maximum*'
    }

    It 'uses XmlReader settings and does not load an XML DOM' {
        $readerPath = Join-Path $RepoRoot 'src\ChannelForge\Private\Read-ChannelForgeXmltvDocument.ps1'
        $readerSource = Get-Content -Raw -LiteralPath $readerPath

        $readerSource | Should -Match 'XmlReader.*::Create'
        $readerSource | Should -Match 'DtdProcessing.*Prohibit'
        $readerSource | Should -Match 'XmlResolver.*\$null'
        $readerSource | Should -Not -Match 'XmlDocument|Select-Xml|ReadOuterXml'
    }
}
