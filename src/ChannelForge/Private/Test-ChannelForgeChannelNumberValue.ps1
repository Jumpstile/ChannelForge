function Test-ChannelForgeChannelNumberValue {
    # True only for a whole number from 1 to 9999. Text, decimals and booleans are not numbers here.
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    return (($Value -is [int] -or $Value -is [long]) -and $Value -ge 1 -and $Value -le 9999)
}
