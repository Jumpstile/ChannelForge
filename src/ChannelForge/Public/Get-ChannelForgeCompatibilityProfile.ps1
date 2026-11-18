function Get-ChannelForgeCompatibilityProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$SchemaPath = (Join-Path $PSScriptRoot '..\..\..\schemas\compatibility-profile.schema.json')
    )

    # Read-only: loads and checks one profile file. Writes nothing.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Compatibility profile file not found: $Path"
    }

    $json = Get-Content -LiteralPath $Path -Raw
    $isValid = $false
    try {
        $isValid = Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction Stop
    }
    catch {
        throw "Compatibility profile is not valid ($Path): $($_.Exception.Message)"
    }
    if (-not $isValid) {
        throw "Compatibility profile is not valid: $Path"
    }

    return ($json | ConvertFrom-Json)
}
