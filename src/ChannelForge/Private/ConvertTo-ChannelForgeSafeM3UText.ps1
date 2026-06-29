function ConvertTo-ChannelForgeSafeM3UText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    # M3U has no formal escaping standard, so a stray double quote or
    # embedded line break in untrusted provider text (M3U attributes are
    # external input - see Import-ChannelForgeM3UPlaylist) can corrupt the
    # generated file structure: a literal newline can make later lines look
    # like a new #EXTINF/stream-URL pair, and an unescaped " breaks whatever
    # comes after it in a quoted attribute. Used by
    # Export-ChannelForgeM3UPlaylist on every field it writes, quoted or not.
    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $safe = $Text -replace '[\r\n]+', ' '
    $safe = $safe -replace '"', "'"
    return $safe
}
