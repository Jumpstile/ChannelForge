BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'
    $script:TempRoot = Join-Path ([io.path]::GetTempPath()) "channelforge-xmltv-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

    function New-GzipFixture {
        param([string]$Destination)

        $inputBytes = [io.file]::ReadAllBytes($script:FixturePath)
        $file = [io.filestream]::new($Destination, [io.filemode]::Create, [io.fileaccess]::Write, [io.fileshare]::None)
        try {
            $gzip = [io.compression.gzipstream]::new($file, [io.compression.compressionmode]::Compress)
            try {
                $gzip.Write($inputBytes, 0, $inputBytes.Length)
            }
            finally {
                $gzip.Dispose()
            }
        }
        finally {
            $file.Dispose()
        }
    }

    function New-ZipFixture {
        param([string]$Destination, [int]$EntryCount = 1)

        $inputBytes = [io.file]::ReadAllBytes($script:FixturePath)
        $file = [io.filestream]::new($Destination, [io.filemode]::Create, [io.fileaccess]::Write, [io.fileshare]::None)
        try {
            $archive = [io.compression.ziparchive]::new($file, [io.compression.ziparchivemode]::Create)
            try {
                for ($i = 0; $i -lt $EntryCount; $i++) {
                    $entry = $archive.CreateEntry("sample-$i.xml")
                    $entryStream = $entry.Open()
                    try {
                        $entryStream.Write($inputBytes, 0, $inputBytes.Length)
                    }
                    finally {
                        $entryStream.Dispose()
                    }
                }
            }
            finally {
                $archive.Dispose()
            }
        }
        finally {
            $file.Dispose()
        }
    }

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

AfterAll {
    Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Compressed XMLTV ingestion' {
    It 'detects bytes beyond the configured bound without buffering the full stream' {
        InModuleScope ChannelForge {
            $inner = [io.memorystream]::new([byte[]](1, 2, 3, 4, 5, 6))
            $bounded = [BoundedStream]::new($inner, 4)
            try {
                $buffer = [byte[]]::new(4)
                $bounded.Read($buffer, 0, $buffer.Length) | Should -Be 4
                { $bounded.EnsureWithinLimit() } | Should -Throw '*maximum*'
            }
            finally {
                $bounded.Dispose()
            }
        }
    }

    It 'produces the same programmes for plain XML, gzip, and zip content' {
        $gzipPath = Join-Path $script:TempRoot 'sample.xml.gz'
        $zipPath = Join-Path $script:TempRoot 'sample.zip'
        New-GzipFixture -Destination $gzipPath
        New-ZipFixture -Destination $zipPath

        $plain = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'fixture')
        $gzip = @(Import-ChannelForgeXmltvSource -Path $gzipPath -SourceId 'fixture')
        $zip = @(Import-ChannelForgeXmltvSource -Path $zipPath -SourceId 'fixture')

        (Get-CanonicalProgrammeJson $plain) | Should -Be (Get-CanonicalProgrammeJson $gzip)
        (Get-CanonicalProgrammeJson $plain) | Should -Be (Get-CanonicalProgrammeJson $zip)
    }

    It 'records the selected compression in evidence without changing programme data' {
        $gzipPath = Join-Path $script:TempRoot 'evidence.xml.gz'
        $zipPath = Join-Path $script:TempRoot 'evidence.zip'
        New-GzipFixture -Destination $gzipPath
        New-ZipFixture -Destination $zipPath

        $gzip = @(Import-ChannelForgeXmltvSource -Path $gzipPath -SourceId 'fixture')
        $zip = @(Import-ChannelForgeXmltvSource -Path $zipPath -SourceId 'fixture')

        $gzip[0].Evidence.Compression | Should -Be 'gzip'
        $zip[0].Evidence.Compression | Should -Be 'zip'
        $gzip[0].Evidence.Format | Should -Be 'xmltv'
        $zip[0].Evidence.Format | Should -Be 'xmltv'
    }

    It 'rejects a zip archive with ambiguous multiple file entries' {
        $zipPath = Join-Path $script:TempRoot 'multiple.zip'
        New-ZipFixture -Destination $zipPath -EntryCount 2

        { Import-ChannelForgeXmltvSource -Path $zipPath -SourceId 'fixture' } | Should -Throw '*exactly one file entry*'
    }
}
