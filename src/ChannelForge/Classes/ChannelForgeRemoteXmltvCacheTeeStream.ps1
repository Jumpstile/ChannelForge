class ChannelForgeRemoteXmltvCacheTeeStream : System.IO.Stream {
    [System.IO.Stream]$InnerStream
    [System.IO.FileStream]$CacheStream
    [System.Security.Cryptography.SHA256]$HashAlgorithm
    [long]$BytesRead
    [bool]$Disposed
    [bool]$WriteFailed
    [string]$FinalHash

    [bool]$CanRead
    [bool]$CanSeek
    [bool]$CanWrite
    [long]$Length
    [long]$Position

    ChannelForgeRemoteXmltvCacheTeeStream(
        [System.IO.Stream]$InnerStream,
        [string]$CachePath
    ) {
        if ($null -eq $InnerStream) {
            throw [System.ArgumentNullException]::new('InnerStream')
        }

        if (-not $InnerStream.CanRead) {
            throw [System.ArgumentException]::new('The inner stream must be readable.', 'InnerStream')
        }

        if ([string]::IsNullOrWhiteSpace($CachePath)) {
            throw [System.ArgumentException]::new('The cache path must be non-empty.', 'CachePath')
        }

        $this.InnerStream = $InnerStream
        $this.CacheStream = [System.IO.FileStream]::new(
            $CachePath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            81920,
            [System.IO.FileOptions]::SequentialScan)
        $this.HashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
        $this.BytesRead = 0
        $this.Disposed = $false
        $this.WriteFailed = $false
        $this.FinalHash = $null
        $this.CanRead = $true
        $this.CanSeek = $false
        $this.CanWrite = $false
        $this.Length = 0
        $this.Position = 0
    }

    [void] Flush() {
        if ($this.Disposed) {
            throw [System.ObjectDisposedException]::new('ChannelForgeRemoteXmltvCacheTeeStream')
        }

        $this.CacheStream.Flush()
    }

    [int] Read(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Count
    ) {
        if ($null -eq $Buffer) {
            throw [System.ArgumentNullException]::new('Buffer')
        }

        if ($Offset -lt 0 -or $Count -lt 0 -or ($Offset + $Count) -gt $Buffer.Length) {
            throw [System.ArgumentOutOfRangeException]::new('Offset/Count')
        }

        if ($this.Disposed) {
            throw [System.ObjectDisposedException]::new('ChannelForgeRemoteXmltvCacheTeeStream')
        }

        if ($Count -eq 0) {
            return 0
        }

        $read = $this.InnerStream.Read($Buffer, $Offset, $Count)
        if ($read -gt 0) {
            try {
                $this.CacheStream.Write($Buffer, $Offset, $read)
                [void]$this.HashAlgorithm.TransformBlock($Buffer, $Offset, $read, $Buffer, $Offset)
                $this.BytesRead += $read
                $this.Position = $this.BytesRead
            }
            catch {
                $exception = [System.InvalidOperationException]::new(
                    'The remote XMLTV cache payload could not be written.',
                    $_.Exception)
                $exception.Data['ChannelForgeFailureCategory'] = 'CacheWriteFailure'
                $this.Dispose()
                throw $exception
            }
        }

        return $read
    }

    [System.Threading.Tasks.Task[int]] ReadAsync(
        [byte[]]$Buffer,
        [int]$Offset,
        [int]$Count,
        [System.Threading.CancellationToken]$CancellationToken
    ) {
        if ($CancellationToken.IsCancellationRequested) {
            throw [System.OperationCanceledException]::new($CancellationToken)
        }

        return [System.Threading.Tasks.Task[int]]::FromResult(
            $this.Read($Buffer, $Offset, $Count))
    }

    [void] Complete() {
        if ([string]::IsNullOrEmpty($this.FinalHash)) {
            [void]$this.HashAlgorithm.TransformFinalBlock([byte[]]::new(0), 0, 0)
            $this.FinalHash = [Convert]::ToHexString($this.HashAlgorithm.Hash).ToLowerInvariant()
        }

        $this.CacheStream.Flush($true)
    }

    [string] GetHashHex() {
        if ([string]::IsNullOrEmpty($this.FinalHash)) {
            $this.Complete()
        }

        return $this.FinalHash
    }

    [long] Seek([long]$Offset, [System.IO.SeekOrigin]$Origin) {
        throw [System.NotSupportedException]::new('The cache tee is not seekable.')
    }

    [void] SetLength([long]$Value) {
        throw [System.NotSupportedException]::new('The cache tee is read-only.')
    }

    [void] Write([byte[]]$Buffer, [int]$Offset, [int]$Count) {
        throw [System.NotSupportedException]::new('The cache tee is read-only.')
    }

    [void] Dispose([bool]$Disposing) {
        if ($this.Disposed) {
            return
        }

        if ($Disposing) {
            try {
                $this.Complete()
            }
            catch {
                $this.WriteFailed = $true
                # The cache transaction validates the final hash and file length
                # after parser success. Disposal must still close the temporary
                # file if flushing fails.
            }
            try {
                $this.CacheStream.Dispose()
            }
            catch {
            }
            try {
                $this.HashAlgorithm.Dispose()
            }
            catch {
            }
        }

        $this.Disposed = $true
    }
}
