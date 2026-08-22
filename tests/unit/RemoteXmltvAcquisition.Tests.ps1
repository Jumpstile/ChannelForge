BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'

    if (-not ('ChannelForge.Tests.RemoteXmltvTestPayload' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;

namespace ChannelForge.Tests
{
    public sealed class RemoteXmltvTestPayload : IDisposable
    {
        public Stream ResponseStream { get; }
        public int StatusCode { get; }
        public string ContentType { get; }
        public string[] ContentEncodings { get; }
        public long? ContentLength { get; }
        public bool HasPayload { get; }
        public bool Disposed { get; private set; }

        public RemoteXmltvTestPayload(byte[] bytes, string contentType, string[] contentEncodings)
        {
            ResponseStream = new MemoryStream(bytes ?? Array.Empty<byte>(), false);
            StatusCode = 200;
            ContentType = contentType;
            ContentEncodings = contentEncodings ?? Array.Empty<string>();
            ContentLength = bytes == null ? 0L : bytes.LongLength;
            HasPayload = true;
        }

        public void Dispose()
        {
            if (Disposed)
            {
                return;
            }

            Disposed = true;
            ResponseStream.Dispose();
        }
    }
}
'@
    }

    function New-GzipBytes {
        param([byte[]]$Bytes)

        $output = [io.memorystream]::new()
        try {
            $gzip = [io.compression.gzipstream]::new(
                $output,
                [io.compression.compressionmode]::Compress,
                $true)
            try {
                $gzip.Write($Bytes, 0, $Bytes.Length)
            }
            finally {
                $gzip.Dispose()
            }

            return $output.ToArray()
        }
        finally {
            $output.Dispose()
        }
    }

    function New-RemotePayload {
        param(
            [byte[]]$Bytes,
            [string]$ContentType = 'application/xml',
            [string[]]$ContentEncodings = @()
        )

        return [ChannelForge.Tests.RemoteXmltvTestPayload]::new(
            $Bytes,
            $ContentType,
            $ContentEncodings)
    }

    function New-RemoteSource {
        return [pscustomobject]@{
            Name       = 'remote-fixture'
            Priority   = 1
            Url        = 'https://example.invalid/guide.xml'
            Path       = ''
            Format     = 'xmltv'
            SourceKind = 'remote'
            Supported  = $true
        }
    }

    function Set-RemotePayloadMock {
        param([object]$Payload)

        $global:ChannelForgeRemoteXmltvTestPayload = $Payload
        Mock -CommandName Invoke-ChannelForgePinnedHttpXmltvAcquisition `
            -ModuleName ChannelForge `
            -MockWith { $global:ChannelForgeRemoteXmltvTestPayload }
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

Describe 'Remote XMLTV acquisition first slice' {
    It 'rejects non-HTTPS and non-443 endpoints before payload acquisition' {
        InModuleScope ChannelForge {
            { Invoke-ChannelForgePinnedHttpXmltvAcquisition `
                -SourceId 'remote-fixture' `
                -Url 'http://example.invalid/guide.xml' } | Should -Throw '*InvalidEndpoint*'

            { Invoke-ChannelForgePinnedHttpXmltvAcquisition `
                -SourceId 'remote-fixture' `
                -Url 'https://example.invalid:8443/guide.xml' } | Should -Throw '*InvalidEndpoint*'
        }
    }

    It 'streams identity XML through the existing parser and releases the transport owner' {
        $bytes = [io.file]::ReadAllBytes($script:FixturePath)
        $payload = New-RemotePayload -Bytes $bytes
        Set-RemotePayloadMock -Payload $payload

        $remote = @(Import-ChannelForgeConfiguredXmltvSource -Source (New-RemoteSource))
        $local = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'remote-fixture')

        Get-CanonicalProgrammeJson $remote | Should -Be (Get-CanonicalProgrammeJson $local)
        $remote[0].Evidence.SourceKind | Should -Be 'remote'
        $remote[0].Evidence.SourceReference | Should -Be 'remote-fixture'
        $remote[0].Evidence.HttpStatusCode | Should -Be 200
        $remote[0].Evidence.ContentType | Should -Be 'application/xml'
        $remote[0].Evidence.ContentEncodings | Should -Be @()
        $remote[0].Evidence.PSObject.Properties.Name | Should -Not -Contain 'SourcePath'
        $payload.Disposed | Should -BeTrue
    }

    It 'decodes gzip, x-gzip, and repeated supported codings in reverse order' {
        $plainBytes = [io.file]::ReadAllBytes($script:FixturePath)
        $compressedBytes = New-GzipBytes -Bytes $plainBytes
        $doubleCompressedBytes = New-GzipBytes -Bytes $compressedBytes

        foreach ($encodingCase in @(
            [pscustomobject]@{ Bytes = $compressedBytes; Encodings = @('gzip') }
            [pscustomobject]@{ Bytes = $compressedBytes; Encodings = @('x-gzip') }
            [pscustomobject]@{ Bytes = $doubleCompressedBytes; Encodings = @('gzip', 'x-gzip') }
        )) {
            $payload = New-RemotePayload `
                -Bytes $encodingCase.Bytes `
                -ContentEncodings $encodingCase.Encodings
            Set-RemotePayloadMock -Payload $payload

            $remote = @(Import-ChannelForgeConfiguredXmltvSource -Source (New-RemoteSource))
            $local = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'remote-fixture')

            Get-CanonicalProgrammeJson $remote | Should -Be (Get-CanonicalProgrammeJson $local)
            $remote[0].Evidence.Compression | Should -Be 'gzip'
            $payload.Disposed | Should -BeTrue
        }
    }

    It 'rejects non-XML content types and releases the owner' {
        $payload = New-RemotePayload `
            -Bytes ([io.file]::ReadAllBytes($script:FixturePath)) `
            -ContentType 'application/octet-stream'
        Set-RemotePayloadMock -Payload $payload

        { Import-ChannelForgeConfiguredXmltvSource -Source (New-RemoteSource) } |
            Should -Throw '*XML content type*'
        $payload.Disposed | Should -BeTrue
    }

    It 'rejects unsupported content codings and releases the owner' {
        $payload = New-RemotePayload `
            -Bytes ([io.file]::ReadAllBytes($script:FixturePath)) `
            -ContentEncodings @('br')
        Set-RemotePayloadMock -Payload $payload

        { Import-ChannelForgeConfiguredXmltvSource -Source (New-RemoteSource) } |
            Should -Throw '*UnsupportedContentEncoding*'
        $payload.Disposed | Should -BeTrue
    }

    It 'rejects decompressed content beyond the configured bound' {
        $bytes = [text.encoding]::UTF8.GetBytes(
            '<tv><channel id="fixture"/><programme channel="fixture" start="20260815090000 +0000" stop="20260815100000 +0000"><title>' +
            ('x' * 500) +
            '</title></programme></tv>')
        $payload = New-RemotePayload -Bytes $bytes
        Set-RemotePayloadMock -Payload $payload

        { Import-ChannelForgeConfiguredXmltvSource `
            -Source (New-RemoteSource) `
            -MaxDocumentBytes 128 } | Should -Throw '*expanded content exceeded*'
        $payload.Disposed | Should -BeTrue
    }

    It 'rejects malformed or truncated XML after streaming and releases the owner' {
        $payload = New-RemotePayload `
            -Bytes ([text.encoding]::UTF8.GetBytes('<tv><channel id="fixture">'))
        Set-RemotePayloadMock -Payload $payload

        { Import-ChannelForgeConfiguredXmltvSource -Source (New-RemoteSource) } |
            Should -Throw
        $payload.Disposed | Should -BeTrue
    }

    It 'produces identical programmes and deterministic export for identical local and remote bytes' {
        $payload = New-RemotePayload -Bytes ([io.file]::ReadAllBytes($script:FixturePath))
        Set-RemotePayloadMock -Payload $payload

        $remote = @(Import-ChannelForgeConfiguredXmltvSource -Source (New-RemoteSource))
        $local = @(Import-ChannelForgeXmltvSource -Path $script:FixturePath -SourceId 'remote-fixture')

        $localMerge = Merge-ChannelForgeXmltvProgrammes -Programme $local
        $remoteMerge = Merge-ChannelForgeXmltvProgrammes -Programme $remote
        $localPath = Join-Path $TestDrive 'local.xml'
        $remotePath = Join-Path $TestDrive 'remote.xml'
        Export-ChannelForgeXmltv -MergeResult $localMerge -Path $localPath -AllowedRoot $TestDrive
        Export-ChannelForgeXmltv -MergeResult $remoteMerge -Path $remotePath -AllowedRoot $TestDrive

        (Get-FileHash -LiteralPath $localPath -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $remotePath -Algorithm SHA256).Hash
        $payload.Disposed | Should -BeTrue
    }
}
