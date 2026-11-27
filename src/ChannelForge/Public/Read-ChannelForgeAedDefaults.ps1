function Read-ChannelForgeAedDefaults {
    <#
    .SYNOPSIS
        Reads an IPTV Boss "AED defaults" export file. Read-only.
    .DESCRIPTION
        Checks the file against schemas/aed-defaults.schema.json and returns the
        known defaults plus plain-words warnings. Unknown defaults are dropped
        with a warning. Any text that looks like a web address is blanked with a
        warning, so no address, host or login can leave this function.
        Writes nothing and changes no guide, M3U, XMLTV or accepted state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$SchemaPath = (Join-Path $PSScriptRoot '..\..\..\schemas\aed-defaults.schema.json')
    )

    $urlLike = '://'

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'The AED defaults file was not found. Details: check the path you gave.'
    }

    $json = Get-Content -LiteralPath $Path -Raw
    try {
        $isValid = Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction Stop
        $detail = 'the file does not match the AED defaults format.'
    }
    catch {
        $isValid = $false
        $detail = [string]$_.Exception.Message
    }
    if (-not $isValid) {
        # Error text can repeat file text; never let a web address through.
        if ($detail.Contains($urlLike)) { $detail = 'the file does not match the AED defaults format.' }
        throw "This is not a valid AED defaults export. Details: $detail"
    }

    $source = $json | ConvertFrom-Json
    $allowed = @(
        (Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json).properties.defaults.properties.PSObject.Properties.Name
    )
    $warnings = [System.Collections.Generic.List[string]]::new()
    $defaults = [ordered]@{}

    foreach ($name in $allowed) {
        if ($source.defaults.PSObject.Properties.Name -notcontains $name) { continue }
        $value = $source.defaults.$name
        $isUrlText = ($value -is [string]) -and (($name -eq 'logo_url' -and $value -ne '') -or $value.Contains($urlLike))
        if ($isUrlText) {
            $warnings.Add("The setting '$name' held a web address. It was removed.")
            $value = ''
        }
        $defaults[$name] = $value
    }

    foreach ($name in $source.defaults.PSObject.Properties.Name) {
        if ($allowed -contains $name) { continue }
        # The name itself is shown, so hide it if it looks like a web address.
        $shown = if ($name.Contains($urlLike)) { '(hidden)' } else { $name }
        $warnings.Add("Unknown setting '$shown' was ignored.")
    }

    [pscustomobject]@{
        Defaults = [pscustomobject]$defaults
        Warnings = @($warnings)
    }
}
