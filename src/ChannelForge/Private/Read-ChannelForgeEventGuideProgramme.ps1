function Read-ChannelForgeEventGuideProgramme {
    # Reads the programs of the named guide channels from XMLTV text. Returns a hashtable:
    # guide id -> rows (Title, Start, Stop, Valid). Times are UTC datetimeoffset. A missing stop is
    # allowed (Stop is null, Valid stays true). A start or stop that cannot be read makes Valid false.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string[]]$GuideId
    )

    $wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]$GuideId, [System.StringComparer]::Ordinal)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $readTime = {
        param([string]$Value)
        $parsed = [datetimeoffset]::MinValue
        if ($Value -match '^(\d{14}) ([+-]\d{2})(\d{2})$' -and [datetimeoffset]::TryParseExact(('{0} {1}:{2}' -f $Matches[1], $Matches[2], $Matches[3]), 'yyyyMMddHHmmss zzz', $culture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed.ToUniversalTime() }
        return $null
    }
    $result = @{}
    foreach ($match in [regex]::Matches($Text, '<programme\b([^>]*)>(.*?)</programme>', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $attribute = @{}
        foreach ($pair in [regex]::Matches($match.Groups[1].Value, '(\w+)="([^"]*)"')) { $attribute[$pair.Groups[1].Value] = [System.Net.WebUtility]::HtmlDecode($pair.Groups[2].Value) }
        # The merged guide names a channel '<n>:<source id>|<n>:<raw id>'; the playlist tvg-id is the raw id.
        $channelId = [regex]::Replace([string]$attribute['channel'], '^\d+:[^|]*\|\d+:', '')
        if (-not $wanted.Contains($channelId)) { continue }
        $start = & $readTime ([string]$attribute['start'])
        $stop = & $readTime ([string]$attribute['stop'])
        $title = [regex]::Match($match.Groups[2].Value, '<title\b[^>]*>(.*?)</title>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $description = [regex]::Match($match.Groups[2].Value, '<desc\b[^>]*>(.*?)</desc>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if (-not $result.ContainsKey($channelId)) { $result[$channelId] = [System.Collections.Generic.List[object]]::new() }
        $result[$channelId].Add([pscustomobject]@{
                Title = $(if ($title.Success) { [System.Net.WebUtility]::HtmlDecode($title.Groups[1].Value) } else { '' })
                Description = $(if ($description.Success) { [System.Net.WebUtility]::HtmlDecode($description.Groups[1].Value) } else { '' })
                Start = $start; Stop = $stop
                Valid = ($null -ne $start -and ($attribute.ContainsKey('stop') -eq ($null -ne $stop)))
            })
    }
    return $result
}
