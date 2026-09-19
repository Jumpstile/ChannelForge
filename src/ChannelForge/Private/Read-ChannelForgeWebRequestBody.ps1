function Read-ChannelForgeWebRequestBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][long]$ContentLength,
        [int]$MaxBytes = 24MB
    )

    if ($ContentLength -gt $MaxBytes) { throw [System.InvalidOperationException]::new('The proposal request is too large.') }
    $buffer = [byte[]]::new(81920)
    $output = [System.IO.MemoryStream]::new()
    $total = 0L
    try {
        while (($read = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt $MaxBytes) { throw [System.InvalidOperationException]::new('The proposal request is too large.') }
            $output.Write($buffer, 0, $read)
        }
        if ($ContentLength -ge 0 -and $total -ne $ContentLength) { throw [System.ArgumentException]::new('The proposal request length does not match its body.') }
        return $output.ToArray()
    }
    finally {
        $output.Dispose()
    }
}
