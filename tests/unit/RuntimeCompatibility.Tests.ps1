BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1'
    $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath

    Import-Module $script:ManifestPath -Force
}

Describe 'ChannelForge runtime contract' {
    It 'runs on PowerShell 7.6 or newer' {
        [version]$PSVersionTable.PSVersion | Should -BeGreaterOrEqual ([version]'7.6')
    }

    It 'runs on PowerShell Core' {
        $PSVersionTable.PSEdition | Should -Be 'Core'
    }

    It 'runs on .NET 10 or newer' {
        [version][System.Environment]::Version | Should -BeGreaterOrEqual ([version]'10.0')
    }

    It 'imports the module under the supported runtime' {
        { Import-Module $script:ManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        Get-Module -Name ChannelForge | Should -Not -BeNullOrEmpty
    }

    It 'keeps the manifest runtime floor aligned with the executing runtime contract' {
        [version]$script:Manifest.PowerShellVersion | Should -Be ([version]'7.6')
        $script:Manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'continues to parse a local M3U under the supported runtime' {
        $fixturePath = Join-Path $RepoRoot 'tests\fixtures\tiny.m3u'

        $channels = @(Import-ChannelForgeM3UPlaylist -Path $fixturePath -Provider 'runtime-fixture' -Playlist 'tiny')

        $channels.Count | Should -Be 3
    }

    It 'continues to parse local XMLTV under the supported runtime' {
        $fixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'

        $programmes = @(Import-ChannelForgeXmltvSource -Path $fixturePath -SourceId 'runtime-fixture')

        $programmes.Count | Should -Be 2
    }
}
