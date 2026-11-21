BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Global -Force
}

Describe 'Event guide file' {
    It 'holds only the event channels, with every block, and escapes text' {
        $bytes = InModuleScope ChannelForge {
            $day = [datetime]::SpecifyKind([datetime]'2026-11-15', [System.DateTimeKind]::Utc)
            $channel = @(
                [pscustomobject]@{ Id = 'ChannelForge-b'; Name = 'Fight & Co'; Blocks = @(
                        [pscustomobject]@{ Start = $day; Stop = $day.AddHours(18); Title = 'Fight & Co' },
                        [pscustomobject]@{ Start = $day.AddHours(18); Stop = $day.AddHours(24); Title = 'Main <Card>' }) },
                [pscustomobject]@{ Id = 'ChannelForge-a'; Name = 'Match 1'; Blocks = @([pscustomobject]@{ Start = $day; Stop = $day.AddHours(24); Title = 'Match 1' }) })
            ConvertTo-ChannelForgeEventGuideXmltv -Channel $channel
        }
        $bytes[0] | Should -Not -Be 0xEF
        $doc = [xml][Text.Encoding]::UTF8.GetString($bytes)
        @($doc.tv.channel).Count | Should -Be 2
        @($doc.tv.channel)[0].id | Should -Be 'ChannelForge-a'
        @($doc.tv.programme).Count | Should -Be 3
        $second = @($doc.tv.programme | Where-Object { $_.channel -eq 'ChannelForge-b' })[1]
        $second.start | Should -Be '20261115180000 +0000'
        $second.stop | Should -Be '20261116000000 +0000'
        $second.title | Should -Be 'Main <Card>'
    }

    It 'gives an empty but valid guide when there is no event channel' {
        $bytes = InModuleScope ChannelForge { ConvertTo-ChannelForgeEventGuideXmltv -Channel @() }
        $doc = [xml][Text.Encoding]::UTF8.GetString($bytes)
        $doc.SelectNodes("//programme").Count | Should -Be 0
    }

    It 'stays valid XML when a name has control characters and writes UTC for local times' {
        $bytes = InModuleScope ChannelForge {
            $local = [datetime]::SpecifyKind([datetime]'2026-11-15 20:00', [System.DateTimeKind]::Local)
            $channel = @([pscustomobject]@{ Id = 'ChannelForge-a'; Name = "Match$([char]7) 1"; Blocks = @([pscustomobject]@{ Start = $local; Stop = $local.AddHours(2); Title = 'Match 1' }) })
            ConvertTo-ChannelForgeEventGuideXmltv -Channel $channel
        }
        $doc = [xml][Text.Encoding]::UTF8.GetString($bytes)
        $doc.tv.channel.'display-name' | Should -Be 'Match  1'
        $expected = ([datetime]::SpecifyKind([datetime]'2026-11-15 20:00', [System.DateTimeKind]::Local)).ToUniversalTime().ToString("yyyyMMddHHmmss '+0000'", [cultureinfo]::InvariantCulture)
        $doc.tv.programme.start | Should -Be $expected
    }
}
