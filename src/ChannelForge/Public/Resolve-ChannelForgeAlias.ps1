function Resolve-ChannelForgeAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$AliasPath
    )

    # Alias data is external configuration, so validate the file exists first.
    if (-not (Test-Path -LiteralPath $AliasPath -PathType Leaf)) {
        throw "Alias file not found: $AliasPath"
    }

    # Alias resolution is deterministic by design.
    # No fuzzy matching happens here. If no exact alias exists, return the input name.
    $aliasConfig = Get-Content -LiteralPath $AliasPath -Raw | ConvertFrom-Json
    $candidate = $Name.Trim()

    foreach ($entry in $aliasConfig.aliases) {
        if ($entry.canonical.Trim() -ieq $candidate) {
            return $entry.canonical
        }

        foreach ($alias in $entry.aliases) {
            if ($alias.Trim() -ieq $candidate) {
                return $entry.canonical
            }
        }
    }

    return $candidate
}