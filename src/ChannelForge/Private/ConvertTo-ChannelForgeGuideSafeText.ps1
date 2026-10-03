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
    $text = [regex]::Replace($text, '(?i)\b(?:[A-Z0-9]+_)*(?:password|passwd|secret|token|credential|api[_-]?key|access[_-]?key|client[_-]?secret)(?:_[A-Z0-9]+)*\s*[:=]\s*(?:"[^"]*"|''[^'']*''|[^\s,;]+)', '[redacted-sensitive]')
    $text = [regex]::Replace($text, '(?i)\bAuthorization\s*[:=]\s*(?:(?:Bearer|Basic)\s+)?(?:"[^"]*"|''[^'']*''|[^\s,;]+)', '[redacted-sensitive]')
    $text = [regex]::Replace($text, '(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*', '[redacted-sensitive]')
    $text = [regex]::Replace($text, '(?<![A-Za-z0-9])/(?:[^/\s]+/)+[^/\s]*', '[redacted-path]')
    $text = [regex]::Replace($text, '\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b', '[redacted-contact]')
    $text = [regex]::Replace($text, '(?<![A-Za-z0-9])[0-9a-f]{64}(?![A-Za-z0-9])', '[redacted-id]')
    $text = $text.Trim()
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}
