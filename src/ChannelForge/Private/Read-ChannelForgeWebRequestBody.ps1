function Read-ChannelForgeWebRequestBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][long]$ContentLength,
        [int]$MaxBytes = 24MB
    )

    if ($ContentLength -lt 0) {
        throw [System.ArgumentException]::new('A Content-Length header is required for POST requests.')
    }
    if ($ContentLength -gt $MaxBytes) {
        throw [System.InvalidOperationException]::new('The proposal request is too large.')
    }
    if ($ContentLength -eq 0) {
        return [byte[]]::new(0)
    }

    $output = [System.IO.MemoryStream]::new([int]$ContentLength)
    $buffer = [byte[]]::new([Math]::Min(81920, [int]$ContentLength))
    $total = 0L
    try {
        while ($total -lt $ContentLength) {
            $remaining = [int]($ContentLength - $total)
            $read = $Stream.Read($buffer, 0, [Math]::Min($buffer.Length, $remaining))
            if ($read -le 0) {
                throw [System.ArgumentException]::new('The request body ended before the declared Content-Length.')
            }
            $output.Write($buffer, 0, $read)
            $total += $read
        }
        return $output.ToArray()
    }
    finally {
        $output.Dispose()
    }
}
