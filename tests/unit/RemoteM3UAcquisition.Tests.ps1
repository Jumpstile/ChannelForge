BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\tiny.m3u'

    if (-not ('ChannelForge.Tests.RemoteM3UTestPayload' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;

namespace ChannelForge.Tests
{
    public sealed class RemoteM3UTestPayload : IDisposable
    {
        public Stream ResponseStream { get; }
        public int StatusCode { get; }
        public string ContentType { get; }
        public string[] ContentEncodings { get; }
        public long? ContentLength { get; }
        public bool HasPayload { get; }
        public string ETag { get; }
        public DateTimeOffset? LastModified { get; }
        public bool Disposed { get; private set; }

        public RemoteM3UTestPayload(byte[] bytes, int statusCode, string contentType, string[] contentEncodings, string etag, DateTimeOffset? lastModified)
        {
            StatusCode = statusCode;
            ContentType = contentType;
            ContentEncodings = contentEncodings ?? Array.Empty<string>();
            ETag = etag;
            LastModified = lastModified;
            if (statusCode == 200)
            {
                ResponseStream = new MemoryStream(bytes ?? Array.Empty<byte>(), false);
                ContentLength = bytes == null ? 0L : bytes.LongLength;
                HasPayload = true;
            }
            else
            {
                ContentLength = null;
                HasPayload = false;
            }
        }

        public void Dispose()
        {
            if (Disposed) return;
            Disposed = true;
            ResponseStream?.Dispose();
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
            try { $gzip.Write($Bytes, 0, $Bytes.Length) }
            finally { $gzip.Dispose() }
            return $output.ToArray()
        }
        finally { $output.Dispose() }
    }

    function New-M3UPayload {
        param(
            [int]$StatusCode = 200,
            [string]$ContentType = 'application/vnd.apple.mpegurl',
            [string[]]$ContentEncodings = @(),
            [string]$ETag = '',
            [Nullable[datetimeoffset]]$LastModified,
            [byte[]]$Bytes
        )

        $bytesToUse = if ($StatusCode -eq 200) {
            if ($null -ne $Bytes) { $Bytes } else { [io.file]::ReadAllBytes($script:FixturePath) }
        }
        else { $null }
        [ChannelForge.Tests.RemoteM3UTestPayload]::new(
            $bytesToUse,
            $StatusCode,
            $ContentType,
            $ContentEncodings,
            $ETag,
            $LastModified)
    }

    function New-M3USource {
        [pscustomobject]@{
            Name       = 'remote-m3u-fixture'
            Url        = 'https://example.invalid/iptv/fixture'
            ProviderId = 'fixture-provider'
        }
    }

    function Set-M3UPayloadMock {
        param([object]$Payload)
        $global:ChannelForgeRemoteM3UTestPayload = $Payload
        Mock -CommandName Invoke-ChannelForgePinnedHttpM3UAcquisition `
            -ModuleName ChannelForge `
            -MockWith { $global:ChannelForgeRemoteM3UTestPayload }
    }

    function Get-ChannelProjection {
        param([object[]]$Channels)
        @($Channels | ForEach-Object {
            [ordered]@{
                Provider = $_.Provider
                Playlist = $_.Playlist
                OriginalName = $_.OriginalName
                DisplayName = $_.DisplayName
                TvgId = $_.TvgId
                TvgName = $_.TvgName
                Logo = $_.Logo
                Group = $_.Group
                Url = $_.Url
            } | ConvertTo-Json -Depth 4 -Compress
        }) -join "`n"
    }
}

AfterAll {
    Remove-Variable -Name ChannelForgeRemoteM3UTestPayload -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Remote M3U acquisition' {
    It 'shares the streaming parser core with the local path API' {
        $local = @(Import-ChannelForgeM3UPlaylist -Path $script:FixturePath -Provider 'fixture-provider' -Playlist 'remote-m3u-fixture')
        $shared = & (Get-Module ChannelForge) {
            param($FixturePath)
            $bytes = [io.file]::ReadAllBytes($FixturePath)
            $stream = [io.memorystream]::new($bytes, $false)
            $reader = [io.streamreader]::new($stream, [text.utf8encoding]::new($false, $true), $true, 8192, $false)
            try {
                return @(Read-ChannelForgeM3UReader -Reader $reader -Provider 'fixture-provider' -Playlist 'remote-m3u-fixture')
            }
            finally {
                $reader.Dispose()
            }
        } $script:FixturePath

        Get-ChannelProjection $shared | Should -Be (Get-ChannelProjection $local)
    }

    It 'accepts each approved content type and a missing content type, while requiring valid M3U structure' {
        foreach ($contentType in @(
            'application/vnd.apple.mpegurl',
            'video/vnd.mpegurl',
            'audio/mpegurl',
            'application/x-mpegurl',
            'audio/x-mpegurl',
            'text/plain',
            'application/octet-stream',
            $null
        )) {
            $payload = New-M3UPayload -ContentType $contentType
            Set-M3UPayloadMock -Payload $payload
            $channels = @(Import-ChannelForgeConfiguredM3USource -Source (New-M3USource))
            $channels.Count | Should -Be 3
            $payload.Disposed | Should -BeTrue
        }
    }

    It 'rejects a declared content type outside the approved list' {
        $payload = New-M3UPayload -ContentType 'application/json'
        Set-M3UPayloadMock -Payload $payload

        { Import-ChannelForgeConfiguredM3USource -Source (New-M3USource) } |
            Should -Throw '*content type*'
        $payload.Disposed | Should -BeTrue
    }

    It 'decodes gzip and repeated supported codings without buffering the payload' {
        $plain = [io.file]::ReadAllBytes($script:FixturePath)
        $gzip = New-GzipBytes -Bytes $plain
        $double = New-GzipBytes -Bytes $gzip

        foreach ($case in @(
            [pscustomobject]@{ Bytes = $gzip; Encodings = @('gzip') }
            [pscustomobject]@{ Bytes = $gzip; Encodings = @('x-gzip') }
            [pscustomobject]@{ Bytes = $double; Encodings = @('gzip', 'x-gzip') }
        )) {
            $payload = New-M3UPayload -Bytes $case.Bytes -ContentEncodings $case.Encodings
            Set-M3UPayloadMock -Payload $payload
            $remote = @(Import-ChannelForgeConfiguredM3USource -Source (New-M3USource))
            $local = @(Import-ChannelForgeM3UPlaylist -Path $script:FixturePath -Provider 'fixture-provider' -Playlist 'remote-m3u-fixture')
            Get-ChannelProjection $remote | Should -Be (Get-ChannelProjection $local)
            $payload.Disposed | Should -BeTrue
        }
    }

    It 'rejects unsupported content encoding before accepting payload bytes' {
        $payload = New-M3UPayload -ContentEncodings @('br')
        Set-M3UPayloadMock -Payload $payload

        { Import-ChannelForgeConfiguredM3USource -Source (New-M3USource) } |
            Should -Throw '*UnsupportedContentEncoding*'
        $payload.Disposed | Should -BeTrue
    }

    It 'rejects missing headers, dangling EXTINF records, and malformed records for every allowed generic type' {
        foreach ($bytes in @(
            [text.encoding]::UTF8.GetBytes('not-m3u`n#EXTINF:-1,Channel`nhttps://example.invalid/live/channel`n'),
            [text.encoding]::UTF8.GetBytes('#EXTM3U`n#EXTINF:-1,Channel`n'),
            [text.encoding]::UTF8.GetBytes('#EXTM3U`n#EXTINF:-1,First`n#EXTINF:-1,Second`nhttps://example.invalid/live/second`n')
        )) {
            $payload = New-M3UPayload -Bytes $bytes -ContentType 'text/plain'
            Set-M3UPayloadMock -Payload $payload
            { Import-ChannelForgeConfiguredM3USource -Source (New-M3USource) } | Should -Throw
            $payload.Disposed | Should -BeTrue
        }
    }

    It 'enforces the decompressed bound and releases the transport owner' {
        $bytes = [text.encoding]::UTF8.GetBytes("#EXTM3U`n#EXTINF:-1,Channel`nhttps://example.invalid/live/channel`n" + ('x' * 400))
        $payload = New-M3UPayload -Bytes $bytes
        Set-M3UPayloadMock -Payload $payload

        { Import-ChannelForgeConfiguredM3USource -Source (New-M3USource) -MaxDocumentBytes 64 } |
            Should -Throw '*expanded content exceeded*'
        $payload.Disposed | Should -BeTrue
    }

    It 'keeps parser diagnostics free of source URL and stream payload text' {
        $bytes = [text.encoding]::UTF8.GetBytes('#EXTM3U`n#EXTINF:-1,Channel`n')
        $payload = New-M3UPayload -Bytes $bytes
        Set-M3UPayloadMock -Payload $payload

        try {
            Import-ChannelForgeConfiguredM3USource -Source (New-M3USource) | Out-Null
            throw 'expected parser failure'
        }
        catch {
            $_.Exception.Message | Should -Not -Match 'example\.invalid'
            $_.Exception.Message | Should -Not -Match 'live/channel'
        }
    }
}
