BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    # Eight channels with one programme each; the padding makes the guide bigger than the test limit.
    $script:GuideText = @(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<tv generator-info-name="test">'
        foreach ($n in 1..8) {
            "<channel id=`"ch$n.us`"><display-name>Channel $n</display-name></channel>"
            "<programme start=`"20260101000000 +0000`" stop=`"20260101010000 +0000`" channel=`"ch$n.us`"><title>Show $n</title><desc>$('x' * 400)</desc></programme>"
        }
        '</tv>'
    ) -join "`n"
    $script:Limit = 3000

    function New-GuideFile {
        param([string]$Name)
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $path = Join-Path $dir $Name
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($script:GuideText)
        if ($Name.EndsWith('.gz')) {
            $fs = [IO.File]::Create($path)
            $gz = [IO.Compression.GZipStream]::new($fs, [IO.Compression.CompressionMode]::Compress)
            $gz.Write($bytes, 0, $bytes.Length); $gz.Dispose(); $fs.Dispose()
        }
        else { [IO.File]::WriteAllBytes($path, $bytes) }
        $path
    }
}

Describe 'Guide trim (guide-trim/v2)' {
    It 'trims a guide over the limit to the playlist channels, for .xml and .gz' {
        foreach ($name in 'guide.xml', 'guide.xml.gz') {
            $path = New-GuideFile $name
            $tempRoot = Join-Path $TestDrive 'staging'
            $status = [ordered]@{}
            $programmes = @(Import-ChannelForgeXmltvSource -Path $path -MaxDocumentBytes $script:Limit -AcquisitionStatus $status `
                    -TrimToChannelId @('ch2.us', 'ch5.us', 'not-in-guide.us') -TrimTempRoot $tempRoot)
            @($programmes.ChannelId | Sort-Object -Unique) | Should -Be @('ch2.us', 'ch5.us')
            $status.GuideTrim.KeptChannelCount | Should -Be 2
            $status.GuideTrim.GuideChannelCount | Should -Be 8
            $status.GuideTrim.OriginalBytes | Should -BeGreaterThan $script:Limit
            $status.GuideTrim.KeptBytes | Should -BeLessThan $script:Limit
            $status.InputArtifactHash | Should -Match '^[0-9a-f]{64}$'
            @(Get-ChildItem -LiteralPath $tempRoot -File).Count | Should -Be 0
            $bind = Resolve-ChannelForgeM3UXmltvBinding -Channel @(New-ChannelForgeChannel -Provider 'p' -Playlist 'l' -OriginalName 'Two' -DisplayName 'Two' -TvgId 'ch2.us' -Url 'http://s.example.com/2' -Group 'G') -Programme $programmes
            @($bind.ExactBindings).Count | Should -Be 1
        }
    }

    It 'gives the same result as before for a guide at or under the limit' {
        $path = New-GuideFile 'guide.xml'
        $plain = [ordered]@{}; $withTrim = [ordered]@{}
        $a = @(Import-ChannelForgeXmltvSource -Path $path -AcquisitionStatus $plain)
        $b = @(Import-ChannelForgeXmltvSource -Path $path -AcquisitionStatus $withTrim -TrimToChannelId @('ch2.us') -TrimTempRoot (Join-Path $TestDrive 'unused'))
        $b.Count | Should -Be $a.Count
        $withTrim.InputArtifactHash | Should -Be $plain.InputArtifactHash
        $withTrim.Contains('GuideTrim') | Should -BeFalse
        Test-Path (Join-Path $TestDrive 'unused') | Should -BeFalse
    }

    It 'says plainly when the trimmed guide is still over the limit' {
        $path = New-GuideFile 'guide.xml'
        $ids = @(1..8 | ForEach-Object { "ch$_.us" })
        { Import-ChannelForgeXmltvSource -Path $path -MaxDocumentBytes $script:Limit -TrimToChannelId $ids -TrimTempRoot (Join-Path $TestDrive 'staging2') } |
            Should -Throw '*still too big*8 playlist channels matched*'
    }
}
