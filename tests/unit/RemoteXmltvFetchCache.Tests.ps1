BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $script:FixturePath = Join-Path $RepoRoot 'tests\fixtures\xmltv\sample.xml'

    if (-not ('ChannelForge.Tests.RemoteXmltvCacheTestPayload' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;

namespace ChannelForge.Tests
{
    public sealed class RemoteXmltvCacheTestPayload : IDisposable
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

        public RemoteXmltvCacheTestPayload(byte[] bytes, int statusCode, string contentType, string[] contentEncodings, string etag, DateTimeOffset? lastModified)
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
            Name='remote-cache-fixture'; Priority=1; Url='https://example.invalid/guide.xml'; Path=''; Format='xmltv'; SourceKind='remote'; Supported=$true
        }
    }

    function New-CachePayload {
        param([int]$StatusCode=200,[string]$ETag='',[Nullable[datetimeoffset]]$LastModified,[string]$ContentType='application/xml',[string[]]$ContentEncodings=@(),[byte[]]$Bytes)
        $bytes = if ($StatusCode -eq 200) { if ($null -ne $Bytes) { $Bytes } else { [io.file]::ReadAllBytes($script:FixturePath) } } else { $null }
        [ChannelForge.Tests.RemoteXmltvCacheTestPayload]::new($bytes,$StatusCode,$ContentType,$ContentEncodings,$ETag,$LastModified)
    }

    function Set-CacheMockQueue {
        param([object[]]$Payloads)
        $global:ChannelForgeRemoteXmltvCachePayloadQueue = [System.Collections.Generic.Queue[object]]::new()
        $global:ChannelForgeRemoteXmltvCacheObservedCalls = [System.Collections.Generic.List[object]]::new()
        foreach ($payload in $Payloads) { $global:ChannelForgeRemoteXmltvCachePayloadQueue.Enqueue($payload) }
        Mock -CommandName Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -MockWith {
            param($SourceId,$Url,$MaxRawResponseBytes,$IfNoneMatch,$IfModifiedSince,$Allow304MetadataOnly)
            $global:ChannelForgeRemoteXmltvCacheObservedCalls.Add([pscustomobject]@{SourceId=$SourceId;Url=$Url;MaxRawResponseBytes=$MaxRawResponseBytes;IfNoneMatch=$IfNoneMatch;IfModifiedSince=$IfModifiedSince;Allow304MetadataOnly=[bool]$Allow304MetadataOnly}) | Out-Null
            if ($global:ChannelForgeRemoteXmltvCachePayloadQueue.Count -eq 0) { throw 'cache test payload queue was exhausted.' }
            $global:ChannelForgeRemoteXmltvCachePayloadQueue.Dequeue()
        }
    }

    function Get-CacheMetadataPath {
        param([string]$CacheRoot)
        (Get-ChildItem -LiteralPath $CacheRoot -Filter 'metadata.json' -File -Recurse | Select-Object -First 1).FullName
    }

    function Set-CacheStale {
        param([string]$MetadataPath,[double]$AgeSeconds=21601)
        $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
        $timestamp = [datetimeoffset]::UtcNow.AddSeconds(-$AgeSeconds).ToString('o',[cultureinfo]::InvariantCulture)
        $metadata.FetchedAtUtc = $timestamp
        $metadata.ValidatedAtUtc = $timestamp
        [io.file]::WriteAllText($MetadataPath,($metadata | ConvertTo-Json -Depth 12 -Compress),[text.utf8encoding]::new($false))
    }

    function Get-ProgrammeJson {
        param([object[]]$Programmes)
        @($Programmes | ForEach-Object { [ordered]@{ChannelId=$_.ChannelId;Start=$_.Start.ToString('o',[cultureinfo]::InvariantCulture);End=$_.End.ToString('o',[cultureinfo]::InvariantCulture);Title=$_.Title;Subtitle=$_.Subtitle;Description=$_.Description;Categories=@($_.Categories);EpisodeNumber=$_.EpisodeNumber;IsNew=$_.IsNew;IsLive=$_.IsLive;IsPremiere=$_.IsPremiere;SourceId=$_.SourceId} | ConvertTo-Json -Depth 5 -Compress }) -join [Environment]::NewLine
    }
    function Get-ProgrammeEvidenceJson {
        param([object[]]$Programmes)
        @($Programmes | ForEach-Object { $e=$_.Evidence; [ordered]@{ChannelId=$_.ChannelId;Start=$_.Start.ToString('o',[cultureinfo]::InvariantCulture);End=$_.End.ToString('o',[cultureinfo]::InvariantCulture);Evidence=[ordered]@{SourceKind=$e.SourceKind;SourceReference=$e.SourceReference;TransportContractVersion=$e.TransportContractVersion;HttpStatusCode=$e.HttpStatusCode;ContentType=$e.ContentType;ContentEncodings=@($e.ContentEncodings);RawContentLength=$e.RawContentLength;ProgrammeCount=$e.ProgrammeCount;ChannelCount=$e.ChannelCount;DocumentBytes=$e.DocumentBytes}} | ConvertTo-Json -Depth 8 -Compress }) -join [Environment]::NewLine
    }
    function Read-TestXmltvCache {
        param([string]$CacheRoot,[string]$SourceId,[string]$Url,[Nullable[datetimeoffset]]$EvaluationTimeUtc)
        if ($EvaluationTimeUtc.HasValue) {
            InModuleScope ChannelForge -Parameters @{ CacheRoot=$CacheRoot; SourceId=$SourceId; Url=$Url; EvaluationTimeUtc=$EvaluationTimeUtc.Value } {
                param($CacheRoot,$SourceId,$Url,$EvaluationTimeUtc)
                Read-ChannelForgeRemoteXmltvFetchCache -CacheRoot $CacheRoot -SourceId $SourceId -Url $Url -EvaluationTimeUtc $EvaluationTimeUtc
            }
        } else {
            InModuleScope ChannelForge -Parameters @{ CacheRoot=$CacheRoot; SourceId=$SourceId; Url=$Url } {
                param($CacheRoot,$SourceId,$Url)
                Read-ChannelForgeRemoteXmltvFetchCache -CacheRoot $CacheRoot -SourceId $SourceId -Url $Url
            }
        }
    }
}

AfterAll { Remove-Variable -Name ChannelForgeRemoteXmltvCachePayloadQueue,ChannelForgeRemoteXmltvCacheObservedCalls -Scope Global -ErrorAction SilentlyContinue }

Describe 'Remote XMLTV disposable fetch cache' {
    It 'writes decompressed bytes and serves a fresh cache hit without network access' {
        $cacheRoot=Join-Path $TestDrive 'cache-fresh'
        $firstPayload=New-CachePayload -ETag '"fixture-v1"'
        Set-CacheMockQueue @($firstPayload)
        $firstStatus=[ordered]@{}
        $first=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $firstStatus)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        $metadata=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $schemaPath=Join-Path $RepoRoot 'schemas\remote_xmltv_fetch_cache.schema.json'
        Test-Json -Json (Get-Content -LiteralPath $metadataPath -Raw) -SchemaFile $schemaPath | Should -BeTrue
        $metadata.PayloadFile | Should -Match '^payload-[0-9a-f]{64}\.xml$'
        $metadata.PSObject.Properties.Name | Should -Not -Contain 'Url'
        $metadata.PSObject.Properties.Name | Should -Not -Contain 'Host'
        $metadata.PayloadByteCount | Should -BeGreaterThan 0
        $metadata.ETag | Should -Be '"fixture-v1"'
        $firstPayload.Disposed | Should -BeTrue
        $secondStatus=[ordered]@{}
        $second=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $secondStatus)
        Get-ProgrammeJson $second | Should -Be (Get-ProgrammeJson $first)
        $secondStatus.Outcome | Should -Be 'CacheHit'
        $secondStatus.Reason | Should -Be 'FreshWithinTtl'
        Should -Invoke Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -Times 1 -Exactly
    }

    It 'revalidates an expired ETag entry with authorized 304 and preserves deterministic programmes' {
        $cacheRoot=Join-Path $TestDrive 'cache-304'
        $firstPayload=New-CachePayload -ETag '"fixture-v1"'
        $notModified=New-CachePayload -StatusCode 304 -ETag '"fixture-v1"'
        Set-CacheMockQueue @($firstPayload,$notModified)
        $first=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        Set-CacheStale $metadataPath
        $status=[ordered]@{}
        $second=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        Get-ProgrammeJson $second | Should -Be (Get-ProgrammeJson $first)
        $status.Outcome | Should -Be 'CacheHit'
        $status.Reason | Should -Be 'Validated304'
        $updated=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $updated.LastValidationStatus | Should -Be 304
        $updated.OperationalReason | Should -Be 'Validated304'
        Should -Invoke Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -Times 2 -Exactly
    }

    It 'performs exactly one unconditional repair after a 304 with a missing payload' {
        $cacheRoot=Join-Path $TestDrive 'cache-repair'
        $firstPayload=New-CachePayload -ETag '"fixture-v1"'
        $notModified=New-CachePayload -StatusCode 304 -ETag '"fixture-v1"'
        $repairPayload=New-CachePayload -ETag '"fixture-v2"'
        Set-CacheMockQueue @($firstPayload,$notModified,$repairPayload)
        $first=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        $metadata=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $payloadPath=Join-Path (Split-Path -Parent $metadataPath) $metadata.PayloadFile
        Remove-Item -LiteralPath $payloadPath -Force
        Set-CacheStale $metadataPath
        $status=[ordered]@{}
        $repaired=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        Get-ProgrammeJson $repaired | Should -Be (Get-ProgrammeJson $first)
        $status.Outcome | Should -Be 'Fetched'
        $status.Reason | Should -Be 'InvalidatedThenFetched'
        Should -Invoke Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -Times 3 -Exactly
        (Get-CacheMetadataPath $cacheRoot) | Should -Not -BeNullOrEmpty
    }

    It 'uses decompressed content hash fallback when validators are absent' {
        $cacheRoot=Join-Path $TestDrive 'cache-hash'
        $firstPayload=New-CachePayload
        $samePayload=New-CachePayload
        Set-CacheMockQueue @($firstPayload,$samePayload)
        $first=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        Set-CacheStale $metadataPath
        $status=[ordered]@{}
        $second=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        Get-ProgrammeJson $second | Should -Be (Get-ProgrammeJson $first)
        $status.Outcome | Should -Be 'Fetched'
        $status.Reason | Should -Be 'HashMatched200'
        $updated=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $updated.OperationalReason | Should -Be 'HashMatched200'
        Should -Invoke Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -Times 2 -Exactly
    }

    It 'fails closed instead of publishing a stale cache when refresh fails' {
        $cacheRoot=Join-Path $TestDrive 'cache-fail'
        $firstPayload=New-CachePayload -ETag '"fixture-v1"'
        Set-CacheMockQueue @($firstPayload)
        $first=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        Set-CacheStale $metadataPath
        Mock -CommandName Invoke-ChannelForgePinnedHttpXmltvAcquisition -ModuleName ChannelForge -MockWith { throw 'deterministic refresh failure' }
        { Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot } | Should -Throw '*deterministic refresh failure*'
    }
    It 'uses ETag before Last-Modified for a 304 revalidation' {
        $cacheRoot=Join-Path $TestDrive 'cache-etag-precedence'
        $lastModified=[datetimeoffset]::Parse('2026-08-20T12:34:56Z')
        $firstPayload=New-CachePayload -ETag '"fixture-v1"' -LastModified $lastModified
        $notModified=New-CachePayload -StatusCode 304 -ETag '"fixture-v1"' -LastModified $lastModified
        Set-CacheMockQueue @($firstPayload,$notModified)
        $first=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Set-CacheStale (Get-CacheMetadataPath $cacheRoot)
        $second=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Get-ProgrammeJson $second | Should -Be (Get-ProgrammeJson $first)
        Get-ProgrammeEvidenceJson $second | Should -Be (Get-ProgrammeEvidenceJson $first)
        $calls=@($global:ChannelForgeRemoteXmltvCacheObservedCalls)
        $calls.Count | Should -Be 2
        $calls[1].IfNoneMatch | Should -Be '"fixture-v1"'
        $calls[1].IfModifiedSince | Should -BeNullOrEmpty
        $calls[1].Allow304MetadataOnly | Should -BeTrue
    }

    It 'uses Last-Modified when an expired cache entry has no ETag' {
        $cacheRoot=Join-Path $TestDrive 'cache-last-modified'
        $lastModified=[datetimeoffset]::Parse('2026-08-19T08:00:00Z')
        $firstPayload=New-CachePayload -LastModified $lastModified
        $notModified=New-CachePayload -StatusCode 304 -LastModified $lastModified
        Set-CacheMockQueue @($firstPayload,$notModified)
        $first=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Set-CacheStale (Get-CacheMetadataPath $cacheRoot)
        $second=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Get-ProgrammeJson $second | Should -Be (Get-ProgrammeJson $first)
        $calls=@($global:ChannelForgeRemoteXmltvCacheObservedCalls)
        $calls.Count | Should -Be 2
        $calls[1].IfNoneMatch | Should -BeNullOrEmpty
        ([datetimeoffset]$calls[1].IfModifiedSince).ToUniversalTime().ToString('o') |
            Should -Be $lastModified.ToUniversalTime().ToString('o')
        $calls[1].Allow304MetadataOnly | Should -BeTrue
    }

    It 'treats cache age at or beyond six hours as stale' {
        $cacheRoot=Join-Path $TestDrive 'cache-ttl-boundary'
        $firstPayload=New-CachePayload
        $replacement=New-CachePayload
        Set-CacheMockQueue @($firstPayload,$replacement)
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Set-CacheStale (Get-CacheMetadataPath $cacheRoot) -AgeSeconds 21600.5
        $status=[ordered]@{}
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $status.Outcome | Should -Be 'Fetched'
        @($global:ChannelForgeRemoteXmltvCacheObservedCalls).Count | Should -Be 2
    }

    It 'refetches when cache metadata is malformed' {
        $cacheRoot=Join-Path $TestDrive 'cache-malformed-metadata'
        $firstPayload=New-CachePayload
        $replacement=New-CachePayload
        Set-CacheMockQueue @($firstPayload,$replacement)
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        [io.file]::WriteAllText($metadataPath,'{not-json',[text.utf8encoding]::new($false))
        $status=[ordered]@{}
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $status.Outcome | Should -Be 'Fetched'
        @($global:ChannelForgeRemoteXmltvCacheObservedCalls).Count | Should -Be 2
        $global:ChannelForgeRemoteXmltvCacheObservedCalls[1].IfNoneMatch | Should -BeNullOrEmpty
    }

    It 'refetches when the cached payload hash is corrupt' {
        $cacheRoot=Join-Path $TestDrive 'cache-corrupt-payload'
        $firstPayload=New-CachePayload
        $replacement=New-CachePayload
        Set-CacheMockQueue @($firstPayload,$replacement)
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        $metadata=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $payloadPath=Join-Path (Split-Path -Parent $metadataPath) $metadata.PayloadFile
        $bytes=[io.file]::ReadAllBytes($payloadPath)
        $bytes[0]=[byte]($bytes[0] -bxor 1)
        [io.file]::WriteAllBytes($payloadPath,$bytes)
        $status=[ordered]@{}
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $status.Outcome | Should -Be 'Fetched'
        @($global:ChannelForgeRemoteXmltvCacheObservedCalls).Count | Should -Be 2
    }

    It 'falls back to an unconditional fetch for an overlong cached ETag' {
        $cacheRoot=Join-Path $TestDrive 'cache-overlong-validator'
        $longEtag='"' + ('a' * 1100) + '"'
        $firstPayload=New-CachePayload -ETag $longEtag
        $replacement=New-CachePayload
        Set-CacheMockQueue @($firstPayload,$replacement)
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        Set-CacheStale (Get-CacheMetadataPath $cacheRoot)
        $status=[ordered]@{}
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $status.Outcome | Should -Be 'Fetched'
        @($global:ChannelForgeRemoteXmltvCacheObservedCalls).Count | Should -Be 2
        $global:ChannelForgeRemoteXmltvCacheObservedCalls[1].IfNoneMatch | Should -BeNullOrEmpty
    }

    It 'releases the remote owner when malformed XML prevents cache publication' {
        $cacheRoot=Join-Path $TestDrive 'cache-malformed-xml'
        $badXml=[text.encoding]::UTF8.GetBytes('<tv><channel id="one"></tv>')
        $payload=New-CachePayload -Bytes $badXml
        Set-CacheMockQueue @($payload)
        { Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot } |
            Should -Throw
        $payload.Disposed | Should -BeTrue
        Get-CacheMetadataPath $cacheRoot | Should -BeNullOrEmpty
    }

    It 'forwards the configured raw-response bound through the no-cache remote path' {
        $payload=New-CachePayload
        Set-CacheMockQueue @($payload)
        $programmes=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -MaxRawResponseBytes 4096)
        $programmes.Count | Should -BeGreaterThan 0
        $payload.Disposed | Should -BeTrue
        $global:ChannelForgeRemoteXmltvCacheObservedCalls[0].MaxRawResponseBytes | Should -Be 4096
    }
    It 'invalidates a parser-failing cache hit and performs one repair fetch' {
        $cacheRoot=Join-Path $TestDrive 'cache-parser-repair'
        $firstPayload=New-CachePayload
        $repairPayload=New-CachePayload
        Set-CacheMockQueue @($firstPayload,$repairPayload)
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        $metadata=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $payloadPath=Join-Path (Split-Path -Parent $metadataPath) $metadata.PayloadFile
        $badXml=[text.encoding]::UTF8.GetBytes('<tv><channel id="one"></tv>')
        [io.file]::WriteAllBytes($payloadPath,$badXml)
        $metadata.PayloadByteCount=$badXml.Length
        $sha=[security.cryptography.sha256]::Create()
        try {
            $metadata.PayloadSha256=[convert]::ToHexString($sha.ComputeHash($badXml)).ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
        [io.file]::WriteAllText($metadataPath,($metadata | ConvertTo-Json -Depth 12 -Compress),[text.utf8encoding]::new($false))
        $status=[ordered]@{}
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot -AcquisitionStatus $status)
        $status.Outcome | Should -Be 'Fetched'
        $status.Reason | Should -Be 'InvalidatedThenFetched'
        @($global:ChannelForgeRemoteXmltvCacheObservedCalls).Count | Should -Be 2
        $final=Get-Content -LiteralPath (Get-CacheMetadataPath $cacheRoot) -Raw | ConvertFrom-Json
        ((Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash).ToLowerInvariant() | Should -Be $final.PayloadSha256
        Get-CacheMetadataPath $cacheRoot | Should -Not -BeNullOrEmpty
    }
    It 'uses explicit evaluation time deterministically at the exact TTL boundary' {
        $cacheRoot=Join-Path $TestDrive 'evaluation-time'
        Set-CacheMockQueue @(New-CachePayload -ETag '"evaluation-v1"')
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $metadataPath=Get-CacheMetadataPath $cacheRoot
        $metadata=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $base=[datetimeoffset]'2026-01-01T00:00:00Z'
        $metadata.FetchedAtUtc=$base.ToString('o',[cultureinfo]::InvariantCulture)
        $metadata.ValidatedAtUtc=$metadata.FetchedAtUtc
        [io.file]::WriteAllText($metadataPath,($metadata|ConvertTo-Json -Depth 12 -Compress),[text.utf8encoding]::new($false))
        $fresh=InModuleScope ChannelForge -Parameters @{ CacheRoot=$cacheRoot } { param($CacheRoot) Read-ChannelForgeRemoteXmltvFetchCache -CacheRoot $CacheRoot -SourceId 'remote-cache-fixture' -Url 'https://example.invalid/guide.xml' -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T05:59:59Z') }
        $repeat=InModuleScope ChannelForge -Parameters @{ CacheRoot=$cacheRoot } { param($CacheRoot) Read-ChannelForgeRemoteXmltvFetchCache -CacheRoot $CacheRoot -SourceId 'remote-cache-fixture' -Url 'https://example.invalid/guide.xml' -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T05:59:59Z') }
        $fresh.MetadataValid|Should -BeTrue;$fresh.PayloadValid|Should -BeTrue;$fresh.AgeSeconds|Should -Be $repeat.AgeSeconds;$fresh.IsFresh|Should -BeTrue;$fresh.IsFresh|Should -Be $repeat.IsFresh;$fresh.CanConditional|Should -BeTrue;$fresh.CanConditional|Should -Be $repeat.CanConditional
        $expired=InModuleScope ChannelForge -Parameters @{ CacheRoot=$cacheRoot } { param($CacheRoot) Read-ChannelForgeRemoteXmltvFetchCache -CacheRoot $CacheRoot -SourceId 'remote-cache-fixture' -Url 'https://example.invalid/guide.xml' -EvaluationTimeUtc ([datetimeoffset]'2026-01-01T06:00:00Z') }
        $expired.MetadataValid|Should -BeTrue;$expired.PayloadValid|Should -BeTrue;$expired.IsFresh|Should -BeFalse;$expired.CanConditional|Should -BeTrue
    }

    It 'keeps omitted evaluation time backward compatible' {
        $cacheRoot=Join-Path $TestDrive 'evaluation-default'
        Set-CacheMockQueue @(New-CachePayload)
        $null=@(Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot)
        $result=Read-TestXmltvCache -CacheRoot $cacheRoot -SourceId 'remote-cache-fixture' -Url 'https://example.invalid/guide.xml'
        $result.MetadataValid|Should -BeTrue;$result.PayloadValid|Should -BeTrue
    }

    It 'rejects empty remote content before cache promotion' {
        $cacheRoot=Join-Path $TestDrive 'empty-response'
        $payload=New-CachePayload -Bytes ([text.encoding]::UTF8.GetBytes('<tv />'))
        Set-CacheMockQueue @($payload)
        { Import-ChannelForgeConfiguredXmltvSource -Source (New-CacheSource) -CacheRoot $cacheRoot } | Should -Throw '*no programmes*'
        $payload.Disposed | Should -BeTrue
        Get-CacheMetadataPath $cacheRoot | Should -BeNullOrEmpty
    }
}
