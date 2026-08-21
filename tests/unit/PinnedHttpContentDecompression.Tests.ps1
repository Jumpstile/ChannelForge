BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $RepoRoot 'src\ChannelForge\ChannelForge.psd1') -Force
    $module = Get-Module ChannelForge

    # Expand-ChannelForgePinnedHttpContentStream is module-private (not exported).
    # A FunctionInfo obtained from inside the module's own session state retains
    # that module binding when invoked later from any outer scope, so the
    # module-private BoundedDecompressionStream class it references still
    # resolves correctly -- unlike defining helpers via separate `& $module { }`
    # invocations, which do not share scope with one another.
    $script:ExpandContentStream = & $module { Get-Command Expand-ChannelForgePinnedHttpContentStream }
    $script:HardMaximumDecompressedBytes = & $module { [BoundedDecompressionStream]::HardMaximumDecompressedBytes }

    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

public sealed class SpikeDecompressionOwner : IDisposable
{
    public bool Disposed;
    public int DisposeCount;
    public void Dispose() { Disposed = true; DisposeCount++; }
}

// A Stream whose Read/ReadAsync immediately throws an exception carrying a
// ChannelForgeFailureCategory, simulating a failure originating in the
// underlying v4 transport's own ChannelForgeBoundedResponseStream (e.g.
// Cancelled, Timeout). Used to prove the decompression wrapper never
// translates a foreign failure category into DecompressionFailed.
public sealed class SpikeFaultyTransportStream : Stream
{
    private readonly string _category;
    private readonly string _message;

    public SpikeFaultyTransportStream(string category, string message)
    {
        _category = category;
        _message = message;
    }

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => 0; set => throw new NotSupportedException(); }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    public override int Read(byte[] buffer, int offset, int count)
    {
        var ex = new InvalidOperationException(_message);
        ex.Data["ChannelForgeFailureCategory"] = _category;
        throw ex;
    }

    public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        var ex = new InvalidOperationException(_message);
        ex.Data["ChannelForgeFailureCategory"] = _category;
        throw ex;
    }
}

// A Stream whose Read/ReadAsync throws a completely generic, uncategorized
// exception -- no ChannelForgeFailureCategory at all -- simulating an
// unexpected underlying IO/read failure that is neither a transport-level
// category nor a decoder-format problem. Used to prove such a failure is
// still propagated unchanged (never recategorized as DecompressionFailed)
// while the wrapper still disposes its owner exactly once.
public sealed class SpikeGenericIOFaultyStream : Stream
{
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => 0; set => throw new NotSupportedException(); }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    public override int Read(byte[] buffer, int offset, int count)
    {
        throw new IOException("simulated unexpected underlying IO failure");
    }

    public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        throw new IOException("simulated unexpected underlying IO failure");
    }
}

// A Stream whose ReadAsync genuinely awaits (via Task.Delay observing the
// supplied CancellationToken) before ever producing bytes, so a caller can
// cancel it mid-read through a real asynchronous continuation rather than a
// synchronously-thrown exception. Used to prove ReadAsync's own
// CancellationToken parameter is actually observed, not merely accepted and
// ignored while silently delegating to the synchronous Read path.
public sealed class SpikeSlowAsyncStream : Stream
{
    private readonly byte[] _data;
    private readonly int _delayMilliseconds;
    private int _position;

    public SpikeSlowAsyncStream(byte[] data, int delayMilliseconds)
    {
        _data = data;
        _delayMilliseconds = delayMilliseconds;
    }

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => _position; set => throw new NotSupportedException(); }
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    public override int Read(byte[] buffer, int offset, int count)
    {
        Thread.Sleep(_delayMilliseconds);
        return CopyNext(buffer, offset, count);
    }

    public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        await Task.Delay(_delayMilliseconds, cancellationToken).ConfigureAwait(false);
        return CopyNext(buffer, offset, count);
    }

    private int CopyNext(byte[] buffer, int offset, int count)
    {
        var remaining = _data.Length - _position;
        if (remaining <= 0) { return 0; }
        var toCopy = Math.Min(count, remaining);
        Array.Copy(_data, _position, buffer, offset, toCopy);
        _position += toCopy;
        return toCopy;
    }
}
'@

    function New-GzipBytes {
        param([byte[]]$Plain)
        $ms = [System.IO.MemoryStream]::new()
        $gz = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Compress, $true)
        $gz.Write($Plain, 0, $Plain.Length)
        $gz.Dispose()
        return , $ms.ToArray()
    }

    function Read-AllBytesSync {
        param([System.IO.Stream]$Stream, [int]$ChunkSize = 7)
        $out = [System.Collections.Generic.List[byte]]::new()
        $buf = [byte[]]::new($ChunkSize)
        while (($n = $Stream.Read($buf, 0, $buf.Length)) -gt 0) {
            for ($i = 0; $i -lt $n; $i++) { $out.Add($buf[$i]) }
        }
        return , $out.ToArray()
    }

    function Read-AllBytesAsync {
        param([System.IO.Stream]$Stream, [int]$ChunkSize = 7)
        $out = [System.Collections.Generic.List[byte]]::new()
        $buf = [byte[]]::new($ChunkSize)
        while ($true) {
            $task = $Stream.ReadAsync($buf, 0, $buf.Length, [System.Threading.CancellationToken]::None)
            $n = $task.GetAwaiter().GetResult()
            if ($n -eq 0) { break }
            for ($i = 0; $i -lt $n; $i++) { $out.Add($buf[$i]) }
        }
        return , $out.ToArray()
    }

    function Get-FailureCategory {
        param($ErrorRecord)
        # PowerShell wraps an exception thrown from a nested compiled Stream
        # call (e.g. the fault-injection streams below) in a
        # MethodInvocationException; walk InnerException until the
        # ChannelForgeFailureCategory marker is found, matching the same
        # unwrap pattern already used in PinnedHttpTransportAcquisition.Tests.ps1.
        $exception = $ErrorRecord.Exception
        while ($null -ne $exception -and
               ($null -eq $exception.Data -or -not $exception.Data.Contains('ChannelForgeFailureCategory'))) {
            $exception = $exception.InnerException
        }
        if ($null -eq $exception) { return $null }
        return [string]$exception.Data['ChannelForgeFailureCategory']
    }

    function Expand-Test {
        param(
            [string[]]$ContentEncodings,
            [System.IO.Stream]$InnerStream,
            [System.IDisposable]$Owner,
            [long]$MaxDecompressedBytes = $script:HardMaximumDecompressedBytes
        )
        return & $script:ExpandContentStream -ContentEncodings $ContentEncodings -InnerStream $InnerStream -Owner $Owner -MaxDecompressedBytes $MaxDecompressedBytes
    }
}

Describe 'ChannelForge bounded HTTP content decompression' {

    Context 'identity' {
        It 'passes bytes through unchanged' {
            $data = [System.Text.Encoding]::UTF8.GetBytes('hello world, identity passthrough')
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $owner -MaxDecompressedBytes 1024
            $result = Read-AllBytesSync $stream
            $stream.Dispose()
            [System.Text.Encoding]::UTF8.GetString($result) | Should -Be 'hello world, identity passthrough'
            $owner.Disposed | Should -BeTrue
        }

        It 'succeeds at exactly the configured limit' {
            $data = [byte[]](1..10)
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @('identity') -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $owner -MaxDecompressedBytes 10
            $result = Read-AllBytesSync $stream
            $stream.Dispose()
            , $result | Should -Be (, $data)
        }

        It 'fails over the configured limit and never returns the byte beyond it' {
            $data = [byte[]](1..11)
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $owner -MaxDecompressedBytes 10
            $received = [System.Collections.Generic.List[byte]]::new()
            $threw = $false
            $category = $null
            try {
                $buf = [byte[]]::new(3)
                while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                    for ($i = 0; $i -lt $n; $i++) { $received.Add($buf[$i]) }
                }
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'DecompressionLimitExceeded'
            $received.Count | Should -BeLessOrEqual 10
            $owner.Disposed | Should -BeTrue
        }
    }

    Context 'gzip' {
        It 'decodes a valid gzip payload' {
            $plain = [System.Text.Encoding]::UTF8.GetBytes('the quick brown fox jumps over the lazy dog')
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @('gzip') -InnerStream ([System.IO.MemoryStream]::new((New-GzipBytes $plain))) -Owner $owner -MaxDecompressedBytes 1024
            $result = Read-AllBytesSync $stream
            $stream.Dispose()
            [System.Text.Encoding]::UTF8.GetString($result) | Should -Be 'the quick brown fox jumps over the lazy dog'
        }

        It 'treats x-gzip identically to gzip' {
            $plain = [System.Text.Encoding]::UTF8.GetBytes('x-gzip equivalence check')
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @('x-gzip') -InnerStream ([System.IO.MemoryStream]::new((New-GzipBytes $plain))) -Owner $owner -MaxDecompressedBytes 1024
            $result = Read-AllBytesSync $stream
            $stream.Dispose()
            [System.Text.Encoding]::UTF8.GetString($result) | Should -Be 'x-gzip equivalence check'
        }

        It 'fails fast on a decompression-bomb payload without buffering the full expansion' {
            $plain = [byte[]]::new(2000000)
            $owner = [SpikeDecompressionOwner]::new()
            $gzipBytes = New-GzipBytes $plain
            # A run of zeros compresses to a tiny payload but expands to ~2 MB;
            # a 4 KiB decompressed limit must trip long before full expansion.
            $stream = Expand-Test -ContentEncodings @('gzip') -InnerStream ([System.IO.MemoryStream]::new($gzipBytes)) -Owner $owner -MaxDecompressedBytes 4096
            $received = 0
            $threw = $false
            $category = $null
            try {
                $buf = [byte[]]::new(8192)
                while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $received += $n }
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'DecompressionLimitExceeded'
            $received | Should -BeLessOrEqual 4096
            $owner.Disposed | Should -BeTrue
        }

        It 'fails as DecompressionFailed on structurally malformed gzip content' {
            # A stream that is not gzip at all: bad magic header. GZipStream
            # reliably throws InvalidDataException for this shape.
            $badBytes = [byte[]](1..20)
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @('gzip') -InnerStream ([System.IO.MemoryStream]::new($badBytes)) -Owner $owner -MaxDecompressedBytes 1024
            $threw = $false
            $category = $null
            try {
                $buf = [byte[]]::new(64)
                $stream.Read($buf, 0, $buf.Length) | Out-Null
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'DecompressionFailed'
            $owner.Disposed | Should -BeTrue
        }

        It 'fails as DecompressionFailed on a corrupted deflate body' {
            # Empirically verified: .NET's GZipStream reliably throws
            # InvalidDataException when a byte inside the compressed body is
            # corrupted such that the bit stream becomes structurally
            # invalid (unlike plain truncation -- see the next test).
            $plain = [System.Text.Encoding]::UTF8.GetBytes(('The quick brown fox jumps over the lazy dog. ' * 200))
            $good = New-GzipBytes $plain
            $corrupt = [byte[]]$good.Clone()
            $mid = [int]($corrupt.Length * 0.5)
            $corrupt[$mid] = $corrupt[$mid] -bxor 0xFF
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @('gzip') -InnerStream ([System.IO.MemoryStream]::new($corrupt)) -Owner $owner -MaxDecompressedBytes $script:HardMaximumDecompressedBytes
            $threw = $false
            $category = $null
            try {
                $buf = [byte[]]::new(64)
                while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { }
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'DecompressionFailed'
            $owner.Disposed | Should -BeTrue
        }

        It 'decodes truncated-but-structurally-valid gzip input as a short result without a false success beyond what was actually decoded' {
            # IMPORTANT, empirically verified finding: .NET's GZipStream does
            # NOT reliably raise an exception for a compressed stream that is
            # simply cut short at an arbitrary byte boundary (missing
            # trailer, or cut mid-body) as long as the remaining bits do not
            # happen to decode to an invalid structure. Swept 11 truncation
            # points from 10%-99% of a 50 KB high-entropy payload plus every
            # header-only cut from 0-12 bytes during implementation: none
            # threw. Only genuinely corrupted bit patterns (previous test)
            # are caught as DecompressionFailed. This test documents and
            # pins that real behavior rather than asserting a guarantee the
            # underlying decoder does not provide: the wrapper must never
            # fabricate a success beyond what was truly decoded, and must
            # never hang or read unboundedly waiting for data that will not
            # arrive.
            $plain = [System.Text.Encoding]::UTF8.GetBytes(('The quick brown fox jumps over the lazy dog. ' * 200))
            $good = New-GzipBytes $plain
            $truncated = $good[0..([int]($good.Length * 0.5) - 1)]
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @('gzip') -InnerStream ([System.IO.MemoryStream]::new($truncated)) -Owner $owner -MaxDecompressedBytes $script:HardMaximumDecompressedBytes
            $result = Read-AllBytesSync $stream
            $stream.Dispose()
            $result.Count | Should -BeGreaterThan 0
            $result.Count | Should -BeLessThan $plain.Length
            $owner.Disposed | Should -BeTrue
        }
    }

    Context 'multiple encodings' {
        It 'decodes gzip,gzip in reverse application order' {
            $plain = [System.Text.Encoding]::UTF8.GetBytes('double-wrapped payload')
            $onceCompressed = New-GzipBytes $plain
            $twiceCompressed = New-GzipBytes $onceCompressed
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @('gzip', 'gzip') -InnerStream ([System.IO.MemoryStream]::new($twiceCompressed)) -Owner $owner -MaxDecompressedBytes 4096
            $result = Read-AllBytesSync $stream
            $stream.Dispose()
            [System.Text.Encoding]::UTF8.GetString($result) | Should -Be 'double-wrapped payload'
        }

        It 'produces a deterministic result across repeated runs of the same input' {
            $plain = [System.Text.Encoding]::UTF8.GetBytes('deterministic content encoding check, run twice')
            $bytes = New-GzipBytes (New-GzipBytes $plain)

            $ownerA = [SpikeDecompressionOwner]::new()
            $streamA = Expand-Test -ContentEncodings @('gzip', 'gzip') -InnerStream ([System.IO.MemoryStream]::new($bytes)) -Owner $ownerA -MaxDecompressedBytes 4096
            $resultA = Read-AllBytesSync $streamA
            $streamA.Dispose()

            $ownerB = [SpikeDecompressionOwner]::new()
            $streamB = Expand-Test -ContentEncodings @('gzip', 'gzip') -InnerStream ([System.IO.MemoryStream]::new($bytes)) -Owner $ownerB -MaxDecompressedBytes 4096
            $resultB = Read-AllBytesSync $streamB
            $streamB.Dispose()

            , $resultA | Should -Be (, $resultB)
        }
    }

    Context 'unsupported content encodings' {
        It 'rejects br as UnsupportedContentEncoding' {
            $owner = [SpikeDecompressionOwner]::new()
            $threw = $false
            $category = $null
            try {
                Expand-Test -ContentEncodings @('br') -InnerStream ([System.IO.MemoryStream]::new([byte[]]@(1, 2, 3))) -Owner $owner -MaxDecompressedBytes 1024 | Out-Null
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'UnsupportedContentEncoding'
            $owner.Disposed | Should -BeTrue
        }

        It 'rejects deflate as UnsupportedContentEncoding' {
            $owner = [SpikeDecompressionOwner]::new()
            $threw = $false
            $category = $null
            try {
                Expand-Test -ContentEncodings @('deflate') -InnerStream ([System.IO.MemoryStream]::new([byte[]]@(1, 2, 3))) -Owner $owner -MaxDecompressedBytes 1024 | Out-Null
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'UnsupportedContentEncoding'
            $owner.Disposed | Should -BeTrue
        }

        It 'rejects an arbitrary unknown token as UnsupportedContentEncoding' {
            $owner = [SpikeDecompressionOwner]::new()
            $threw = $false
            $category = $null
            try {
                Expand-Test -ContentEncodings @('zstd') -InnerStream ([System.IO.MemoryStream]::new([byte[]]@(1, 2, 3))) -Owner $owner -MaxDecompressedBytes 1024 | Out-Null
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'UnsupportedContentEncoding'
            $owner.Disposed | Should -BeTrue
        }

        It 'never instantiates ZipArchive or treats zip as a content encoding' {
            $owner = [SpikeDecompressionOwner]::new()
            $threw = $false
            $category = $null
            try {
                Expand-Test -ContentEncodings @('zip') -InnerStream ([System.IO.MemoryStream]::new([byte[]]@(1, 2, 3))) -Owner $owner -MaxDecompressedBytes 1024 | Out-Null
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'UnsupportedContentEncoding'
        }
    }

    Context 'limits' {
        It 'honors a smaller caller-requested limit' {
            $data = [byte[]](1..100)
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $owner -MaxDecompressedBytes 50
            $threw = $false
            $category = $null
            try {
                $buf = [byte[]]::new(10)
                while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { }
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'DecompressionLimitExceeded'
        }

        It 'rejects a caller-requested limit above the 256 MiB hard maximum before any payload is consumed' {
            $owner = [SpikeDecompressionOwner]::new()
            $threw = $false
            try {
                Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new([byte[]]@(1))) -Owner $owner -MaxDecompressedBytes ($script:HardMaximumDecompressedBytes + 1) | Out-Null
            }
            catch {
                $threw = $true
            }
            $threw | Should -BeTrue
            $owner.Disposed | Should -BeTrue
        }
    }

    Context 'sync and async read paths' {
        # Relying on Stream's default ReadAsync/BeginRead/EndRead machinery
        # (i.e. NOT overriding ReadAsync explicitly and letting a PowerShell
        # class's Read() be invoked from a .NET Task continuation thread)
        # reliably hung on the second ReadAsync call -- reproduced with both
        # a blocking GetAwaiter().GetResult() loop and a properly `await`-based
        # compiled C# driver. BoundedDecompressionStream now explicitly
        # overrides ReadAsync with a synchronous-completion implementation
        # (Task.FromResult/TaskCompletionSource) that never crosses that
        # continuation boundary; these tests are the regression coverage for
        # that fix and must keep passing without a timeout/hang.
        It 'enforces the same bound via sync Read and async ReadAsync, with equivalent output' {
            $plain = [System.Text.Encoding]::UTF8.GetBytes('sync and async parity check payload')
            $gzipBytes = New-GzipBytes $plain

            $ownerSync = [SpikeDecompressionOwner]::new()
            $syncStream = Expand-Test -ContentEncodings @('gzip') -InnerStream ([System.IO.MemoryStream]::new($gzipBytes)) -Owner $ownerSync -MaxDecompressedBytes 4096
            $syncResult = Read-AllBytesSync $syncStream
            $syncStream.Dispose()

            $ownerAsync = [SpikeDecompressionOwner]::new()
            $asyncStream = Expand-Test -ContentEncodings @('gzip') -InnerStream ([System.IO.MemoryStream]::new($gzipBytes)) -Owner $ownerAsync -MaxDecompressedBytes 4096
            $asyncResult = Read-AllBytesAsync $asyncStream
            $asyncStream.Dispose()

            , $syncResult | Should -Be (, $asyncResult)
            [System.Text.Encoding]::UTF8.GetString($syncResult) | Should -Be 'sync and async parity check payload'
        }

        It 'enforces DecompressionLimitExceeded identically via sync Read and async ReadAsync' {
            $data = [byte[]](1..20)

            $ownerSync = [SpikeDecompressionOwner]::new()
            $syncStream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $ownerSync -MaxDecompressedBytes 10
            $syncThrew = $false
            $syncCategory = $null
            try { Read-AllBytesSync $syncStream | Out-Null }
            catch { $syncThrew = $true; $syncCategory = Get-FailureCategory $_ }

            $ownerAsync = [SpikeDecompressionOwner]::new()
            $asyncStream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $ownerAsync -MaxDecompressedBytes 10
            $asyncThrew = $false
            $asyncCategory = $null
            try { Read-AllBytesAsync $asyncStream | Out-Null }
            catch { $asyncThrew = $true; $asyncCategory = Get-FailureCategory $_ }

            $syncThrew | Should -BeTrue
            $asyncThrew | Should -BeTrue
            $syncCategory | Should -Be 'DecompressionLimitExceeded'
            $asyncCategory | Should -Be $syncCategory
            $ownerSync.Disposed | Should -BeTrue
            $ownerAsync.Disposed | Should -BeTrue
        }
    }

    Context 'ownership and disposal' {
        It 'disposes the owner exactly once on the success path' {
            $data = [System.Text.Encoding]::UTF8.GetBytes('ok')
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $owner -MaxDecompressedBytes 1024
            Read-AllBytesSync $stream | Out-Null
            $stream.Dispose()
            $stream.Dispose()
            $owner.DisposeCount | Should -Be 1
        }

        It 'disposes the owner exactly once on a limit failure' {
            $data = [byte[]](1..20)
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $owner -MaxDecompressedBytes 5
            try { Read-AllBytesSync $stream | Out-Null } catch { }
            $stream.Dispose()
            $owner.DisposeCount | Should -Be 1
        }

        It 'disposes the owner exactly once on a malformed-content failure' {
            $badBytes = [byte[]](1..20)
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @('gzip') -InnerStream ([System.IO.MemoryStream]::new($badBytes)) -Owner $owner -MaxDecompressedBytes 1024
            try {
                $buf = [byte[]]::new(64)
                $stream.Read($buf, 0, $buf.Length) | Out-Null
            }
            catch { }
            $stream.Dispose()
            $owner.DisposeCount | Should -Be 1
        }

        It 'leaves no usable stream after a decompression failure' {
            $data = [byte[]](1..20)
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $owner -MaxDecompressedBytes 5
            try { Read-AllBytesSync $stream | Out-Null } catch { }
            { $stream.Read([byte[]]::new(1), 0, 1) } | Should -Throw -ExceptionType ([System.ObjectDisposedException])
        }
    }

    Context 'timeout and cancellation propagation' {
        It 'propagates underlying Cancelled and Timeout failures unchanged via sync Read, disposing the owner exactly once' {
            foreach ($simulatedCategory in @('Cancelled', 'Timeout')) {
                $owner = [SpikeDecompressionOwner]::new()
                $faulty = [SpikeFaultyTransportStream]::new($simulatedCategory, 'simulated underlying transport failure')
                $stream = Expand-Test -ContentEncodings @() -InnerStream $faulty -Owner $owner -MaxDecompressedBytes 1024
                $threw = $false
                $category = $null
                try {
                    $buf = [byte[]]::new(4)
                    $stream.Read($buf, 0, $buf.Length) | Out-Null
                }
                catch {
                    $threw = $true
                    $category = Get-FailureCategory $_
                }
                $threw | Should -BeTrue
                $category | Should -Be $simulatedCategory
                $category | Should -Not -Be 'DecompressionFailed'
                $owner.Disposed | Should -BeTrue
                $owner.DisposeCount | Should -Be 1
            }
        }

        It 'propagates underlying Cancelled and Timeout failures unchanged via async ReadAsync, disposing the owner exactly once' {
            foreach ($simulatedCategory in @('Cancelled', 'Timeout')) {
                $owner = [SpikeDecompressionOwner]::new()
                $faulty = [SpikeFaultyTransportStream]::new($simulatedCategory, 'simulated underlying transport failure')
                $stream = Expand-Test -ContentEncodings @() -InnerStream $faulty -Owner $owner -MaxDecompressedBytes 1024
                $threw = $false
                $category = $null
                try {
                    $buf = [byte[]]::new(4)
                    $task = $stream.ReadAsync($buf, 0, $buf.Length, [System.Threading.CancellationToken]::None)
                    $task.GetAwaiter().GetResult() | Out-Null
                }
                catch {
                    $threw = $true
                    $category = Get-FailureCategory $_
                }
                $threw | Should -BeTrue
                $category | Should -Be $simulatedCategory
                $category | Should -Not -Be 'DecompressionFailed'
                $owner.Disposed | Should -BeTrue
                $owner.DisposeCount | Should -Be 1
            }
        }

        It 'propagates an underlying Cancelled failure unchanged through gzip decoding, disposing the owner exactly once' {
            $owner = [SpikeDecompressionOwner]::new()
            $faulty = [SpikeFaultyTransportStream]::new('Cancelled', 'simulated underlying transport cancellation')
            $stream = Expand-Test -ContentEncodings @('gzip') -InnerStream $faulty -Owner $owner -MaxDecompressedBytes 1024
            $threw = $false
            $category = $null
            try {
                $buf = [byte[]]::new(4)
                $stream.Read($buf, 0, $buf.Length) | Out-Null
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'Cancelled'
            $owner.Disposed | Should -BeTrue
            $owner.DisposeCount | Should -Be 1
        }

        It 'propagates a generic unexpected underlying IO failure unchanged (not DecompressionFailed), disposing the owner exactly once' {
            foreach ($useAsync in @($false, $true)) {
                $owner = [SpikeDecompressionOwner]::new()
                $faulty = [SpikeGenericIOFaultyStream]::new()
                $stream = Expand-Test -ContentEncodings @() -InnerStream $faulty -Owner $owner -MaxDecompressedBytes 1024
                $threw = $false
                $exceptionType = $null
                $category = $null
                try {
                    $buf = [byte[]]::new(4)
                    if ($useAsync) {
                        $task = $stream.ReadAsync($buf, 0, $buf.Length, [System.Threading.CancellationToken]::None)
                        $task.GetAwaiter().GetResult() | Out-Null
                    }
                    else {
                        $stream.Read($buf, 0, $buf.Length) | Out-Null
                    }
                }
                catch {
                    $threw = $true
                    $exceptionType = $_.Exception.GetType().FullName
                    if ($_.Exception.InnerException) { $exceptionType = $_.Exception.InnerException.GetType().FullName }
                    $category = Get-FailureCategory $_
                }
                $threw | Should -BeTrue -Because "useAsync=$useAsync"
                $exceptionType | Should -Be 'System.IO.IOException' -Because "useAsync=$useAsync"
                $category | Should -Not -Be 'DecompressionFailed' -Because "useAsync=$useAsync"
                $owner.Disposed | Should -BeTrue -Because "useAsync=$useAsync"
                $owner.DisposeCount | Should -Be 1 -Because "useAsync=$useAsync"
            }
        }
    }

    Context 'ReadAsync cancellation' {
        It 'completes as cancelled without consuming any bytes when the token is already cancelled' {
            $data = [byte[]](1..20)
            $owner = [SpikeDecompressionOwner]::new()
            $innerStream = [System.IO.MemoryStream]::new($data)
            $stream = Expand-Test -ContentEncodings @() -InnerStream $innerStream -Owner $owner -MaxDecompressedBytes 10
            $cts = [System.Threading.CancellationTokenSource]::new()
            $cts.Cancel()

            $buf = [byte[]]::new(4)
            $task = $stream.ReadAsync($buf, 0, $buf.Length, $cts.Token)

            $task.Status | Should -Be 'Canceled'
            $innerStream.Position | Should -Be 0
            $owner.Disposed | Should -BeTrue

            $threw = $false
            $exceptionType = $null
            try {
                $task.GetAwaiter().GetResult() | Out-Null
            }
            catch {
                $threw = $true
                $exceptionType = $_.Exception.GetType()
                if (-not $exceptionType.IsSubclassOf([System.OperationCanceledException]) -and
                    $_.Exception.InnerException) {
                    $exceptionType = $_.Exception.InnerException.GetType()
                }
            }
            $threw | Should -BeTrue
            ($exceptionType -eq [System.Threading.Tasks.TaskCanceledException] -or
                $exceptionType.IsSubclassOf([System.OperationCanceledException])) | Should -BeTrue -Because "actual type was $exceptionType"
        }

        It 'propagates cancellation requested mid-read as cancellation, not DecompressionFailed, and disposes the owner' {
            $data = [byte[]](1..50)
            $owner = [SpikeDecompressionOwner]::new()
            $slow = [SpikeSlowAsyncStream]::new($data, 5000)
            $stream = Expand-Test -ContentEncodings @() -InnerStream $slow -Owner $owner -MaxDecompressedBytes 1024
            $cts = [System.Threading.CancellationTokenSource]::new()
            $cts.CancelAfter(200)

            $buf = [byte[]]::new(10)
            $threw = $false
            $exceptionType = $null
            $category = $null
            try {
                $task = $stream.ReadAsync($buf, 0, $buf.Length, $cts.Token)
                $task.GetAwaiter().GetResult() | Out-Null
            }
            catch {
                $threw = $true
                $exceptionType = $_.Exception.GetType().FullName
                if ($exceptionType -notmatch 'Cancel' -and $_.Exception.InnerException) {
                    $exceptionType = $_.Exception.InnerException.GetType().FullName
                }
                $category = Get-FailureCategory $_
            }

            $threw | Should -BeTrue
            $exceptionType | Should -Match 'Cancel'
            $category | Should -Not -Be 'DecompressionFailed'
            $owner.Disposed | Should -BeTrue
        }

        It 'still enforces DecompressionLimitExceeded via ReadAsync and never returns the over-limit byte' {
            $data = [byte[]](1..11)
            $owner = [SpikeDecompressionOwner]::new()
            $stream = Expand-Test -ContentEncodings @() -InnerStream ([System.IO.MemoryStream]::new($data)) -Owner $owner -MaxDecompressedBytes 10
            $received = [System.Collections.Generic.List[byte]]::new()
            $threw = $false
            $category = $null
            try {
                $buf = [byte[]]::new(3)
                while ($true) {
                    $task = $stream.ReadAsync($buf, 0, $buf.Length, [System.Threading.CancellationToken]::None)
                    $n = $task.GetAwaiter().GetResult()
                    if ($n -eq 0) { break }
                    for ($i = 0; $i -lt $n; $i++) { $received.Add($buf[$i]) }
                }
            }
            catch {
                $threw = $true
                $category = Get-FailureCategory $_
            }
            $threw | Should -BeTrue
            $category | Should -Be 'DecompressionLimitExceeded'
            $received.Count | Should -BeLessOrEqual 10
            $received.Contains([byte]11) | Should -BeFalse
            $owner.Disposed | Should -BeTrue
        }
    }
}
