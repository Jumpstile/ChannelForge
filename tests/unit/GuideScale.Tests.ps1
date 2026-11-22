BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force

    # A real guide lists every channel first, then every programme. Build a small one of that shape.
    $script:ItemCount = 2000
    $script:GuidePath = Join-Path ([System.IO.Path]::GetTempPath()) ("cf-guide-scale-" + [guid]::NewGuid().ToString('N') + '.xml')
    $xml = [System.Text.StringBuilder]::new()
    [void]$xml.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$xml.AppendLine('<tv>')
    for ($i = 0; $i -lt $script:ItemCount; $i++) {
        [void]$xml.AppendLine("  <channel id=`"fx$i.test`"><display-name>Fixture $i</display-name></channel>")
    }
    for ($i = 0; $i -lt $script:ItemCount; $i++) {
        $hour = $i % 24
        $start = '202601{0:00}{1:00}0000 +0000' -f (1 + [int][math]::Floor($i / 24) % 28), $hour
        $stop = '202601{0:00}{1:00}3000 +0000' -f (1 + [int][math]::Floor($i / 24) % 28), $hour
        [void]$xml.AppendLine("  <programme start=`"$start`" stop=`"$stop`" channel=`"fx$i.test`"><title>Show $i</title></programme>")
    }
    [void]$xml.AppendLine('</tv>')
    [System.IO.File]::WriteAllText($script:GuidePath, $xml.ToString(), [System.Text.UTF8Encoding]::new($false))
}

AfterAll {
    Remove-Item -LiteralPath $script:GuidePath -Force -ErrorAction SilentlyContinue
}

Describe 'Guide steps on a many-channel guide' {
    It 'reads, merges and binds 2000 channels and programmes in linear time' {
        $elapsed = Measure-Command {
            $programmes = @(Import-ChannelForgeXmltvSource -Path $script:GuidePath -SourceId 'fixture')
            $merge = Merge-ChannelForgeXmltvProgrammes -Programme $programmes
            $binding = InModuleScope ChannelForge -Parameters @{ Programmes = $programmes; Count = $script:ItemCount } {
                param($Programmes, $Count)
                $channels = foreach ($i in 0..($Count - 1)) {
                    $channel = [Channel]::new()
                    $channel.TvgId = "fx$i.test"
                    $channel.DisplayName = "Fixture $i"
                    $channel
                }
                Resolve-ChannelForgeM3UXmltvBinding -Channel @($channels) -Programme $Programmes
            }
        }

        $programmes.Count | Should -Be $script:ItemCount
        @($merge.BoundProgrammes).Count | Should -Be $script:ItemCount
        @($binding.ExactBindings).Count | Should -Be $script:ItemCount
        $elapsed.TotalSeconds | Should -BeLessThan 120
    }
}
