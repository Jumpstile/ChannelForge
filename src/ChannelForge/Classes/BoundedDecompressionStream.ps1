class BoundedDecompressionStream : System.IO.Stream {
    static [long] $HardMaximumDecompressedBytes = 268435456

    [System.IO.Stream]$Source
    [System.IO.Stream[]]$OwnedStreams
    [System.IDisposable]$Owner
    [long]$MaximumBytes
    [long]$BytesRead
    [bool]$LimitChecked
    [bool]$Disposed

    [bool]$CanRead
    [bool]$CanSeek
    [bool]$CanWrite
    [long]$Length
    [long]$Position

    BoundedDecompressionStream(
        [System.IO.Stream]$Source,
        [System.IO.Stream[]]$OwnedStreams,
        [System.IDisposable]$Owner,
        [long]$MaximumBytes
    ) {
        if ($null -eq $Source) {
            throw [System.ArgumentNullException]::new('Source')
        }

        if (-not $Source.CanRead) {
            throw [System.ArgumentException]::new('The decoded source stream must be readable.', 'Source')
        }

        if ($null -eq $Owner) {
            throw [System.ArgumentNullException]::new('Owner')
        }

        if ($MaximumBytes -le 0 -or $MaximumBytes -gt [BoundedDecompressionStream]::HardMaximumDecompressedBytes) {
            throw [System.ArgumentOutOfRangeException]::new('MaximumBytes')
        }

        $this.Source = $Source
        $this.OwnedStreams = if ($null -eq $OwnedStreams) { @() } else { @($OwnedStreams) }
        $this.Owner = $Owner
        $this.MaximumBytes = $MaximumBytes
        $this.BytesRead = 0
        $this.LimitChecked = $false
        $this.Disposed = $false
        $this.CanRead = $true
        $this.CanSeek = $false
        $this.CanWrite = $false
        $this.Length = $MaximumBytes
        $this.Position = 0
    }

    [void] Flush() {
    }

    hidden [void] ValidateReadArguments([byte[]]$Buffer, [int]$Offset, [int]$Count) {
        if ($null -eq $Buffer) {
            throw [System.ArgumentNullException]::new('Buffer')
        }

        if ($Offset -lt 0 -or $Count -lt 0 -or ($Offset + $Count) -gt $Buffer.Length) {
            throw [System.ArgumentOutOfRangeException]::new('Offset/Count')
        }
    }

    [int] Read([byte[]]$Buffer, [int]$Offset, [int]$Count) {
        $this.ValidateReadArguments($Buffer, $Offset, $Count)

        if ($this.Disposed) {
            throw [System.ObjectDisposedException]::new('BoundedDecompressionStream')
        }

        if ($Count -eq 0) {
            return 0
        }

        return $this.ReadCore($Buffer, $Offset, $Count, $false, [System.Threading.CancellationToken]::None)
    }

    # ReadAsync MUST be explicitly overridden here rather than relying on
    # Stream's default ReadAsync/BeginRead/EndRead machinery. That default
    # machinery schedules the actual read as a .NET Task continuation, and
    # invoking a PowerShell class's script-defined method body from that
    # continuation's thread reliably HANGS (verified empirically: reproduced
    # with both a plain PowerShell await-blocking loop and a properly
    # `await`-based compiled C# driver -- the first ReadAsync call on a given
    # instance completes, the second one deadlocks indefinitely). This
    # override never relies on that default machinery: it always completes
    # synchronously from the caller's own thread, either immediately (via
    # Task.FromResult/TaskCompletionSource) or by blocking on
    # Source.ReadAsync(...).GetAwaiter().GetResult() -- which is safe because
    # Source is always a compiled stream (GZipStream, MemoryStream, or the
    # transport's own ChannelForgeBoundedResponseStream), never another
    # PowerShell-class method body, so no continuation ever needs to call
    # back into PowerShell script code from a foreign thread. Verified
    # empirically for both the classic byte[] overload and the modern
    # ReadAsync(Memory<byte>, CancellationToken) overload (whose own
    # Stream-provided default implementation delegates to this one when the
    # memory wraps an array). Do not remove this override or "simplify" it
    # back to relying on the base class default, and do not have it silently
    # delegate to the synchronous Read() below -- the supplied
    # CancellationToken must actually reach Source.ReadAsync so real
    # cancellation (already-requested or mid-read) is genuinely observed,
    # not merely accepted and ignored.
    [System.Threading.Tasks.Task[int]] ReadAsync(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Count,
        [System.Threading.CancellationToken]$CancellationToken
    ) {
        $this.ValidateReadArguments($Buffer, $Offset, $Count)

        if ($this.Disposed) {
            throw [System.ObjectDisposedException]::new('BoundedDecompressionStream')
        }

        if ($CancellationToken.IsCancellationRequested) {
            # Cancelled before any byte was requested from Source: complete as
            # cancelled without touching Source at all, and still release the
            # owner -- a caller that observes a cancelled ReadAsync is not
            # expected to separately dispose this stream, and this wrapper's
            # whole purpose is to guarantee the owned transport payload/lease
            # is never left dangling once this stream stops being usable.
            $this.Dispose()
            $cancelledSource = [System.Threading.Tasks.TaskCompletionSource[int]]::new()
            $cancelledSource.SetCanceled($CancellationToken)
            return $cancelledSource.Task
        }

        if ($Count -eq 0) {
            return [System.Threading.Tasks.Task]::FromResult(0)
        }

        try {
            $result = $this.ReadCore($Buffer, $Offset, $Count, $true, $CancellationToken)
            return [System.Threading.Tasks.Task]::FromResult($result)
        }
        catch [System.OperationCanceledException] {
            $this.Dispose()
            $cancelledSource = [System.Threading.Tasks.TaskCompletionSource[int]]::new()
            $cancelledSource.SetCanceled($CancellationToken)
            return $cancelledSource.Task
        }
        catch {
            # ReadCore already disposed (via FailMalformed/FailLimitExceeded,
            # or the generic underlying-failure handler below) before this
            # exception reached here; Dispose() is idempotent regardless.
            # The original exception -- including a foreign
            # ChannelForgeFailureCategory such as Cancelled or Timeout -- is
            # forwarded unchanged, never recategorized.
            $completionSource = [System.Threading.Tasks.TaskCompletionSource[int]]::new()
            $completionSource.SetException($_.Exception)
            return $completionSource.Task
        }
    }

    # Shared by both Read() and ReadAsync() so decompressed-byte-bound
    # enforcement, the exact-limit/probe behavior, and error mapping are
    # identical on both paths by construction rather than by convention.
    # UseAsync selects whether bytes are pulled from Source via its
    # synchronous Read or its cancellable ReadAsync; every other decision is
    # shared code.
    hidden [int] ReadCore(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Count,
        [bool]$UseAsync,
        [System.Threading.CancellationToken]$CancellationToken
    ) {
        $remaining = $this.MaximumBytes - $this.BytesRead
        if ($remaining -le 0) {
            if (-not $this.LimitChecked) {
                $this.LimitChecked = $true
                $probe = [byte[]]::new(1)
                $probeCount = 0
                try {
                    $probeCount = $this.ReadFromSource($probe, 0, 1, $UseAsync, $CancellationToken)
                }
                catch [System.IO.InvalidDataException] {
                    $this.FailMalformed()
                }
                catch {
                    $this.FailPropagated($_.Exception)
                }

                if ($probeCount -gt 0) {
                    $this.FailLimitExceeded()
                }
            }

            return 0
        }

        # Request one more byte than remains so a crossing is detected before any
        # over-limit byte is ever copied into the caller's buffer.
        $requested = [int][Math]::Min([long]$Count, $remaining + 1)
        $temp = [byte[]]::new($requested)
        $read = 0
        try {
            $read = $this.ReadFromSource($temp, 0, $temp.Length, $UseAsync, $CancellationToken)
        }
        catch [System.IO.InvalidDataException] {
            $this.FailMalformed()
        }
        catch {
            $this.FailPropagated($_.Exception)
        }

        if ($read -gt $remaining) {
            $this.FailLimitExceeded()
        }

        if ($read -gt 0) {
            [Array]::Copy($temp, 0, $Buffer, $Offset, $read)
            $this.BytesRead += $read
        }

        return $read
    }

    hidden [int] ReadFromSource(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Count,
        [bool]$UseAsync,
        [System.Threading.CancellationToken]$CancellationToken
    ) {
        if ($UseAsync) {
            return $this.Source.ReadAsync($Buffer, $Offset, $Count, $CancellationToken).GetAwaiter().GetResult()
        }

        return $this.Source.Read($Buffer, $Offset, $Count)
    }

    [long] Seek([long]$Offset, [System.IO.SeekOrigin]$Origin) {
        throw [System.NotSupportedException]::new('BoundedDecompressionStream is not seekable.')
    }

    [void] SetLength([long]$Value) {
        throw [System.NotSupportedException]::new('BoundedDecompressionStream is read-only.')
    }

    [void] Write([byte[]]$Buffer, [int]$Offset, [int]$Count) {
        throw [System.NotSupportedException]::new('BoundedDecompressionStream is read-only.')
    }

    hidden [void] FailLimitExceeded() {
        $this.Dispose()
        $exception = [System.InvalidOperationException]::new(
            'the expanded content exceeded the configured decompressed-byte limit.')
        $exception.Data['ChannelForgeFailureCategory'] = 'DecompressionLimitExceeded'
        throw $exception
    }

    hidden [void] FailMalformed() {
        $this.Dispose()
        $exception = [System.InvalidOperationException]::new(
            'the compressed content could not be decoded.')
        $exception.Data['ChannelForgeFailureCategory'] = 'DecompressionFailed'
        throw $exception
    }

    # Any failure reading from Source that is not itself a decoding problem --
    # underlying cancellation, an underlying timeout, or any other unexpected
    # IO/read exception -- still means this stream (and the owner it holds)
    # must be torn down exactly once here, on this single shared read path,
    # before the ORIGINAL exception is rethrown unchanged. This must never
    # repackage or recategorize the original exception (e.g. a transport
    # Cancelled/Timeout ChannelForgeFailureCategory) as DecompressionFailed.
    hidden [void] FailPropagated([System.Exception]$OriginalException) {
        $this.Dispose()
        throw $OriginalException
    }

    # This stream owns disposal of the entire decoding wrapper chain plus the
    # supplied acquisition owner (e.g. the transport payload/lease). Every
    # intermediate decoding stream is constructed with leaveOpen so none of them
    # independently cascades disposal -- this method is the single, unambiguous
    # point where everything is torn down, exactly once, on every path.
    [void] Dispose([bool]$Disposing) {
        if ($this.Disposed) {
            return
        }

        $this.Disposed = $true

        if ($Disposing) {
            foreach ($stream in $this.OwnedStreams) {
                try {
                    $stream.Dispose()
                }
                catch {
                    # Best-effort teardown of an intermediate layer; owner
                    # disposal below is authoritative and must still run.
                }
            }

            try {
                $this.Owner.Dispose()
            }
            catch {
                # Disposal failures must never mask the originating read failure.
            }
        }
    }
}
