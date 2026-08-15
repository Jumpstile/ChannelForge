BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'
}

Describe 'XMLTV evidence records' {
    It 'attaches deterministic provenance and parse totals to every programme' {
        $programmes = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'fixture')

        $programmes[0].Evidence | Should -Be $programmes[1].Evidence
        $evidence = $programmes[0].Evidence
        $evidence.EvidenceType | Should -Be 'xmltv-source'
        $evidence.SourceId | Should -Be 'fixture'
        $evidence.SourcePath | Should -Be ([io.path]::GetFullPath($script:FixturePath))
        $evidence.Format | Should -Be 'xmltv'
        $evidence.Compression | Should -Be 'none'
        $evidence.ProgrammeCount | Should -Be 2
        $evidence.ChannelCount | Should -Be 2
        $evidence.DocumentBytes | Should -BeGreaterThan 0
        @($evidence.PSObject.Properties.Name) | Should -Not -Contain 'CapturedAt'
    }

    It 'constructs a validated evidence record without a cache or refresh status' {
        InModuleScope ChannelForge {
            $record = New-ChannelForgeXmltvEvidenceRecord `
                -SourceId 'fixture' `
                -SourcePath 'tests\fixtures\xmltv\sample.xml' `
                -Compression 'gzip' `
                -ProgrammeCount 2 `
                -ChannelCount 2 `
                -DocumentBytes 123

            $record.EvidenceType | Should -Be 'xmltv-source'
            $record.Format | Should -Be 'xmltv'
            $record.Compression | Should -Be 'gzip'
            @($record.PSObject.Properties.Name) | Should -Not -Contain 'CachePath'
            @($record.PSObject.Properties.Name) | Should -Not -Contain 'RefreshStatus'
        }
    }

    It 'rejects invalid evidence identifiers and negative totals' {
        InModuleScope ChannelForge {
            { New-ChannelForgeXmltvEvidenceRecord -SourceId '' -SourcePath 'sample.xml' -ProgrammeCount 0 -ChannelCount 0 -DocumentBytes 0 } | Should -Throw
            { New-ChannelForgeXmltvEvidenceRecord -SourceId 'fixture' -SourcePath 'sample.xml' -ProgrammeCount -1 -ChannelCount 0 -DocumentBytes 0 } | Should -Throw
        }
    }
}
