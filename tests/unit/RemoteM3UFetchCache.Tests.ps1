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

    function New-CacheSource {
        [pscustomobject]@{
            Name       = 'remote-m3u-cache-fixture'
            Url        = 'https://example.invalid/iptv/cache-fixture'
            ProviderId = 'fixture-provider'
        }
    }

    function New-CachePayload {
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

    function Set-CacheMockQueue {
        param([object[]]$Payloads)
        $global:ChannelForgeRemoteM3UCachePayloadQueue = [System.Collections.Generic.Queue[object]]::new()
        $global:ChannelForgeRemoteM3UCacheObservedCalls = [System.Collections.Generic.List[object]]::new()
        foreach ($payload in $Payloads) { $global:ChannelForgeRemoteM3UCachePayloadQueue.Enqueue($payload) }
        Mock -CommandName Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -MockWith {
            param($SourceId,$Url,$MaxRawResponseBytes,$IfNoneMatch,$IfModifiedSince,$Allow304MetadataOnly)
            $global:ChannelForgeRemoteM3UCacheObservedCalls.Add([pscustomobject]@{
                SourceId=$SourceId
                Url=$Url
                MaxRawResponseBytes=$MaxRawResponseBytes
                IfNoneMatch=$IfNoneMatch
                IfModifiedSince=$IfModifiedSince
                Allow304MetadataOnly=[bool]$Allow304MetadataOnly
            }) | Out-Null
            if ($global:ChannelForgeRemoteM3UCachePayloadQueue.Count -eq 0) {
                throw 'M3U cache test payload queue was exhausted.'
            }
            $global:ChannelForgeRemoteM3UCachePayloadQueue.Dequeue()
        }
    }

    function Get-CacheMetadataPath {
        param([string]$CacheRoot)
        (Get-ChildItem -LiteralPath $CacheRoot -Filter 'metadata.json' -File -Recurse | Select-Object -First 1).FullName
    }

    function Set-CacheStale {
        param([string]$MetadataPath,[double]$AgeSeconds=86401)
        $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
        $timestamp = [datetimeoffset]::UtcNow.AddSeconds(-$AgeSeconds).ToString('o',[cultureinfo]::InvariantCulture)
        $metadata.FetchedAtUtc = $timestamp
        $metadata.ValidatedAtUtc = $timestamp
        [io.file]::WriteAllText($MetadataPath,($metadata | ConvertTo-Json -Depth 12 -Compress),[text.utf8encoding]::new($false))
    }

    function Get-ChannelProjection {
        param([object[]]$Channels)
        @($Channels | ForEach-Object {
            [ordered]@{TvgId=$_.TvgId;DisplayName=$_.DisplayName;Group=$_.Group;Url=$_.Url;Provider=$_.Provider;Playlist=$_.Playlist} |
                ConvertTo-Json -Depth 4 -Compress
        }) -join "`n"
    }
}

AfterAll {
    Remove-Variable -Name ChannelForgeRemoteM3UCachePayloadQueue,ChannelForgeRemoteM3UCacheObservedCalls -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Remote M3U disposable fetch cache' {
    It 'writes decompressed payload bytes and serves a fresh cache hit without network access' {
        $cacheRoot = Join-Path $TestDrive 'fresh'
        $rawETag = '"cache-private-etag-sentinel"'
        $lastModified = [datetimeoffset]::Parse('2026-08-20T12:34:56Z')
        $expectedLastModifiedUtc = $lastModified.ToUniversalTime().ToString(
            'o',
            [cultureinfo]::InvariantCulture)
        $firstPayload = New-CachePayload -ETag $rawETag -LastModified $lastModified
        Set-CacheMockQueue @($firstPayload)
        $firstStatus = [ordered]@{}
        $first = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $firstStatus)
        $metadataPath = Get-CacheMetadataPath $cacheRoot
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $schemaPath = Join-Path $RepoRoot 'schemas\remote_m3u_fetch_cache.schema.json'

        Test-Json -Json (Get-Content -LiteralPath $metadataPath -Raw) -SchemaFile $schemaPath | Should -BeTrue
        $metadata.ETag | Should -Be $rawETag
        $metadata.LastModified | Should -Not -BeNullOrEmpty
        ([datetimeoffset]::Parse([string]$metadata.LastModified)).ToUniversalTime().ToString(
            'o',
            [cultureinfo]::InvariantCulture) | Should -Be $expectedLastModifiedUtc
        $rawLastModified = [string]$metadata.LastModified
        $metadata.PayloadFile | Should -Match '^payload-[0-9a-f]{64}\.m3u$'
        $metadata.PSObject.Properties.Name | Should -Not -Contain 'Url'
        $metadata.PSObject.Properties.Name | Should -Not -Contain 'ETagValue'
        (Get-Content -LiteralPath $metadataPath -Raw) | Should -Not -Match 'https?://'
        $metadata.CacheKey | Should -Not -Match ([regex]::Escape($rawETag))
        $metadata.CacheKey | Should -Not -Match ([regex]::Escape($rawLastModified))
        $cachePaths = @(
            Get-ChildItem -LiteralPath $cacheRoot -File -Recurse |
                ForEach-Object { $_.FullName }
        ) -join ([Environment]::NewLine)
        $cachePaths | Should -Not -Match ([regex]::Escape($rawETag))
        $cachePaths | Should -Not -Match ([regex]::Escape($rawLastModified))
        ($firstStatus | ConvertTo-Json -Depth 8 -Compress) | Should -Not -Match ([regex]::Escape($rawETag))
        ($firstStatus | ConvertTo-Json -Depth 8 -Compress) | Should -Not -Match ([regex]::Escape($rawLastModified))
        $firstStatus.HasETag | Should -BeTrue
        $firstStatus.HasLastModified | Should -BeTrue
        $firstChannelsJson = @(
            $first | ForEach-Object {
                $_ | ConvertTo-Json -Depth 10 -Compress
            }
        ) -join ([Environment]::NewLine)
        $firstChannelsJson | Should -Not -Match ([regex]::Escape($rawETag))
        $firstChannelsJson | Should -Not -Match ([regex]::Escape($rawLastModified))
        $firstPayload.Disposed | Should -BeTrue

        $secondStatus = [ordered]@{}
        $second = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $secondStatus)
        Get-ChannelProjection $second | Should -Be (Get-ChannelProjection $first)
        $secondStatus.Outcome | Should -Be 'CacheHit'
        $secondStatus.Reason | Should -Be 'FreshWithinTtl'
        $secondStatus.HasETag | Should -BeTrue
        $secondStatus.HasLastModified | Should -BeTrue
        $secondStatusJson = $secondStatus | ConvertTo-Json -Depth 8 -Compress
        $secondStatusJson | Should -Not -Match ([regex]::Escape($rawETag))
        $secondStatusJson | Should -Not -Match ([regex]::Escape($rawLastModified))
        $secondChannelsJson = @(
            $second | ForEach-Object {
                $_ | ConvertTo-Json -Depth 10 -Compress
            }
        ) -join ([Environment]::NewLine)
        $secondChannelsJson | Should -Not -Match ([regex]::Escape($rawETag))
        $secondChannelsJson | Should -Not -Match ([regex]::Escape($rawLastModified))
        @($global:ChannelForgeRemoteM3UCacheObservedCalls).Count | Should -Be 1
    }

    It 'uses ETag before Last-Modified and accepts an authorized 304' {
        $cacheRoot = Join-Path $TestDrive 'etag'
        $lastModified = [datetimeoffset]::Parse('2026-08-20T12:34:56Z')
        $firstPayload = New-CachePayload -ETag '"fixture-v1"' -LastModified $lastModified
        $notModified = New-CachePayload -StatusCode 304 -ETag '"fixture-v1"' -LastModified $lastModified
        Set-CacheMockQueue @($firstPayload,$notModified)
        $first = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Set-CacheStale (Get-CacheMetadataPath $cacheRoot)
        $status = [ordered]@{}
        $second = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)

        Get-ChannelProjection $second | Should -Be (Get-ChannelProjection $first)
        $status.Outcome | Should -Be 'CacheHit'
        $status.Reason | Should -Be 'Validated304'
        $calls = @($global:ChannelForgeRemoteM3UCacheObservedCalls)
        $calls.Count | Should -Be 2
        $calls[1].IfNoneMatch | Should -Be '"fixture-v1"'
        $calls[1].IfModifiedSince | Should -BeNullOrEmpty
        $calls[1].Allow304MetadataOnly | Should -BeTrue
    }

    It 'uses Last-Modified when ETag is absent' {
        $cacheRoot = Join-Path $TestDrive 'last-modified'
        $lastModified = [datetimeoffset]::Parse('2026-08-19T08:00:00Z')
        $firstPayload = New-CachePayload -LastModified $lastModified
        $notModified = New-CachePayload -StatusCode 304 -LastModified $lastModified
        Set-CacheMockQueue @($firstPayload,$notModified)
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Set-CacheStale (Get-CacheMetadataPath $cacheRoot)
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot)

        $calls = @($global:ChannelForgeRemoteM3UCacheObservedCalls)
        $calls.Count | Should -Be 2
        $calls[1].IfNoneMatch | Should -BeNullOrEmpty
        ([datetimeoffset]$calls[1].IfModifiedSince).ToUniversalTime().ToString('o') |
            Should -Be $lastModified.ToUniversalTime().ToString('o')
    }

    It 'uses decompressed content hash fallback when validators are absent' {
        $cacheRoot = Join-Path $TestDrive 'hash'
        $firstPayload = New-CachePayload
        $samePayload = New-CachePayload
        Set-CacheMockQueue @($firstPayload,$samePayload)
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Set-CacheStale (Get-CacheMetadataPath $cacheRoot)
        $status = [ordered]@{}
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $status.Outcome | Should -Be 'Fetched'
        $status.Reason | Should -Be 'HashMatched200'
        @($global:ChannelForgeRemoteM3UCacheObservedCalls).Count | Should -Be 2
    }

    It 'performs exactly one unconditional repair after a 304 with a missing payload' {
        $cacheRoot = Join-Path $TestDrive 'repair'
        $firstPayload = New-CachePayload -ETag '"fixture-v1"'
        $notModified = New-CachePayload -StatusCode 304 -ETag '"fixture-v1"'
        $repairPayload = New-CachePayload -ETag '"fixture-v2"'
        Set-CacheMockQueue @($firstPayload,$notModified,$repairPayload)
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath = Get-CacheMetadataPath $cacheRoot
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $payloadPath = Join-Path (Split-Path -Parent $metadataPath) $metadata.PayloadFile
        Remove-Item -LiteralPath $payloadPath -Force
        Set-CacheStale $metadataPath

        $status = [ordered]@{}
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $status.Outcome | Should -Be 'Fetched'
        $status.Reason | Should -Be 'InvalidatedThenFetched'
        @($global:ChannelForgeRemoteM3UCacheObservedCalls).Count | Should -Be 3
    }

    It 'repairs a parser-failing cache hit once and never publishes the stale payload' {
        $cacheRoot = Join-Path $TestDrive 'parser-repair'
        $firstPayload = New-CachePayload
        $repairPayload = New-CachePayload
        Set-CacheMockQueue @($firstPayload,$repairPayload)
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath = Get-CacheMetadataPath $cacheRoot
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $payloadPath = Join-Path (Split-Path -Parent $metadataPath) $metadata.PayloadFile
        $badBytes = [text.encoding]::UTF8.GetBytes('#EXTM3U`n#EXTINF:-1,broken`n')
        [io.file]::WriteAllBytes($payloadPath, $badBytes)
        $metadata.PayloadByteCount = $badBytes.Length
        $sha = [security.cryptography.sha256]::Create()
        try { $metadata.PayloadSha256 = [convert]::ToHexString($sha.ComputeHash($badBytes)).ToLowerInvariant() }
        finally { $sha.Dispose() }
        [io.file]::WriteAllText($metadataPath,($metadata | ConvertTo-Json -Depth 12 -Compress),[text.utf8encoding]::new($false))

        $status = [ordered]@{}
        $repaired = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $repaired.Count | Should -Be 3
        $status.Outcome | Should -Be 'Fetched'
        $status.Reason | Should -Be 'InvalidatedThenFetched'
        @($global:ChannelForgeRemoteM3UCacheObservedCalls).Count | Should -Be 2
        @(Get-ChildItem -LiteralPath $cacheRoot -Filter '*.tmp' -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'fails closed when stale refresh fails instead of returning stale channels' {
        $cacheRoot = Join-Path $TestDrive 'failed-refresh'
        $rawETag = '"diagnostic-etag-sentinel"'
        $lastModified = [datetimeoffset]::Parse('2026-08-21T07:28:00Z')
        $expectedLastModifiedUtc = $lastModified.ToUniversalTime().ToString(
            'o',
            [cultureinfo]::InvariantCulture)
        $firstPayload = New-CachePayload -ETag $rawETag -LastModified $lastModified
        Set-CacheMockQueue @($firstPayload)
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath = Get-CacheMetadataPath $cacheRoot
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $metadata.ETag | Should -Be $rawETag
        $metadata.LastModified | Should -Not -BeNullOrEmpty
        ([datetimeoffset]::Parse([string]$metadata.LastModified)).ToUniversalTime().ToString(
            'o',
            [cultureinfo]::InvariantCulture) | Should -Be $expectedLastModifiedUtc
        $rawLastModified = [string]$metadata.LastModified
        Set-CacheStale $metadataPath
        Mock -CommandName Invoke-ChannelForgePinnedHttpM3UAcquisition -ModuleName ChannelForge -MockWith {
            throw 'deterministic M3U refresh failure'
        }

        $diagnostic = try {
            Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot
            ''
        }
        catch {
            $_.Exception.ToString()
        }
        $diagnostic | Should -Match 'deterministic M3U refresh failure'
        $diagnostic | Should -Not -Match ([regex]::Escape($rawETag))
        $diagnostic | Should -Not -Match ([regex]::Escape($rawLastModified))
    }

    It 'refetches after malformed metadata and corrupt payload, without leaking stream URLs' {
        $cacheRoot = Join-Path $TestDrive 'corrupt'
        $firstPayload = New-CachePayload
        $replacement = New-CachePayload
        Set-CacheMockQueue @($firstPayload,$replacement)
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath = Get-CacheMetadataPath $cacheRoot
        [io.file]::WriteAllText($metadataPath,'{not-json',[text.utf8encoding]::new($false))
        $status = [ordered]@{}
        $null = @(Import-ChannelForgeConfiguredM3USource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $status.Outcome | Should -Be 'Fetched'
        @($global:ChannelForgeRemoteM3UCacheObservedCalls).Count | Should -Be 2
        (Get-Content -LiteralPath (Get-CacheMetadataPath $cacheRoot) -Raw) | Should -Not -Match 'https?://'
        (Get-Content -LiteralPath (Get-CacheMetadataPath $cacheRoot) -Raw) | Should -Not -Match 'live/'
    }
}
