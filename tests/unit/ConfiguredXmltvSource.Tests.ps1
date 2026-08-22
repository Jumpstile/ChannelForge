BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'
    $script:TempRoot = Join-Path ([io.path]::GetTempPath()) "channelforge-configured-xmltv-$([guid]::NewGuid().ToString('N'))"
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
        param([string]$Destination)

        $inputBytes = [io.file]::ReadAllBytes($script:FixturePath)
        $file = [io.filestream]::new($Destination, [io.filemode]::Create, [io.fileaccess]::Write, [io.fileshare]::None)
        try {
            $archive = [io.compression.ziparchive]::new($file, [io.compression.ziparchivemode]::Create)
            try {
                $entry = $archive.CreateEntry('sample.xml')
                $entryStream = $entry.Open()
                try {
                    $entryStream.Write($inputBytes, 0, $inputBytes.Length)
                }
                finally {
                    $entryStream.Dispose()
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

Describe 'Configured local XMLTV source ingestion' {
    It 'imports configured plain XML, gzip, and single-entry zip through the existing importer' {
        $plainPath = Join-Path $script:TempRoot 'sample.xml'
        $gzipPath = Join-Path $script:TempRoot 'sample.xml.gz'
        $zipPath = Join-Path $script:TempRoot 'sample.zip'
        Copy-Item -LiteralPath $script:FixturePath -Destination $plainPath
        New-GzipFixture -Destination $gzipPath
        New-ZipFixture -Destination $zipPath

        $configPath = Join-Path $script:TempRoot 'epg_sources.json'
        $config = [ordered]@{
            epg_sources = @(
                [ordered]@{ name = 'configured-fixture'; priority = 1; path = 'sample.xml'; enabled = $true; role = 'primary' }
                [ordered]@{ name = 'configured-fixture'; priority = 2; path = 'sample.xml.gz'; enabled = $true; role = 'primary' }
                [ordered]@{ name = 'configured-fixture'; priority = 3; path = 'sample.zip'; enabled = $true; role = 'primary' }
            )
        }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath

        $sources = @(Read-ChannelForgeEpgSource -Path $configPath)
        $plain = @(Import-ChannelForgeConfiguredXmltvSource -Source $sources[0])
        $gzip = @(Import-ChannelForgeConfiguredXmltvSource -Source $sources[1])
        $zip = @(Import-ChannelForgeConfiguredXmltvSource -Source $sources[2])

        $sources.Format | Should -Be @('xmltv', 'xmltv', 'xmltv')
        $sources.Path | Should -Be @($plainPath, $gzipPath, $zipPath)
        (Get-CanonicalProgrammeJson $gzip) | Should -Be (Get-CanonicalProgrammeJson $plain)
        (Get-CanonicalProgrammeJson $zip) | Should -Be (Get-CanonicalProgrammeJson $plain)
        $plain[0].Evidence.Compression | Should -Be 'none'
        $gzip[0].Evidence.Compression | Should -Be 'gzip'
        $zip[0].Evidence.Compression | Should -Be 'zip'
        $plain[0].Evidence.SourceId | Should -Be 'configured-fixture'
        $gzip[0].Evidence.SourceId | Should -Be 'configured-fixture'
        $zip[0].Evidence.SourceId | Should -Be 'configured-fixture'
    }

    It 'keeps URL-backed sources in the normalized remote adapter boundary' {
        $configPath = Join-Path $RepoRoot 'data\epg\epg_sources.json'
        $source = @(Read-ChannelForgeEpgSource -Path $configPath)[0]

        $source.SourceKind | Should -Be 'remote'
        $source.Supported | Should -BeTrue
        $source.Path | Should -Be ''
        $source.UnsupportedReason | Should -Be ''
    }

    It 'rejects normalized sources with no path or an unsupported format' {
        $missingPath = [pscustomobject]@{
            Name = 'missing-path'
            Path = ''
            Url = ''
            Format = 'xmltv'
            Supported = $true
        }
        $unsupported = [pscustomobject]@{
            Name = 'unsupported-format'
            Path = $script:FixturePath
            Url = ''
            Format = 'm3u'
            Supported = $true
        }

        { Import-ChannelForgeConfiguredXmltvSource -Source $missingPath } | Should -Throw '*local path*'
        { Import-ChannelForgeConfiguredXmltvSource -Source $unsupported } | Should -Throw '*unsupported format*'
    }
}
