function ConvertTo-ChannelForgeGuideSafeText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [ValidateRange(1, 512)]
        [int]$MaximumLength = 256
    )

    if ($null -eq $Value) { return '' }

    $text = [string]$Value
    $text = [regex]::Replace($text, '[\u0000-\u001F\u007F]', ' ')
    $text = [regex]::Replace($text, '(?i)\b(?:https?|ftp)://[^\s<>"'']+', '[redacted-url]')
    $text = [regex]::Replace($text, '(?i)(?:[A-Z]:[\\/]|\\\\)[^\s<>"'']+', '[redacted-path]')
    $text = [regex]::Replace($text, '(?i)\b(?:password|passwd|secret|token|credential|api[_-]?key)\s*[:=]\s*[^\s,;]+', '[redacted-sensitive]')
    $text = [regex]::Replace($text, '(?<![A-Za-z0-9])[0-9a-f]{64}(?![A-Za-z0-9])', '[redacted-id]')
    $text = $text.Trim()
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}
