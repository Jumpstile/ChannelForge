function Get-ChannelForgeDomainHash {
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9./-]+$')]
        [string]$Domain,

        [Parameter(Mandatory, ParameterSetName = 'Object')]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Bytes')]
        [byte[]]$Bytes
    )

    [byte[]]$payload = if ($PSCmdlet.ParameterSetName -eq 'Object') {
        $json = ConvertTo-ChannelForgeCanonicalJson -InputObject $InputObject
        [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    }
    else {
        [byte[]]$Bytes
    }

    [byte[]]$domainBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Domain)
    $buffer = [byte[]]::new($domainBytes.Length + 1 + $payload.Length)
    [System.Buffer]::BlockCopy($domainBytes, 0, $buffer, 0, $domainBytes.Length)
    $buffer[$domainBytes.Length] = 0
    [System.Buffer]::BlockCopy($payload, 0, $buffer, $domainBytes.Length + 1, $payload.Length)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($buffer))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}
