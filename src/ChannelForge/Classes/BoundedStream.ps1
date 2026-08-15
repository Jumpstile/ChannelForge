class BoundedStream : System.IO.Stream {
    [System.IO.Stream]$InnerStream
    [long]$MaximumBytes
    [long]$BytesRead
    [bool]$LimitChecked
    [bool]$LimitExceeded

    [bool]$CanRead
    [bool]$CanSeek
    [bool]$CanWrite
    [long]$Length
    [long]$Position

    BoundedStream([System.IO.Stream]$InnerStream, [long]$MaximumBytes) {
        if ($null -eq $InnerStream) {
            throw [System.ArgumentNullException]::new('InnerStream')
        }

        if (-not $InnerStream.CanRead) {
            throw [System.ArgumentException]::new('The inner stream must be readable.', 'InnerStream')
        }

        if ($MaximumBytes -le 0) {
            throw [System.ArgumentOutOfRangeException]::new('MaximumBytes')
        }

        $this.InnerStream = $InnerStream
        $this.MaximumBytes = $MaximumBytes
        $this.BytesRead = 0
        $this.LimitChecked = $false
        $this.LimitExceeded = $false
        $this.CanRead = $true
        $this.CanSeek = $false
        $this.CanWrite = $false
        $this.Length = $MaximumBytes
        $this.Position = 0
    }

    [void] Flush() {
    }

    [int] Read([byte[]]$Buffer, [int]$Offset, [int]$Count) {
        if ($null -eq $Buffer) {
            throw [System.ArgumentNullException]::new('Buffer')
        }

        if ($Offset -lt 0 -or $Count -lt 0 -or ($Offset + $Count) -gt $Buffer.Length) {
            throw [System.ArgumentOutOfRangeException]::new('Offset/Count')
        }

        if ($Count -eq 0) {
            return 0
        }

        $remaining = $this.MaximumBytes - $this.BytesRead
        if ($remaining -le 0) {
            if (-not $this.LimitChecked) {
                $probe = [byte[]]::new(1)
                $probeCount = $this.InnerStream.Read($probe, 0, 1)
                $this.LimitChecked = $true
                if ($probeCount -gt 0) {
                    $this.LimitExceeded = $true
                }
            }

            return 0
        }

        $readCount = [int][math]::Min([long]$Count, $remaining)
        $read = $this.InnerStream.Read($Buffer, $Offset, $readCount)
        if ($read -gt 0) {
            $this.BytesRead += $read
            $this.Position = $this.BytesRead
        }

        return $read
    }

    [long] Seek([long]$Offset, [System.IO.SeekOrigin]$Origin) {
        throw [System.NotSupportedException]::new('BoundedStream is not seekable.')
    }

    [void] SetLength([long]$Value) {
        throw [System.NotSupportedException]::new('BoundedStream is read-only.')
    }

    [void] Write([byte[]]$Buffer, [int]$Offset, [int]$Count) {
        throw [System.NotSupportedException]::new('BoundedStream is read-only.')
    }

    [void] EnsureWithinLimit() {
        while ($this.BytesRead -lt $this.MaximumBytes) {
            $remaining = $this.MaximumBytes - $this.BytesRead
            $bufferSize = [int][math]::Min(8192, $remaining)
            $buffer = [byte[]]::new($bufferSize)
            $read = $this.Read($buffer, 0, $buffer.Length)
            if ($read -eq 0) {
                break
            }
        }

        if ($this.BytesRead -ge $this.MaximumBytes -and -not $this.LimitChecked) {
            $probe = [byte[]]::new(1)
            $probeCount = $this.InnerStream.Read($probe, 0, 1)
            $this.LimitChecked = $true
            if ($probeCount -gt 0) {
                $this.LimitExceeded = $true
            }
        }

        if ($this.LimitExceeded) {
            throw [System.IO.InvalidDataException]::new("XMLTV document exceeds the configured maximum of $($this.MaximumBytes) bytes.")
        }
    }

    [void] Dispose([bool]$Disposing) {
        if ($Disposing -and $null -ne $this.InnerStream) {
            $this.InnerStream.Dispose()
            $this.InnerStream = $null
        }
    }
}
