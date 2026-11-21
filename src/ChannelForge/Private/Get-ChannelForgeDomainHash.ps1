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

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $domainLength = $utf8.GetByteCount($Domain)
    if ($PSCmdlet.ParameterSetName -eq 'Object') {
        $json = ConvertTo-ChannelForgeCanonicalJson -InputObject $InputObject
        $buffer = [byte[]]::new($domainLength + 1 + $utf8.GetByteCount($json))
        [void]$utf8.GetBytes($json, 0, $json.Length, $buffer, $domainLength + 1)
    }
    else {
        $buffer = [byte[]]::new($domainLength + 1 + $Bytes.Length)
        [System.Buffer]::BlockCopy($Bytes, 0, $buffer, $domainLength + 1, $Bytes.Length)
    }
    [void]$utf8.GetBytes($Domain, 0, $Domain.Length, $buffer, 0)

    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($buffer)).ToLowerInvariant()
}
