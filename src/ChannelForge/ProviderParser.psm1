function Read-ChannelForgeProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Provider file not found: $Path"
    }

    $provider = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    foreach ($source in $provider.sources) {
        [pscustomobject]@{
            Name    = $source.name
            Group   = $source.group
            Url     = $source.url
            Enabled = [bool]$source.enabled
        }
    }
}

Export-ModuleMember -Function Read-ChannelForgeProvider