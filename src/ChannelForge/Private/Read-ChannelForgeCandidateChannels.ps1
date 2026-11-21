function Read-ChannelForgeCandidateChannels {
    # The channels of a sealed candidate, read from its merged.m3u. Read only.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $document = [System.Text.Json.JsonDocument]::Parse($utf8.GetString([System.IO.File]::ReadAllBytes((Join-Path $Directory 'manifest.json'))))
    try {
        $contractVersion = ''
        if ($document.RootElement.ValueKind -eq 'Object') {
            foreach ($property in $document.RootElement.EnumerateObject()) {
                if ($property.Name -ceq 'ContractVersion') { $contractVersion = $property.Value.ToString() }
            }
        }
    }
    finally { $document.Dispose() }
    $reader = [System.IO.StreamReader]::new((Join-Path $Directory 'merged.m3u'), $utf8)
    try { return @(Read-ChannelForgeM3UReader -Reader $reader -CandidateContractVersion $contractVersion) }
    finally { $reader.Dispose() }
}
