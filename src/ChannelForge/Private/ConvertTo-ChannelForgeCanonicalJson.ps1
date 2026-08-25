function ConvertTo-ChannelForgeCanonicalJson {
    [CmdletBinding()]
    param([AllowNull()][object]$InputObject)

    $builder = [System.Text.StringBuilder]::new()
    $slash = [char]92

    function Write-JsonString {
        param([AllowNull()][string]$Value)
        if ($null -eq $Value) { [void]$builder.Append('null'); return }
        [void]$builder.Append([char]34)
        for ($index = 0; $index -lt $Value.Length; $index++) {
            $character = $Value[$index]
            $code = [int][char]$character
            if ($code -eq 8) { [void]$builder.Append($slash); [void]$builder.Append('b'); continue }
            if ($code -eq 9) { [void]$builder.Append($slash); [void]$builder.Append('t'); continue }
            if ($code -eq 10) { [void]$builder.Append($slash); [void]$builder.Append('n'); continue }
            if ($code -eq 12) { [void]$builder.Append($slash); [void]$builder.Append('f'); continue }
            if ($code -eq 13) { [void]$builder.Append($slash); [void]$builder.Append('r'); continue }
            if ($code -eq 34) { [void]$builder.Append($slash); [void]$builder.Append([char]34); continue }
            if ($code -eq 92) { [void]$builder.Append($slash); [void]$builder.Append($slash); continue }
            if ($code -lt 0x20 -or $code -gt 0x7e) {
                if ($code -ge 0xd800 -and $code -le 0xdbff) {
                    if ($index + 1 -ge $Value.Length) { throw 'Canonical JSON does not allow an unpaired UTF-16 surrogate.' }
                    $next = [int][char]$Value[$index + 1]
                    if ($next -lt 0xdc00 -or $next -gt 0xdfff) { throw 'Canonical JSON does not allow an unpaired UTF-16 surrogate.' }
                    [void]$builder.Append($slash); [void]$builder.Append(('u{0:x4}' -f $code))
                    $index++
                    [void]$builder.Append($slash); [void]$builder.Append(('u{0:x4}' -f $next))
                    continue
                }
                if ($code -ge 0xdc00 -and $code -le 0xdfff) { throw 'Canonical JSON does not allow an unpaired UTF-16 surrogate.' }
                [void]$builder.Append($slash); [void]$builder.Append(('u{0:x4}' -f $code))
            }
            else { [void]$builder.Append($character) }
        }
        [void]$builder.Append([char]34)
    }

    function Write-JsonValue {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value) { [void]$builder.Append('null'); return }
        if ($Value -is [string] -or $Value -is [char]) { Write-JsonString ([string]$Value); return }
        if ($Value -is [bool]) { [void]$builder.Append($(if ($Value) { 'true' } else { 'false' })); return }
        if ($Value -is [sbyte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [System.Numerics.BigInteger]) {
            if ([System.Numerics.BigInteger]$Value -lt [System.Numerics.BigInteger]::Zero) { throw 'Canonical JSON does not allow negative integers.' }
            [void]$builder.Append($Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)); return
        }
        if ($Value -is [byte] -or $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64]) {
            [void]$builder.Append($Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)); return
        }
        if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) { throw 'Canonical JSON does not allow floating-point values.' }
        if ($Value -is [System.Collections.IDictionary]) {
            if ($Value -isnot [System.Collections.Specialized.OrderedDictionary]) { throw 'Canonical JSON requires ordered dictionaries.' }
            [void]$builder.Append('{'); $first = $true
            foreach ($entry in $Value.GetEnumerator()) {
                if (-not $first) { [void]$builder.Append(',') }; $first = $false
                Write-JsonString ([string]$entry.Key); [void]$builder.Append(':'); Write-JsonValue $entry.Value
            }
            [void]$builder.Append('}'); return
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            [void]$builder.Append('['); $first = $true
            foreach ($item in $Value) {
                if (-not $first) { [void]$builder.Append(',') }; $first = $false; Write-JsonValue $item
            }
            [void]$builder.Append(']'); return
        }
        if ($Value.GetType().FullName -ne 'System.Management.Automation.PSCustomObject') {
            throw "Canonical JSON does not support value type '$($Value.GetType().FullName)'."
        }
        $properties = @($Value.PSObject.Properties)
        [void]$builder.Append('{')
        for ($index = 0; $index -lt $properties.Count; $index++) {
            if ($index -gt 0) { [void]$builder.Append(',') }
            Write-JsonString $properties[$index].Name; [void]$builder.Append(':'); Write-JsonValue $properties[$index].Value
        }
        [void]$builder.Append('}')
    }
    Write-JsonValue $InputObject
    return $builder.ToString()
}
