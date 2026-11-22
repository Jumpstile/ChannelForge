BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    function Get-RoundTripText {
        param([string]$Root, [string]$Body)

        $inPath = Join-Path $Root 'in.xml'
        $outPath = Join-Path $Root 'out.xml'
        $xml = '<?xml version="1.0" encoding="UTF-8"?><tv><channel id="a.one"><display-name>A One</display-name></channel>' +
            '<programme start="20260815120000 +0000" stop="20260815130000 +0000" channel="a.one"><title>Show</title>' +
            $Body + '</programme></tv>'
        [System.IO.File]::WriteAllText($inPath, $xml, [System.Text.UTF8Encoding]::new($false))
        $source = [pscustomobject]@{ Name = 'kept'; Path = $inPath; Url = ''; Format = 'xmltv'; Supported = $true }
        $programmes = @(Import-ChannelForgeConfiguredXmltvSource -Source $source)
        $merged = Merge-ChannelForgeXmltvProgrammes -Programme $programmes
        Export-ChannelForgeXmltv -MergeResult $merged -Path $outPath -AllowedRoot $Root
        return [System.IO.File]::ReadAllText($outPath)
    }
}

Describe 'XMLTV kept tags previously-shown and date' {
    It 'keeps date and previously-shown with start in XMLTV order' {
        $text = Get-RoundTripText -Root $TestDrive -Body '<desc>D</desc><date>20240102</date><category>News</category><episode-num system="onscreen">S1E1</episode-num><previously-shown start="20240101000000 +0000"/><new/>'
        $text | Should -Match '(?s)<desc>D</desc>\s*<date>20240102</date>\s*<category>News</category>'
        $text | Should -Match '(?s)</episode-num>\s*<previously-shown start="20240101000000 \+0000" />\s*<new />'
    }

    It 'keeps previously-shown without a start attribute' {
        $text = Get-RoundTripText -Root $TestDrive -Body '<previously-shown/>'
        $text | Should -Match '<previously-shown />'
    }

    It 'adds nothing for guides without the tags' {
        $text = Get-RoundTripText -Root $TestDrive -Body '<desc>D</desc><new/>'
        $text | Should -Not -Match 'previously-shown'
        $text | Should -Not -Match '<date'
    }

    It 'keeps programmes that differ only by the tags as separate entries' {
        $a = New-ChannelForgeProgramme -ChannelId 'a.one' -Start '2026-08-15T12:00:00Z' -End '2026-08-15T13:00:00Z' -Title 'Show' -SourceId 's1'
        $b = New-ChannelForgeProgramme -ChannelId 'a.one' -Start '2026-08-15T12:00:00Z' -End '2026-08-15T13:00:00Z' -Title 'Show' -SourceId 's1' -PreviouslyShown $true -Date '2024'
        $result = Merge-ChannelForgeXmltvProgrammes -Programme @($a, $b)
        @($result.Conflicts).Count | Should -BeGreaterThan 0
    }
}
