function Get-ChannelForgeGuidePatternHash {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return [Convert]::ToHexString($sha.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertTo-ChannelForgeGuidePatternSafeText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    $text = ConvertTo-ChannelForgeGuideSafeText -Value $Value -MaximumLength 512
    $text = [regex]::Replace($text, '(?i)\b(?:password|passwd|secret|token|credential|api[_-]?key)[-_]?[A-Za-z0-9]+\b', '[redacted-sensitive]')
    return $text
}

function New-ChannelForgeGuidePatternExample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Ordinal,

        [AllowEmptyString()]
        [string]$Text,

        [ValidateSet('DisplayName', 'TvgName', 'OriginalName')]
        [string]$InputField = 'DisplayName',

        [string]$SourceId = 'beginner-examples',
        [string]$SourceFamily = 'beginner-examples',
        [string]$EvidenceType = 'ProviderDisplayText',
        [ValidateSet('Authoritative', 'Independent', 'Mirror', 'Unknown')]
        [string]$SourceRelationship = 'Unknown',
        [string]$Group = '',
        [ValidateSet('Fight', 'PPV', 'TemporaryEvent', 'League', 'SingleTeam', 'StreamingEvent', 'Sports', 'Other', 'Unknown')]
        [string]$EventType = 'Unknown',
        [ValidateSet('Scheduled', 'Live', 'Postponed', 'Cancelled', 'Rescheduled', 'Delayed', 'Completed', 'Idle', 'Unknown')]
        [string]$EventStatus = 'Unknown',
        [string]$League = '',
        [string]$Sport = '',
        [string]$FreshnessState = 'Unknown',
        [string]$ConfidenceState = 'Unknown',
        [string]$EvidenceStartUtc = '',
        [string]$EvidenceEndUtc = '',
        [string]$SourceTimezone = '',
        [string]$ChannelReference = '',
        [string]$EvidenceTitle = '',
        [string]$EvidenceHomeParticipant = '',
        [string]$EvidenceAwayParticipant = '',
        [AllowNull()]
        [string[]]$EvidenceReasonCodes = @(),

        [AllowNull()]
        [object[]]$VolatileFacts = @()
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        $safeText = ''
    }
    else {
        $safeText = ConvertTo-ChannelForgeGuidePatternSafeText -Value $Text
    }

    $example = [GuidePatternExample]::new()
    $example.Ordinal = $Ordinal
    $example.InputField = $InputField
    $example.SourceId = ConvertTo-ChannelForgeGuidePatternSafeText -Value $SourceId
    $example.SourceFamily = ConvertTo-ChannelForgeGuidePatternSafeText -Value $SourceFamily
    $example.EvidenceType = ConvertTo-ChannelForgeGuidePatternSafeText -Value $EvidenceType
    $example.SourceRelationship = $SourceRelationship
    $example.Group = ConvertTo-ChannelForgeGuidePatternSafeText -Value $Group
    $example.EventType = $EventType
    $example.EventStatus = $EventStatus
    $example.League = ConvertTo-ChannelForgeGuidePatternSafeText -Value $League
    $example.Sport = ConvertTo-ChannelForgeGuidePatternSafeText -Value $Sport
    $example.FreshnessState = ConvertTo-ChannelForgeGuidePatternSafeText -Value $FreshnessState
    $example.ConfidenceState = ConvertTo-ChannelForgeGuidePatternSafeText -Value $ConfidenceState
    $example.EvidenceStartUtc = ConvertTo-ChannelForgeGuidePatternSafeText -Value $EvidenceStartUtc
    $example.EvidenceEndUtc = ConvertTo-ChannelForgeGuidePatternSafeText -Value $EvidenceEndUtc
    $example.SourceTimezone = ConvertTo-ChannelForgeGuidePatternSafeText -Value $SourceTimezone
    $example.ChannelReference = ConvertTo-ChannelForgeGuidePatternSafeText -Value $ChannelReference
    $example.EvidenceTitle = ConvertTo-ChannelForgeGuidePatternSafeText -Value $EvidenceTitle
    $example.EvidenceHomeParticipant = ConvertTo-ChannelForgeGuidePatternSafeText -Value $EvidenceHomeParticipant
    $example.EvidenceAwayParticipant = ConvertTo-ChannelForgeGuidePatternSafeText -Value $EvidenceAwayParticipant
    $example.EvidenceReasonCodes = @($EvidenceReasonCodes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ConvertTo-ChannelForgeGuidePatternSafeText -Value $_ } | Sort-Object -Unique)
    $example.VolatileFacts = @($VolatileFacts | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-ChannelForgeGuideVolatileFactRecord -InputObject $_ })
    $example.SafeText = $safeText
    $example.SafeFingerprint = Get-ChannelForgeGuidePatternHash -Text $safeText
    return $example
}

function Resolve-ChannelForgeGuidePatternTimezone {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Label,

        [AllowNull()]
        [System.Collections.IDictionary]$TimezoneMap
    )

    $normalizedLabel = if ([string]::IsNullOrWhiteSpace($Label)) { '' } else { $Label.Trim() }
    $mapping = $null
    if ($null -ne $TimezoneMap -and -not [string]::IsNullOrEmpty($normalizedLabel)) {
        foreach ($key in $TimezoneMap.Keys) {
            if ([string]$key -ieq $normalizedLabel) {
                $mapping = $TimezoneMap[$key]
                break
            }
        }
    }

    if ($null -eq $mapping -and $normalizedLabel -match '^(?i:UTC|GMT|Z)$') {
        $mapping = '+00:00'
    }

    if ($null -eq $mapping -and -not [string]::IsNullOrEmpty($normalizedLabel)) {
        $mapping = $normalizedLabel
    }
    if ($null -eq $mapping -or [string]::IsNullOrWhiteSpace([string]$mapping)) {
        return [pscustomobject][ordered]@{
            Label = $normalizedLabel
            Resolved = $false
            Display = ''
            Offset = $null
            TimeZone = $null
            ReasonCodes = @('AmbiguousTime')
        }
    }

    $mappingText = (ConvertTo-ChannelForgeGuidePatternSafeText -Value $mapping).Trim()
    if ($mappingText -match '^[+-][0-9]{2}:[0-9]{2}$') {
        $sign = if ($mappingText.StartsWith('-')) { -1 } else { 1 }
        $hours = [int]$mappingText.Substring(1, 2)
        $minutes = [int]$mappingText.Substring(4, 2)
        if ($hours -gt 14 -or $minutes -gt 59 -or ($hours -eq 14 -and $minutes -gt 0)) {
            return [pscustomobject][ordered]@{
                Label = $normalizedLabel
                Resolved = $false
                Display = ''
                Offset = $null
                TimeZone = $null
                ReasonCodes = @('AmbiguousTime')
            }
        }

        $offset = [TimeSpan]::FromMinutes($sign * (($hours * 60) + $minutes))
        return [pscustomobject][ordered]@{
            Label = $normalizedLabel
            Resolved = $true
            Display = $mappingText
            Offset = $offset
            TimeZone = $null
            ReasonCodes = @()
        }
    }

    try {
        $timeZone = [TimeZoneInfo]::FindSystemTimeZoneById($mappingText)
        return [pscustomobject][ordered]@{
            Label = $normalizedLabel
            Resolved = $true
            Display = $timeZone.Id
            Offset = $null
            TimeZone = $timeZone
            ReasonCodes = @()
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            Label = $normalizedLabel
            Resolved = $false
            Display = ''
            Offset = $null
            TimeZone = $null
            ReasonCodes = @('AmbiguousTime')
        }
    }
}

function Get-ChannelForgeGuidePatternDateParts {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$DateText,

        [ValidateSet('MonthFirst', 'DayFirst')]
        [string]$DateOrder = 'MonthFirst'
    )

    $text = if ($null -eq $DateText) { '' } else { $DateText.Trim().Trim(',') }
    $weekday = ''
    $weekdayMatch = [regex]::Match(
        $text,
        '^(?<weekday>Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b\s*',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($weekdayMatch.Success) {
        $weekday = $weekdayMatch.Groups['weekday'].Value
        $text = $text.Substring($weekdayMatch.Length).Trim().Trim(',')
    }
    $weekdayFormat = if ([string]::IsNullOrEmpty($weekday)) { '' } elseif ($weekday.Length -le 3) { 'EEE' } else { 'EEEE' }

    $monthNames = 'January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec'
    $monthNumbers = @{
        jan = 1; january = 1; feb = 2; february = 2; mar = 3; march = 3; apr = 4; april = 4
        may = 5; jun = 6; june = 6; jul = 7; july = 7; aug = 8; august = 8; sep = 9; sept = 9
        september = 9; oct = 10; october = 10; nov = 11; november = 11; dec = 12; december = 12
    }

    $month = 0
    $day = 0
    $year = 0
    $hasYear = $false
    $monthNameMatch = [regex]::Match(
        $text,
        "^(?:(?<day>[0-9]{1,2})\s+(?<month>$monthNames)|(?<month>$monthNames)\s+(?<day>[0-9]{1,2}))(?:\s*,?\s*(?<year>[0-9]{2,4}))?$",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($monthNameMatch.Success) {
        $monthName = $monthNameMatch.Groups['month'].Value.ToLowerInvariant()
        $month = $monthNumbers[$monthName]
        $day = [int]$monthNameMatch.Groups['day'].Value
        if ($monthNameMatch.Groups['year'].Success) {
            $year = [int]$monthNameMatch.Groups['year'].Value
            if ($year -lt 100) { $year += 2000 }
            $hasYear = $true
        }
    }
    else {
        $numericMatch = [regex]::Match($text, '^(?<first>[0-9]{1,2})(?<separator>[./-])(?<second>[0-9]{1,2})(?:[./-](?<year>[0-9]{2,4}))?$')
        if ($numericMatch.Success) {
            $first = [int]$numericMatch.Groups['first'].Value
            $second = [int]$numericMatch.Groups['second'].Value
            if ($DateOrder -eq 'MonthFirst') {
                $month = $first
                $day = $second
            }
            else {
                $day = $first
                $month = $second
            }
            if ($numericMatch.Groups['year'].Success) {
                $year = [int]$numericMatch.Groups['year'].Value
                if ($year -lt 100) { $year += 2000 }
                $hasYear = $true
            }
        }
    }

    if ($month -lt 1 -or $month -gt 12 -or $day -lt 1 -or $day -gt 31) {
        return [pscustomobject][ordered]@{
            Valid = $false
            HasYear = $hasYear
            Year = $year
            Month = $month
            Day = $day
            Weekday = $weekday
            WeekdayFormat = $weekdayFormat
            Format = ''
            ReasonCodes = @('InvalidDate')
        }
    }

    $format = if ($monthNameMatch.Success) {
        $dayToken = $monthNameMatch.Groups['day'].Value
        $monthToken = $monthNameMatch.Groups['month'].Value
        $dayFormat = if ($dayToken.Length -eq 1) { 'd' } else { 'dd' }
        $monthFormat = if ($monthToken.Length -le 4) { 'MMM' } else { 'MMMM' }
        $baseFormat = if ($monthNameMatch.Groups['day'].Index -lt $monthNameMatch.Groups['month'].Index) { "$dayFormat $monthFormat" } else { "$monthFormat $dayFormat" }
        if ($monthNameMatch.Groups['year'].Success) {
            $yearFormat = if ($monthNameMatch.Groups['year'].Value.Length -le 2) { 'yy' } else { 'yyyy' }
            $yearSeparator = if ($text -match ',') { ', ' } else { ' ' }
            '{0}{1}{2}' -f $baseFormat, $yearSeparator, $yearFormat
        }
        else {
            $baseFormat
        }
    }
    else {
        $firstFormat = if ($numericMatch.Groups['first'].Value.Length -eq 1) { if ($DateOrder -eq 'MonthFirst') { 'M' } else { 'd' } } else { if ($DateOrder -eq 'MonthFirst') { 'MM' } else { 'dd' } }
        $secondFormat = if ($numericMatch.Groups['second'].Value.Length -eq 1) { if ($DateOrder -eq 'MonthFirst') { 'd' } else { 'M' } } else { if ($DateOrder -eq 'MonthFirst') { 'dd' } else { 'MM' } }
        $separator = $numericMatch.Groups['separator'].Value
        $baseFormat = "$firstFormat$separator$secondFormat"
        if ($numericMatch.Groups['year'].Success) {
            $yearFormat = if ($numericMatch.Groups['year'].Value.Length -le 2) { 'yy' } else { 'yyyy' }
            '{0}{1}{2}' -f $baseFormat, $separator, $yearFormat
        }
        else {
            $baseFormat
        }
    }

    return [pscustomobject][ordered]@{
        Valid = $true
        HasYear = $hasYear
        Year = $year
        Month = $month
        Day = $day
        Weekday = $weekday
        WeekdayFormat = $weekdayFormat
        Format = $format
        ReasonCodes = @()
    }
}

function ConvertTo-ChannelForgeGuidePatternUtc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$LocalDateTime,

        [Parameter(Mandatory)]
        [object]$Timezone
    )

    $unspecified = [DateTime]::SpecifyKind($LocalDateTime, [DateTimeKind]::Unspecified)
    if ($null -ne $Timezone.TimeZone) {
        $utcDateTime = [TimeZoneInfo]::ConvertTimeToUtc($unspecified, $Timezone.TimeZone)
        return [datetimeoffset]::new($utcDateTime).ToUniversalTime()
    }

    return [datetimeoffset]::new($unspecified, $Timezone.Offset).ToUniversalTime()
}

function Get-ChannelForgeGuidePatternTimeClause {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Segment,

        [AllowNull()]
        [System.Collections.IDictionary]$TimezoneMap,

        [AllowEmptyString()]
        [string]$DefaultTimezone,

        [AllowNull()]
        [Nullable[datetimeoffset]]$ReferenceInstantUtc,

        [ValidateSet('MonthFirst', 'DayFirst')]
        [string]$DateOrder = 'MonthFirst'
    )

    $text = $Segment.Trim()
    $firstTokenMatch = [regex]::Match($text, '^(?<first>\S+)(?:\s+(?<rest>.*))?$')
    $label = ''
    $body = $text
    if ($firstTokenMatch.Success) {
        $first = $firstTokenMatch.Groups['first'].Value
        $rest = if ($firstTokenMatch.Groups['rest'].Success) { $firstTokenMatch.Groups['rest'].Value } else { '' }
        $looksLikeWeekday = $first -match '^(?i:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)$'
        $looksLikeMonth = $first -match '^(?i:January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)$'
        $looksLikeDate = $first -match '^[0-9]{1,2}[./-][0-9]{1,2}'
        $looksLikeTime = $first -match '^[0-9]{1,2}(?::[0-9]{2})?(?i:a\.?m\.?|p\.?m\.?)?$'
        if (-not $looksLikeWeekday -and -not $looksLikeMonth -and -not $looksLikeDate -and -not $looksLikeTime -and -not [string]::IsNullOrEmpty($rest)) {
            $label = $first
            $body = $rest
        }
    }
    if ([string]::IsNullOrEmpty($label)) { $label = $DefaultTimezone }

    $timeMatch = [regex]::Match($body, '(?<hour>[0-9]{1,2})(?::(?<minute>[0-9]{2}))?\s*(?<meridiem>a\.?m\.?|p\.?m\.?)?\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (-not $timeMatch.Success) {
        [void]$reasons.Add('MissingTime')
        return [pscustomobject][ordered]@{
            Label = $label
            DateText = $body.Trim()
            TimeText = ''
            DateParts = $null
            TimeFormat = ''
            DateFormat = ''
            WeekdayFormat = ''
            ResolvedTimezone = Resolve-ChannelForgeGuidePatternTimezone -Label $label -TimezoneMap $TimezoneMap
            StartUtc = ''
            LocalDate = ''
            HasDate = $false
            HasTime = $false
            HasTimezone = $false
            ReasonCodes = @($reasons)
        }
    }

    $trailing = $body.Substring($timeMatch.Index + $timeMatch.Length).Trim()
    if (-not [string]::IsNullOrEmpty($trailing)) { [void]$reasons.Add('AmbiguousTime') }
    $dateText = $body.Substring(0, $timeMatch.Index).Trim().Trim(',').Trim()
    $hour = [int]$timeMatch.Groups['hour'].Value
    $minute = if ($timeMatch.Groups['minute'].Success) { [int]$timeMatch.Groups['minute'].Value } else { 0 }
    $meridiem = if ($timeMatch.Groups['meridiem'].Success) { $timeMatch.Groups['meridiem'].Value.ToLowerInvariant().Replace('.', '') } else { '' }
    if ($minute -gt 59) { [void]$reasons.Add('InvalidTime') }
    if (-not [string]::IsNullOrEmpty($meridiem)) {
        if ($hour -lt 1 -or $hour -gt 12) { [void]$reasons.Add('InvalidTime') }
        elseif ($meridiem -eq 'pm' -and $hour -lt 12) { $hour += 12 }
        elseif ($meridiem -eq 'am' -and $hour -eq 12) { $hour = 0 }
    }
    elseif ($hour -gt 23) {
        [void]$reasons.Add('InvalidTime')
    }

    $dateParts = Get-ChannelForgeGuidePatternDateParts -DateText $dateText -DateOrder $DateOrder
    foreach ($reason in @($dateParts.ReasonCodes)) { if (-not $reasons.Contains([string]$reason)) { [void]$reasons.Add([string]$reason) } }
    if (-not $dateParts.Valid) { [void]$reasons.Add('MissingDate') }

    $timezone = Resolve-ChannelForgeGuidePatternTimezone -Label $label -TimezoneMap $TimezoneMap
    foreach ($reason in @($timezone.ReasonCodes)) { if (-not $reasons.Contains([string]$reason)) { [void]$reasons.Add([string]$reason) } }
    if (-not $timezone.Resolved) { [void]$reasons.Add('TimezoneUnresolved') }

    $startUtc = ''
    $localDate = ''
    if ($dateParts.Valid -and $reasons -notcontains 'InvalidTime' -and $timezone.Resolved) {
        $candidateYears = if ($dateParts.HasYear) {
            @($dateParts.Year)
        }
        elseif ($null -ne $ReferenceInstantUtc) {
            $referenceYear = $ReferenceInstantUtc.ToUniversalTime().Year
            @(
                ($referenceYear - 1)
                $referenceYear
                ($referenceYear + 1)
            )
        }
        else {
            @()
        }

        if ($candidateYears.Count -eq 0) {
            [void]$reasons.Add('ReferenceInstantRequired')
        }
        else {
            $utcCandidates = [System.Collections.Generic.List[object]]::new()
            foreach ($candidateYear in $candidateYears) {
                try {
                    $local = [datetime]::new($candidateYear, $dateParts.Month, $dateParts.Day, $hour, $minute, 0, [DateTimeKind]::Unspecified)
                    if (-not [string]::IsNullOrEmpty($dateParts.Weekday)) {
                        $weekdayMatches = $local.ToString('dddd', [Globalization.CultureInfo]::InvariantCulture) -like "$($dateParts.Weekday)*"
                        if (-not $weekdayMatches) { continue }
                    }
                    if ($null -ne $timezone.TimeZone) {
                        if ($timezone.TimeZone.IsInvalidTime($local)) {
                            if (-not $reasons.Contains('InvalidTime')) { [void]$reasons.Add('InvalidTime') }
                            continue
                        }
                        if ($timezone.TimeZone.IsAmbiguousTime($local)) {
                            if (-not $reasons.Contains('AmbiguousTime')) { [void]$reasons.Add('AmbiguousTime') }
                            continue
                        }
                    }
                    $utc = ConvertTo-ChannelForgeGuidePatternUtc -LocalDateTime $local -Timezone $timezone
                    $distance = if ($null -ne $ReferenceInstantUtc) {
                        [math]::Abs(($utc - $ReferenceInstantUtc.ToUniversalTime()).TotalSeconds)
                    }
                    else { 0 }
                    [void]$utcCandidates.Add([pscustomobject]@{ Utc = $utc; Local = $local; Distance = $distance })
                }
                catch {
                    continue
                }
            }

            if ($utcCandidates.Count -eq 0) {
                if (-not $reasons.Contains('InvalidTime') -and -not $reasons.Contains('AmbiguousTime')) {
                    [void]$reasons.Add('InvalidDate')
                }
            }
            else {
                $orderedCandidates = @($utcCandidates | Sort-Object Distance, @{ Expression = { $_.Utc.ToString('o') } })
                if (-not $dateParts.HasYear -and $orderedCandidates.Count -gt 1 -and $orderedCandidates[0].Distance -eq $orderedCandidates[1].Distance) {
                    [void]$reasons.Add('AmbiguousTime')
                }
                elseif (-not $dateParts.HasYear -and $orderedCandidates[0].Distance -gt (400 * 24 * 60 * 60)) {
                    [void]$reasons.Add('AmbiguousTime')
                }
                else {
                    $selected = $orderedCandidates[0]
                    $startUtc = $selected.Utc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
                    $localDate = $selected.Local.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                }
            }
        }
    }

    $hourFormat = if ($timeMatch.Groups['hour'].Value.Length -eq 1) {
        if ([string]::IsNullOrEmpty($meridiem)) { 'H' } else { 'h' }
    }
    elseif ([string]::IsNullOrEmpty($meridiem)) {
        'HH'
    }
    else {
        'hh'
    }
    $minuteFormat = if ($timeMatch.Groups['minute'].Success) { ':mm' } else { '' }
    $timeFormat = if ([string]::IsNullOrEmpty($meridiem)) { '{0}{1}' -f $hourFormat, $minuteFormat } elseif ($timeMatch.Value -match '\s+[aApP]') { '{0}{1} a' -f $hourFormat, $minuteFormat } else { '{0}{1}a' -f $hourFormat, $minuteFormat }
    return [pscustomobject][ordered]@{
        Label = $label
        DateText = $dateText
        TimeText = $timeMatch.Value.Trim()
        DateParts = $dateParts
        TimeFormat = $timeFormat
        DateFormat = $dateParts.Format
        WeekdayFormat = $dateParts.WeekdayFormat
        ResolvedTimezone = $timezone
        StartUtc = $startUtc
        LocalDate = $localDate
        HasDate = $dateParts.Valid
        HasTime = ($reasons -notcontains 'MissingTime' -and $reasons -notcontains 'InvalidTime')
        HasTimezone = $timezone.Resolved
        ReasonCodes = @($reasons | Sort-Object -Unique)
    }
}

function ConvertTo-ChannelForgeGuidePatternSample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [GuidePatternExample]$Example,

        [AllowNull()]
        [System.Collections.IDictionary]$TimezoneMap,

        [AllowEmptyString()]
        [string]$DefaultTimezone,

        [AllowNull()]
        [Nullable[datetimeoffset]]$ReferenceInstantUtc,

        [ValidateSet('MonthFirst', 'DayFirst')]
        [string]$DateOrder = 'MonthFirst'
    )

    $reasons = [System.Collections.Generic.List[string]]::new()
    foreach ($reason in @($Example.EvidenceReasonCodes)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$reason) -and -not $reasons.Contains([string]$reason)) { [void]$reasons.Add([string]$reason) }
    }
    if ([string]::IsNullOrWhiteSpace($Example.SafeText)) {
        [void]$reasons.Add('EvidenceMissing')
        return [pscustomobject][ordered]@{
            Example = $Example
            ChannelIdentifier = ''
            ChannelOrdinalText = ''
            ChannelOrdinal = -1
            Delimiter = ''
            EventTitle = ''
            TimeClauses = @()
            TimezoneLabels = @()
            CanonicalStartUtc = ''
            EventDate = ''
            EventDateText = ''
            EventTimeText = ''
            SourceTimezone = ''
            ChannelReference = $Example.ChannelReference
            HomeParticipant = ''
            AwayParticipant = ''
            EventFamily = 'Unknown'
            League = $Example.League
            EventStatus = $Example.EventStatus
            Sport = $Example.Sport
            StructuralSignature = 'empty'
            Matched = $false
            MatchState = 'Unresolved'
            HasDuplicateTimezoneRepresentation = $false
            TimezoneCrossCheck = 'NotAvailable'
            ReasonCodes = @($reasons)
        }
    }

    $segments = [regex]::Split($Example.SafeText, '\s*//\s*')
    $head = $segments[0].Trim()
    $ordinalMatch = [regex]::Match($head, '^(?<identifier>.+?)\s+(?<ordinal>[0-9]{1,4})(?<delimiter>\s*[:.\-])\s*(?<title>.+?)\s*$')
    $identifier = if ($ordinalMatch.Success) { $ordinalMatch.Groups['identifier'].Value.Trim() } else { $head }
    $ordinalText = if ($ordinalMatch.Success) { $ordinalMatch.Groups['ordinal'].Value } else { '' }
    $ordinal = if ($ordinalMatch.Success) { [int]$ordinalText } else { -1 }
    $delimiter = if ($ordinalMatch.Success) { $ordinalMatch.Groups['delimiter'].Value.Trim() } else { '' }
    $title = if ($ordinalMatch.Success) { $ordinalMatch.Groups['title'].Value.Trim() } else { $head }
    if (-not $ordinalMatch.Success -and $Example.EventType -eq 'SingleTeam') {
        $colonIndex = $head.IndexOf(':')
        if ($colonIndex -gt 0 -and $colonIndex -lt ($head.Length - 1)) {
            $identifier = $head.Substring(0, $colonIndex).Trim()
            $title = $head.Substring($colonIndex + 1).Trim()
        }
    }

    $clauses = [System.Collections.Generic.List[object]]::new()
    if ($segments.Count -gt 1) {
        for ($index = 1; $index -lt $segments.Count; $index++) {
            $clause = Get-ChannelForgeGuidePatternTimeClause `
                -Segment ([string]$segments[$index]) `
                -TimezoneMap $TimezoneMap `
                -DefaultTimezone $DefaultTimezone `
                -ReferenceInstantUtc $ReferenceInstantUtc `
                -DateOrder $DateOrder
            [void]$clauses.Add($clause)
            foreach ($reason in @($clause.ReasonCodes)) {
                if (-not $reasons.Contains([string]$reason)) { [void]$reasons.Add([string]$reason) }
            }
        }
    }

    $resolvedInstants = @($clauses | Where-Object { -not [string]::IsNullOrEmpty($_.StartUtc) } | Select-Object -ExpandProperty StartUtc -Unique)
    $crossCheck = 'NotAvailable'
    $canonicalStart = if ($resolvedInstants.Count -gt 0) { $resolvedInstants[0] } else { '' }
    if ($clauses.Count -gt 1) {
        if ($resolvedInstants.Count -eq 1 -and @($clauses | Where-Object { -not $_.HasTimezone }).Count -eq 0) {
            $crossCheck = 'Agrees'
            if (-not $reasons.Contains('EvidenceAgrees')) { [void]$reasons.Add('EvidenceAgrees') }
        }
        elseif ($resolvedInstants.Count -gt 1) {
            $crossCheck = 'Contradiction'
            $canonicalStart = ''
            if (-not $reasons.Contains('EvidenceContradicts')) { [void]$reasons.Add('EvidenceContradicts') }
        }
        else {
            $crossCheck = 'NotAvailable'
            if (-not $reasons.Contains('TimezoneCrossCheckUnavailable')) { [void]$reasons.Add('TimezoneCrossCheckUnavailable') }
        }
    }
    $evidenceStartUtc = ''
    if (-not [string]::IsNullOrWhiteSpace($Example.EvidenceStartUtc)) {
        try {
            $parsedEvidenceStart = [datetimeoffset]::Parse(
                $Example.EvidenceStartUtc,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
            $evidenceStartUtc = $parsedEvidenceStart.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            [void]$reasons.Add('InvalidDate')
        }
    }
    if (-not [string]::IsNullOrEmpty($evidenceStartUtc)) {
        if ([string]::IsNullOrEmpty($canonicalStart)) {
            $canonicalStart = $evidenceStartUtc
            if ($clauses.Count -eq 0) { $crossCheck = 'EvidenceOnly' }
        }
        elseif ($canonicalStart -ne $evidenceStartUtc) {
            $crossCheck = 'Contradiction'
            $canonicalStart = ''
            if (-not $reasons.Contains('EvidenceContradicts')) { [void]$reasons.Add('EvidenceContradicts') }
        }
        elseif (-not $reasons.Contains('EvidenceAgrees')) {
            [void]$reasons.Add('EvidenceAgrees')
        }
    }


    $primaryClause = @($clauses | Where-Object { -not [string]::IsNullOrEmpty($_.StartUtc) } | Select-Object -First 1)
    if ($primaryClause.Count -eq 0) { $primaryClause = @($clauses | Select-Object -First 1) }
    $eventDate = if ($primaryClause.Count -gt 0) { [string]$primaryClause[0].LocalDate } else { '' }
    if ([string]::IsNullOrEmpty($eventDate) -and -not [string]::IsNullOrEmpty($canonicalStart)) {
        try { $eventDate = ([datetimeoffset]::Parse($canonicalStart, [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { $eventDate = '' }
    }
    $eventDateText = if ($primaryClause.Count -gt 0) { [string]$primaryClause[0].DateText } else { '' }
    $eventTimeText = if ($primaryClause.Count -gt 0) { [string]$primaryClause[0].TimeText } else { '' }
    if ([string]::IsNullOrEmpty($eventDateText)) { $eventDateText = $eventDate }
    if ([string]::IsNullOrEmpty($eventTimeText) -and -not [string]::IsNullOrEmpty($canonicalStart)) {
        try { $eventTimeText = ([datetimeoffset]::Parse($canonicalStart, [Globalization.CultureInfo]::InvariantCulture)).ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture) } catch { $eventTimeText = '' }
    }
    $eventDayOfWeek = if ($primaryClause.Count -gt 0 -and $null -ne $primaryClause[0].DateParts) { [string]$primaryClause[0].DateParts.Weekday } else { '' }

    $homeParticipant = ''
    $awayParticipant = ''
    $participantMatch = [regex]::Match($title, '^(?<home>.+?)\s+(?:vs?\.?|at|@)\s+(?<away>.+?)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($participantMatch.Success) {
        $homeParticipant = $participantMatch.Groups['home'].Value.Trim()
        if ($homeParticipant.Contains(':')) { $homeParticipant = ($homeParticipant -split ':')[-1].Trim() }
        $awayParticipant = $participantMatch.Groups['away'].Value.Trim()
    }
    elseif ($Example.EventType -eq 'SingleTeam') {
        $homeParticipant = $title.Trim()
    }
    if ([string]::IsNullOrEmpty($homeParticipant) -and -not [string]::IsNullOrWhiteSpace($Example.EvidenceHomeParticipant)) { $homeParticipant = $Example.EvidenceHomeParticipant }
    if ([string]::IsNullOrEmpty($awayParticipant) -and -not [string]::IsNullOrWhiteSpace($Example.EvidenceAwayParticipant)) { $awayParticipant = $Example.EvidenceAwayParticipant }
    $outputTimezoneLabels = @($clauses | ForEach-Object { [string]$_.Label } | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Unique)
    if ($outputTimezoneLabels.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Example.SourceTimezone)) { $outputTimezoneLabels = @($Example.SourceTimezone) }

    $signatureLabels = @($clauses | ForEach-Object { ([string]$_.Label).ToLowerInvariant() }) -join ','
    $signature = @(
        ([string]$identifier).ToLowerInvariant(),
        [string](-not [string]::IsNullOrEmpty($ordinalText)),
        $delimiter,
        [string]$clauses.Count,
        $signatureLabels
    ) -join '|'
    $matched = -not [string]::IsNullOrWhiteSpace($title)
    $hasReviewReason = @($reasons | Where-Object { $_ -notin @('EvidenceAgrees', 'AcceptedKnowledge', 'MetadataOnly') }).Count -gt 0
    $matchState = if (-not $matched) { 'Unresolved' } elseif ($reasons -contains 'EvidenceContradicts') { 'Contradiction' } elseif ($hasReviewReason) { 'NeedsReview' } else { 'Matched' }

    return [pscustomobject][ordered]@{
        Example = $Example
        ChannelIdentifier = $identifier
        ChannelReference = $Example.ChannelReference
        ChannelOrdinalText = $ordinalText
        ChannelOrdinal = $ordinal
        Delimiter = $delimiter
        EventTitle = $title
        TimeClauses = @($clauses.ToArray())
        TimezoneLabels = @($outputTimezoneLabels)
        CanonicalStartUtc = $canonicalStart
        EventDate = $eventDate
        EventDateText = $eventDateText
        EventTimeText = $eventTimeText
        EventDayOfWeek = $eventDayOfWeek
        EventDayOfWeekFormat = if ($primaryClause.Count -gt 0 -and $null -ne $primaryClause[0].DateParts) { [string]$primaryClause[0].DateParts.WeekdayFormat } else { '' }
        HomeParticipant = $homeParticipant
        AwayParticipant = $awayParticipant
        EventFamily = $Example.EventType
        EventStatus = $Example.EventStatus
        League = $Example.League
        Sport = $Example.Sport
        SourceTimezone = @($outputTimezoneLabels) -join ','
        StructuralSignature = $signature
        Matched = $matched
        MatchState = $matchState
        HasDuplicateTimezoneRepresentation = $clauses.Count -gt 1
        TimezoneCrossCheck = $crossCheck
        ReasonCodes = @($reasons | Sort-Object -Unique)
    }
}

function Resolve-ChannelForgeGuidePatternFamily {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Samples,

        [AllowEmptyString()]
        [string]$ExplicitEventType = '',

        [AllowEmptyString()]
        [string]$ExplicitLeague = '',

        [AllowEmptyString()]
        [string]$ExplicitSport = ''
    )

    $reasons = [System.Collections.Generic.List[string]]::new()
    $metadataFamilies = @($Samples | ForEach-Object { [string]$_.Example.EventType } | Where-Object { -not [string]::IsNullOrEmpty($_) -and $_ -ne 'Unknown' } | Sort-Object -Unique)
    if (-not [string]::IsNullOrEmpty($ExplicitEventType) -and $ExplicitEventType -ne 'Unknown') { $metadataFamilies = @($ExplicitEventType) }
    if ($metadataFamilies.Count -gt 1) {
        [void]$reasons.Add('EventFamilyConflict')
        $family = 'Unknown'
    }
    elseif ($metadataFamilies.Count -eq 1) {
        $family = $metadataFamilies[0]
    }
    else {
        $combined = (@($Samples | ForEach-Object { "$($_.ChannelIdentifier) $($_.EventTitle) $($_.Example.Group) $($_.Example.League) $($_.Example.Sport)" }) -join ' ').ToLowerInvariant()
        if ($combined -match '\b(ppv|pay\s*per\s*view)\b') { $family = 'PPV' }
        elseif ($combined -match '(?<![A-Za-z0-9_])(espn\+|espn\s*plus|streaming\s*event|streaming)(?![A-Za-z0-9_])') { $family = 'StreamingEvent' }
        elseif ($combined -match '\b(temporary|temp(?:orary)?\s+(?:sports|event))\b') { $family = 'TemporaryEvent' }
        elseif ($combined -match '\b(single\s*team|team\s*channel)\b') { $family = 'SingleTeam' }
        elseif ($combined -match '\b(ufc|mma|fight|boxing|cage\s*fury)\b') { $family = 'Fight' }
        elseif ($combined -match '\b(mlb|nba|nfl|nhl|mls|league|sport|soccer|baseball|football|hockey|basketball|tennis)\b') { $family = 'League' }
        else { $family = 'Unknown' }
    }

    $league = if (-not [string]::IsNullOrWhiteSpace($ExplicitLeague)) { $ExplicitLeague.Trim() } else { '' }
    $sport = if (-not [string]::IsNullOrWhiteSpace($ExplicitSport)) { $ExplicitSport.Trim() } else { '' }
    $metadataLeagues = @($Samples | ForEach-Object { [string]$_.Example.League } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $metadataSports = @($Samples | ForEach-Object { [string]$_.Example.Sport } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($metadataLeagues.Count -gt 1) { [void]$reasons.Add('LeagueConflict') }
    if ($metadataSports.Count -gt 1) { [void]$reasons.Add('SportConflict') }
    if ([string]::IsNullOrEmpty($league) -and $metadataLeagues.Count -eq 1) { $league = $metadataLeagues[0] }
    if ([string]::IsNullOrEmpty($sport) -and $metadataSports.Count -eq 1) { $sport = $metadataSports[0] }

    $combinedFields = (@($Samples | ForEach-Object { "$($_.ChannelIdentifier) $($_.EventTitle) $($_.Example.Group) $($_.Example.League) $($_.Example.Sport)" }) -join ' ').ToLowerInvariant()
    $leagueMap = @(
        @{ Token = 'mlb'; League = 'MLB'; Sport = 'Baseball' }
        @{ Token = 'nba'; League = 'NBA'; Sport = 'Basketball' }
        @{ Token = 'nfl'; League = 'NFL'; Sport = 'Football' }
        @{ Token = 'nhl'; League = 'NHL'; Sport = 'Hockey' }
        @{ Token = 'mls'; League = 'MLS'; Sport = 'Soccer' }
        @{ Token = 'ufc'; League = 'UFC'; Sport = 'MMA' }
        @{ Token = 'mma'; League = 'MMA'; Sport = 'MMA' }
    )
    if ([string]::IsNullOrEmpty($league) -or [string]::IsNullOrEmpty($sport)) {
        foreach ($entry in $leagueMap) {
            if ($combinedFields -match "\b$($entry.Token)\b") {
                if ([string]::IsNullOrEmpty($league)) { $league = $entry.League }
                if ([string]::IsNullOrEmpty($sport)) { $sport = $entry.Sport }
                break
            }
        }
    }

    return [pscustomobject][ordered]@{
        EventFamily = $family
        League = $league
        Sport = $sport
        ReasonCodes = @($reasons | Sort-Object -Unique)
    }
}
function Get-ChannelForgeGuidePatternCrossSourceAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Samples
    )

    $sourceIds = @($Samples | ForEach-Object { $_.Example.SourceId } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $mirrorIds = @($Samples | Where-Object { $_.Example.SourceRelationship -eq 'Mirror' } | ForEach-Object { $_.Example.SourceId } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $independentIds = @($Samples | Where-Object { $_.Example.SourceRelationship -in @('Authoritative', 'Independent') } | ForEach-Object { $_.Example.SourceId } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $groups = @($Samples | ForEach-Object {
        $key = if (-not [string]::IsNullOrWhiteSpace($_.Example.ChannelReference)) { $_.Example.ChannelReference } else { $_.Example.SafeFingerprint }
        [pscustomobject]@{ Key = $key; Sample = $_ }
    } | Group-Object Key)
    $comparisons = [System.Collections.Generic.List[object]]::new()
    foreach ($group in $groups) {
        $independent = @($group.Group | Where-Object { $_.Sample.Example.SourceRelationship -in @('Authoritative', 'Independent') } | ForEach-Object { $_.Sample.Example.SourceId } | Sort-Object -Unique)
        if ($independent.Count -lt 2) { continue }
        $starts = @($group.Group | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_.Sample.Example.EvidenceStartUtc)) { $_.Sample.Example.EvidenceStartUtc } else { $_.Sample.CanonicalStartUtc }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $missing = @($group.Group | Where-Object {
            [string]::IsNullOrWhiteSpace($_.Sample.Example.EvidenceStartUtc) -and [string]::IsNullOrWhiteSpace($_.Sample.CanonicalStartUtc)
        }).Count -gt 0
        $comparisonState = if ($starts.Count -gt 1) { 'Contradiction' } elseif ($missing) { 'Missing' } else { 'Agreement' }
        [void]$comparisons.Add([ordered]@{
            KeyFingerprint = Get-ChannelForgeGuidePatternHash -Text ([string]$group.Name)
            SourceIds = $independent
            State = $comparisonState
        })
    }

    $state = if (@($comparisons | Where-Object { $_.State -eq 'Contradiction' }).Count -gt 0) { 'Contradiction' }
    elseif (@($comparisons | Where-Object { $_.State -eq 'Missing' }).Count -gt 0) { 'Missing' }
    elseif (@($comparisons | Where-Object { $_.State -eq 'Agreement' }).Count -gt 0) { 'Agreement' }
    elseif ($mirrorIds.Count -gt 0 -and $independentIds.Count -lt 2) { 'MirrorOnly' }
    elseif ($sourceIds.Count -gt 1) { 'NotComparable' }
    elseif ($sourceIds.Count -eq 1) { 'SingleSource' }
    else { 'NotAvailable' }
    return [pscustomobject][ordered]@{
        State = $state
        DistinctSourceCount = $sourceIds.Count
        IndependentSourceIds = $independentIds
        MirrorSourceIds = $mirrorIds
        Comparisons = @($comparisons.ToArray())
    }
}

function Get-ChannelForgeGuidePatternFieldCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FieldName,

        [Parameter(Mandatory)]
        [string]$ExtractionKind,

        [Parameter(Mandatory)]
        [bool]$Required,

        [Parameter(Mandatory)]
        [object[]]$Samples,

        [AllowNull()]
        [object[]]$Values = @(),

        [AllowEmptyString()]
        [string]$Format = '',

        [AllowEmptyString()]
        [string]$TimezoneLabel = '',

        [string[]]$ExtraReasons = @()
    )

    $exampleCount = $Samples.Count
    $observed = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $observedCount = $observed.Count
    $score = if ($exampleCount -eq 0) { 0 } else { [math]::Floor((100 * $observedCount) / $exampleCount) }
    $reasons = [System.Collections.Generic.List[string]]::new()
    foreach ($reason in $ExtraReasons) { if (-not $reasons.Contains($reason)) { [void]$reasons.Add($reason) } }
    if ($Required -and $observedCount -lt $exampleCount) { if (-not $reasons.Contains('EvidenceMissing')) { [void]$reasons.Add('EvidenceMissing') } }
    $state = if ($score -ge 90 -and $reasons.Count -eq 0) { 'Confirmed' } elseif ($score -ge 70) { 'SafeCandidate' } else { 'NeedsReview' }
    $ordinals = @($Samples | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Value) } | ForEach-Object { [string]$_.Sample.Example.Ordinal })

    $field = [GuidePatternFieldCandidate]::new()
    $field.FieldName = $FieldName
    $field.ExtractionKind = $ExtractionKind
    $field.Required = $Required
    $field.ObservedCount = $observedCount
    $field.ExampleCount = $exampleCount
    $field.ConfidenceScore = [int]$score
    $field.ConfidenceState = $state
    $field.Format = $Format
    $field.TimezoneLabel = $TimezoneLabel
    $field.ExampleOrdinals = @($ordinals | Sort-Object -Unique)
    $field.ReasonCodes = @($reasons | Sort-Object -Unique)
    $field.Provenance = @($Samples | ForEach-Object {
        [ordered]@{
            ExampleOrdinal = $_.Sample.Example.Ordinal
            SourceId = $_.Sample.Example.SourceId
            SourceFamily = $_.Sample.Example.SourceFamily
            EvidenceType = $_.Sample.Example.EvidenceType
            SourceRelationship = $_.Sample.Example.SourceRelationship
            Fingerprint = $_.Sample.Example.SafeFingerprint
            Group = $_.Sample.Example.Group
            ChannelReference = $_.Sample.Example.ChannelReference
            FreshnessState = $_.Sample.Example.FreshnessState
            ConfidenceState = $_.Sample.Example.ConfidenceState
            EvidenceStartUtc = $_.Sample.Example.EvidenceStartUtc
            EvidenceEndUtc = $_.Sample.Example.EvidenceEndUtc
            SourceTimezone = $_.Sample.Example.SourceTimezone
            ReasonCodes = @($_.Sample.ReasonCodes)
        }
    })
    return $field
}

function Invoke-ChannelForgeGuidePatternAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [GuidePatternExample[]]$Examples,

        [AllowNull()]
        [System.Collections.IDictionary]$TimezoneMap,

        [AllowEmptyString()]
        [string]$DefaultTimezone,

        [AllowNull()]
        [Nullable[datetimeoffset]]$ReferenceInstantUtc,

        [ValidateSet('MonthFirst', 'DayFirst')]
        [string]$DateOrder = 'MonthFirst',

        [ValidateRange(2, 50)]
        [int]$MinimumExamples = 3,

        [AllowEmptyString()]
        [string]$ExplicitEventType = '',

        [AllowEmptyString()]
        [string]$ExplicitLeague = '',

        [AllowEmptyString()]
        [string]$ExplicitSport = '',

        [AllowEmptyString()]
        [string]$ScopeGroup = '',

        [AllowNull()]
        [object]$ExistingRule
    )

    $orderedExamples = @($Examples | Sort-Object SafeFingerprint, SourceId, SourceFamily, EvidenceType, EvidenceReasonCodes, SourceRelationship, Group, ChannelReference, EventType, EventStatus, League, Sport, SourceTimezone, EvidenceStartUtc, EvidenceEndUtc, EvidenceTitle, EvidenceHomeParticipant, EvidenceAwayParticipant, InputField, Ordinal)
    for ($index = 0; $index -lt $orderedExamples.Count; $index++) {
        $orderedExamples[$index].Ordinal = $index + 1
    }
    $sampleList = [System.Collections.Generic.List[object]]::new()
    foreach ($example in $orderedExamples) {
        [void]$sampleList.Add((ConvertTo-ChannelForgeGuidePatternSample `
                    -Example $example `
                    -TimezoneMap $TimezoneMap `
                    -DefaultTimezone $DefaultTimezone `
                    -ReferenceInstantUtc $ReferenceInstantUtc `
                    -DateOrder $DateOrder))
    }
    $samples = @($sampleList.ToArray())
    $allReasons = [System.Collections.Generic.List[string]]::new()
    foreach ($sample in $samples) {
        foreach ($reason in @($sample.ReasonCodes)) { if (-not $allReasons.Contains([string]$reason)) { [void]$allReasons.Add([string]$reason) } }
    }

    $family = Resolve-ChannelForgeGuidePatternFamily `
        -Samples $samples `
        -ExplicitEventType $ExplicitEventType `
        -ExplicitLeague $ExplicitLeague `
        -ExplicitSport $ExplicitSport
    foreach ($reason in @($family.ReasonCodes)) { if (-not $allReasons.Contains([string]$reason)) { [void]$allReasons.Add([string]$reason) } }
    $crossSourceAssessment = Get-ChannelForgeGuidePatternCrossSourceAssessment -Samples $samples
    if ($crossSourceAssessment.State -eq 'Contradiction' -and -not $allReasons.Contains('EvidenceContradicts')) { [void]$allReasons.Add('EvidenceContradicts') }
    if ($crossSourceAssessment.State -eq 'Missing' -and -not $allReasons.Contains('EvidenceMissing')) { [void]$allReasons.Add('EvidenceMissing') }
    if ($crossSourceAssessment.State -eq 'MirrorOnly' -and -not $allReasons.Contains('MirrorNotIndependent')) { [void]$allReasons.Add('MirrorNotIndependent') }
    if (@($samples | Where-Object { $_.Example.ConfidenceState -eq 'Contradiction' }).Count -gt 0 -and -not $allReasons.Contains('EvidenceContradicts')) { [void]$allReasons.Add('EvidenceContradicts') }
    if (@($samples | Where-Object { $_.Example.ConfidenceState -eq 'NeedsReview' }).Count -gt 0 -and -not $allReasons.Contains('SourceNeedsReview')) { [void]$allReasons.Add('SourceNeedsReview') }

    $majoritySignature = @($samples | Group-Object StructuralSignature | Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } | Select-Object -First 1).Name
    $outliers = @($samples | Where-Object { $_.StructuralSignature -ne $majoritySignature })
    if ($outliers.Count -gt 0) {
        if (-not $allReasons.Contains('PatternDrift')) { [void]$allReasons.Add('PatternDrift') }
        foreach ($outlier in $outliers) {
            if (-not $allReasons.Contains('InconsistentExamples')) { [void]$allReasons.Add('InconsistentExamples') }
        }
    }

    $commonIdentifiers = @($samples | ForEach-Object { $_.ChannelIdentifier } | Sort-Object -Unique)
    $commonIdentifier = if ($commonIdentifiers.Count -eq 1) { $commonIdentifiers[0] } else { '' }
    $commonDelimiters = @($samples | ForEach-Object { $_.Delimiter } | Sort-Object -Unique)
    $commonDelimiter = if ($commonDelimiters.Count -eq 1) { $commonDelimiters[0] } else { '' }
    $timezoneLabels = @($samples | ForEach-Object { $_.TimezoneLabels } | Sort-Object -Unique)
    $timeFormats = @($samples | ForEach-Object { $_.TimeClauses | ForEach-Object { $_.TimeFormat } } | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Unique)
    $dateFormats = @($samples | ForEach-Object { $_.TimeClauses | ForEach-Object { $_.DateFormat } } | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Unique)
    $weekdayFormats = @($samples | ForEach-Object { $_.TimeClauses | ForEach-Object { $_.WeekdayFormat } } | Where-Object { -not [string]::IsNullOrEmpty($_) } | Sort-Object -Unique)
    $observedTimezones = [ordered]@{}
    foreach ($label in $timezoneLabels) {
        $mapping = Resolve-ChannelForgeGuidePatternTimezone -Label $label -TimezoneMap $TimezoneMap
        $observedTimezones[$label] = if ($mapping.Resolved) { $mapping.Display } else { '' }
    }

    $scopeSourceFamilies = @($samples | ForEach-Object { $_.Example.SourceFamily } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $scopeSourceIds = @($samples | ForEach-Object { $_.Example.SourceId } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $scopeGroups = @($samples | ForEach-Object { $_.Example.Group } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $scope = [ordered]@{
        SourceId = if ($scopeSourceIds.Count -eq 1) { $scopeSourceIds[0] } else { '' }
        SourceFamily = if ($scopeSourceFamilies.Count -eq 1) { $scopeSourceFamilies[0] } else { '' }
        Group = if (-not [string]::IsNullOrWhiteSpace($ScopeGroup)) { ConvertTo-ChannelForgeGuidePatternSafeText -Value $ScopeGroup } elseif ($scopeGroups.Count -eq 1) { $scopeGroups[0] } else { '' }
        InputField = if ($samples.Count -gt 0) { $samples[0].Example.InputField } else { 'DisplayName' }
        EventFamily = $family.EventFamily
        League = $family.League
        Sport = $family.Sport
    }

    $grammarSegments = [System.Collections.Generic.List[object]]::new()
    if (-not [string]::IsNullOrEmpty($commonIdentifier)) {
        [void]$grammarSegments.Add([ordered]@{ Kind = 'StableLiteral'; Name = 'ChannelIdentifier'; Value = $commonIdentifier })
    }
    if (@($samples | Where-Object { -not [string]::IsNullOrEmpty($_.ChannelOrdinalText) }).Count -eq $samples.Count) {
        $width = @($samples | ForEach-Object { $_.ChannelOrdinalText.Length } | Sort-Object -Unique)
        [void]$grammarSegments.Add([ordered]@{ Kind = 'Field'; Name = 'ChannelOrdinal'; Extractor = 'LeadingOrdinal'; Width = if ($width.Count -eq 1) { $width[0] } else { 0 } })
        [void]$grammarSegments.Add([ordered]@{ Kind = 'StableLiteral'; Name = 'ChannelDelimiter'; Value = $commonDelimiter })
    }
    [void]$grammarSegments.Add([ordered]@{ Kind = 'Field'; Name = 'EventTitle'; Extractor = 'RemainingHeadBeforeTimezoneSeparator'; PreservePunctuation = $true })
    if ($timezoneLabels.Count -gt 0) {
        [void]$grammarSegments.Add([ordered]@{ Kind = 'Field'; Name = 'EventDateTime'; Extractor = 'TimezoneClause'; Labels = @($timezoneLabels); DateOrder = $DateOrder })
    }
    $grammar = [ordered]@{
        Version = 1
        InputField = $scope.InputField
        Segments = @($grammarSegments.ToArray())
        WeekdayFormats = @($weekdayFormats)
        DateOrder = $DateOrder
        TimeFormats = @($timeFormats)
        DateFormats = @($dateFormats)
        TimezoneLabels = @($timezoneLabels)
        Separator = if ($timezoneLabels.Count -gt 0) { '//' } else { '' }
    }

    $fieldCandidates = [System.Collections.Generic.List[object]]::new()
    $identifierValues = @($samples | ForEach-Object { $_.ChannelIdentifier })
    $ordinalValues = @($samples | ForEach-Object { $_.ChannelOrdinalText })
    $titleValues = @($samples | ForEach-Object { $_.EventTitle })
    $dateValues = @($samples | ForEach-Object {
        $value = @($_.TimeClauses | ForEach-Object { $_.DateText } | Select-Object -First 1)
        if ($value.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$value[0])) { $value = $_.EventDate }
        [string]$value[0]
    })
    $weekdayValues = @($samples | ForEach-Object { $_.TimeClauses | ForEach-Object { $_.DateParts.Weekday } | Where-Object { -not [string]::IsNullOrEmpty($_) } | Select-Object -First 1 })
    $timeValues = @($samples | ForEach-Object {
        $value = @($_.TimeClauses | ForEach-Object { $_.TimeText } | Select-Object -First 1)
        if ($value.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$value[0])) { $value = $_.CanonicalStartUtc }
        [string]$value[0]
    })
    $timezoneValues = @($samples | ForEach-Object { $_.TimezoneLabels -join ',' })
    $homeValues = @($samples | ForEach-Object { $_.HomeParticipant })
    $awayValues = @($samples | ForEach-Object { $_.AwayParticipant })
    $leagueValues = @($samples | ForEach-Object { if (-not [string]::IsNullOrEmpty($_.Example.League)) { $_.Example.League } else { $family.League } })
    $sportValues = @($samples | ForEach-Object { if (-not [string]::IsNullOrEmpty($_.Example.Sport)) { $_.Example.Sport } else { $family.Sport } })
    $familyValues = @($samples | ForEach-Object { if ($family.EventFamily -eq 'Unknown') { '' } else { $family.EventFamily } })
    $statusValues = @($samples | ForEach-Object { $_.EventStatus })
    $fieldDefinitions = @(
        @{ Name = 'ChannelIdentifier'; Kind = 'StableLiteralPrefix'; Required = $true; Values = $identifierValues; Format = ''; Timezone = ''; Reasons = @() }
        @{ Name = 'EventDayOfWeek'; Kind = 'WeekdayToken'; Required = $false; Values = $weekdayValues; Format = if ($weekdayFormats.Count -eq 1) { $weekdayFormats[0] } else { '' }; Timezone = ''; Reasons = @() }
        @{ Name = 'ChannelOrdinal'; Kind = 'LeadingOrdinal'; Required = $false; Values = $ordinalValues; Format = 'integer'; Timezone = ''; Reasons = @() }
        @{ Name = 'EventTitle'; Kind = 'RemainingHeadBeforeTimezoneSeparator'; Required = $true; Values = $titleValues; Format = ''; Timezone = ''; Reasons = @() }
        @{ Name = 'EventDate'; Kind = 'DateToken'; Required = $true; Values = $dateValues; Format = if ($dateFormats.Count -eq 1) { $dateFormats[0] } else { '' }; Timezone = ''; Reasons = @() }
        @{ Name = 'EventTime'; Kind = 'TimeToken'; Required = $true; Values = $timeValues; Format = if ($timeFormats.Count -eq 1) { $timeFormats[0] } else { '' }; Timezone = ''; Reasons = @() }
        @{ Name = 'EventTimezone'; Kind = 'TimezoneLabel'; Required = $true; Values = $timezoneValues; Format = ''; Timezone = ($timezoneLabels -join ','); Reasons = @() }
        @{ Name = 'HomeParticipant'; Kind = 'ParticipantSeparator'; Required = $false; Values = $homeValues; Format = ''; Timezone = ''; Reasons = @() }
        @{ Name = 'AwayParticipant'; Kind = 'ParticipantSeparator'; Required = $false; Values = $awayValues; Format = ''; Timezone = ''; Reasons = @() }
        @{ Name = 'League'; Kind = 'StructuredMetadataOrVocabulary'; Required = $false; Values = $leagueValues; Format = ''; Timezone = ''; Reasons = @($family.ReasonCodes | Where-Object { $_ -eq 'LeagueConflict' }) }
        @{ Name = 'Sport'; Kind = 'StructuredMetadataOrVocabulary'; Required = $false; Values = $sportValues; Format = ''; Timezone = ''; Reasons = @($family.ReasonCodes | Where-Object { $_ -eq 'SportConflict' }) }
        @{ Name = 'EventFamily'; Kind = 'StructuredMetadataOrVocabulary'; Required = $true; Values = $familyValues; Format = ''; Timezone = ''; Reasons = @($family.ReasonCodes) }
        @{ Name = 'EventStatus'; Kind = 'StructuredMetadata'; Required = $false; Values = $statusValues; Format = ''; Timezone = ''; Reasons = @() }
    )
    foreach ($definition in $fieldDefinitions) {
        $sampleValueObjects = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $samples.Count; $index++) {
            [void]$sampleValueObjects.Add([pscustomobject]@{ Value = [string]$definition.Values[$index]; Sample = $samples[$index] })
        }
        $field = Get-ChannelForgeGuidePatternFieldCandidate `
            -FieldName $definition.Name `
            -ExtractionKind $definition.Kind `
            -Required $definition.Required `
            -Samples $sampleValueObjects `
            -Values $definition.Values `
            -Format $definition.Format `
            -TimezoneLabel $definition.Timezone `
            -ExtraReasons $definition.Reasons
        [void]$fieldCandidates.Add($field)
    }
    foreach ($field in @($fieldCandidates)) {
        foreach ($reason in @($field.ReasonCodes)) {
            if (-not $allReasons.Contains([string]$reason)) { [void]$allReasons.Add([string]$reason) }
        }
    }

    $matchedCount = @($samples | Where-Object { $_.Matched }).Count
    $coverageScore = if ($samples.Count -eq 0) { 0 } else { [math]::Floor((40 * $matchedCount) / $samples.Count) }
    $criticalPresent = @(
        (@($samples | Where-Object { -not [string]::IsNullOrWhiteSpace($_.ChannelIdentifier) }).Count -eq $samples.Count),
        (@($samples | Where-Object { -not [string]::IsNullOrWhiteSpace($_.EventTitle) }).Count -eq $samples.Count),
        (@($samples | Where-Object { @($_.TimeClauses | Where-Object { $_.HasTime }).Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($_.Example.EvidenceStartUtc) }).Count -eq $samples.Count)
    )
    $criticalScore = [math]::Floor((30 * (@($criticalPresent | Where-Object { $_ }).Count)) / 3)
    $structureScore = if ($samples.Count -eq 0) { 0 } else { [math]::Floor((20 * ($samples.Count - $outliers.Count)) / $samples.Count) }
    $crossCheckSamples = @($samples | Where-Object { $_.HasDuplicateTimezoneRepresentation })
    $crossCheckScore = if ($crossCheckSamples.Count -eq 0) { 5 } elseif (@($crossCheckSamples | Where-Object { $_.TimezoneCrossCheck -eq 'Agrees' }).Count -eq $crossCheckSamples.Count) { 10 } else { 0 }
    $confidenceScore = [int]($coverageScore + $criticalScore + $structureScore + $crossCheckScore)

    $state = 'Unresolved'
    if ($samples.Count -lt $MinimumExamples) {
        [void]$allReasons.Add('InsufficientExamples')
        $state = 'Unresolved'
    }
    elseif ($allReasons -contains 'EvidenceContradicts' -or $allReasons -contains 'EventFamilyConflict') {
        $state = 'Contradiction'
    }
    elseif (@($samples | Where-Object { $_.Example.FreshnessState -eq 'Unavailable' -or $_.Example.ConfidenceState -eq 'SourceUnavailable' }).Count -gt 0) {
        $state = 'SourceUnavailable'
    }
    elseif (@($samples | Where-Object { $_.Example.FreshnessState -eq 'Stale' -or $_.Example.ConfidenceState -eq 'StaleSource' }).Count -gt 0) {
        $state = 'StaleSource'
    }
    elseif ($allReasons -contains 'EvidenceMissing' -or $allReasons -contains 'SourceNeedsReview' -or $allReasons -contains 'ConfidenceBelowThreshold' -or $allReasons -contains 'MirrorNotIndependent' -or $allReasons -contains 'MissingTime' -or $allReasons -contains 'MissingDate' -or $allReasons -contains 'InvalidDate' -or $allReasons -contains 'InvalidTime' -or $allReasons -contains 'TimezoneUnresolved' -or $allReasons -contains 'ReferenceInstantRequired' -or $allReasons -contains 'AmbiguousTime' -or $allReasons -contains 'AmbiguousTitle' -or $allReasons -contains 'NoEventData' -or $allReasons -contains 'ScheduleChanged' -or $allReasons -contains 'Postponed' -or $allReasons -contains 'Cancelled' -or $allReasons -contains 'Rescheduled' -or $allReasons -contains 'SourceStale' -or $allReasons -contains 'SourceUnavailable' -or $allReasons -contains 'StaleSource' -or $allReasons -contains 'TimezoneCrossCheckUnavailable' -or $allReasons -contains 'LeagueConflict' -or $allReasons -contains 'SportConflict' -or $outliers.Count -gt 0 -or $family.EventFamily -eq 'Unknown') {
        $state = 'NeedsReview'
    }
    elseif ($confidenceScore -ge 90) {
        $state = 'Confirmed'
    }
    elseif ($confidenceScore -ge 70) {
        $state = 'SafeCandidate'
    }
    else {
        $state = 'NeedsReview'
    }
    if ($state -eq 'SourceUnavailable' -and -not $allReasons.Contains('SourceUnavailable')) { [void]$allReasons.Add('SourceUnavailable') }
    if ($state -eq 'StaleSource' -and -not $allReasons.Contains('StaleSource')) { [void]$allReasons.Add('StaleSource') }

    if ($state -eq 'NeedsReview' -and -not $allReasons.Contains('ConfidenceBelowThreshold') -and $confidenceScore -lt 70) { [void]$allReasons.Add('ConfidenceBelowThreshold') }
    if ($state -eq 'NeedsReview' -and $allReasons -contains 'TimezoneCrossCheckUnavailable' -and -not $allReasons.Contains('AmbiguousTime')) { [void]$allReasons.Add('AmbiguousTime') }

    $driftStatus = if ($outliers.Count -gt 0) { 'Detected' } else { 'NotEvaluated' }
    $existingRuleId = ''
    $existingRuleVersion = 0
    $invalidExistingRule = $false
    if ($null -ne $ExistingRule) {
        $candidateExistingRuleId = if ($null -ne $ExistingRule.PSObject.Properties['RuleId']) { [string]$ExistingRule.RuleId } else { '' }
        if ([string]::IsNullOrEmpty($candidateExistingRuleId)) {
            $invalidExistingRule = $false
        }
        elseif ($candidateExistingRuleId -match '^pattern-[0-9a-f]{64}$') {
            $existingRuleId = $candidateExistingRuleId
            if ($null -ne $ExistingRule.PSObject.Properties['RuleVersion']) { $existingRuleVersion = [int]$ExistingRule.RuleVersion }
        }
        else {
            $invalidExistingRule = $true
        }
    }

    $timezoneInterpretation = [ordered]@{
        Labels = @($timezoneLabels)
        Mappings = [pscustomobject]$observedTimezones
        CrossCheck = if ($crossCheckSamples.Count -eq 0) { 'NotAvailable' } elseif (@($crossCheckSamples | Where-Object { $_.TimezoneCrossCheck -eq 'Contradiction' }).Count -gt 0) { 'Contradiction' } elseif (@($crossCheckSamples | Where-Object { $_.TimezoneCrossCheck -eq 'Agrees' }).Count -eq $crossCheckSamples.Count) { 'Agrees' } else { 'NeedsReview' }
        ReferenceInstantUtc = if ($null -ne $ReferenceInstantUtc) { $ReferenceInstantUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) } else { '' }
    }
    $ruleIdentity = [ordered]@{
        Scope = $scope
        Grammar = $grammar
        TimezoneInterpretation = [ordered]@{
            Labels = @($timezoneInterpretation.Labels)
            Mappings = $timezoneInterpretation.Mappings
            CrossCheck = $timezoneInterpretation.CrossCheck
        }
        FieldNames = @($fieldCandidates | ForEach-Object { $_.FieldName })
    }
    $ruleJson = $ruleIdentity | ConvertTo-Json -Depth 20 -Compress
    $ruleId = 'pattern-' + (Get-ChannelForgeGuidePatternHash -Text $ruleJson)
    if ($null -ne $ExistingRule -and -not [string]::IsNullOrEmpty($existingRuleId) -and $existingRuleId -ne $ruleId) {
        $driftStatus = 'Detected'
        if (-not $allReasons.Contains('PatternDrift')) { [void]$allReasons.Add('PatternDrift') }
    }
    if ($invalidExistingRule) {
        $driftStatus = 'Detected'
        if (-not $allReasons.Contains('InvalidBaselineRule')) { [void]$allReasons.Add('InvalidBaselineRule') }
    }
    if ($driftStatus -eq 'Detected' -and $state -in @('Confirmed', 'SafeCandidate')) { $state = 'NeedsReview' }
    $driftComparison = [ordered]@{
        BaselineRuleId = $existingRuleId
        CandidateRuleId = $ruleId
        Status = $driftStatus
        ComparedBy = 'DeterministicGrammarAndRuleId'
        Adoption = 'NotApplied'
        ReviewRequired = $driftStatus -eq 'Detected'
    }
    $ruleVersion = if ($existingRuleVersion -gt 0 -and $existingRuleId -eq $ruleId) { $existingRuleVersion } elseif ($existingRuleVersion -gt 0) { $existingRuleVersion + 1 } else { 1 }

    $evidenceReferences = @($samples | ForEach-Object {
        [ordered]@{
            ExampleOrdinal = $_.Example.Ordinal
            SourceId = $_.Example.SourceId
            SourceFamily = $_.Example.SourceFamily
            EvidenceType = $_.Example.EvidenceType
            SourceRelationship = $_.Example.SourceRelationship
            Fingerprint = $_.Example.SafeFingerprint
            EvidenceReasonCodes = @($_.Example.EvidenceReasonCodes)
            ReasonCodes = @($_.ReasonCodes)
            Group = $_.Example.Group
            ChannelReference = $_.Example.ChannelReference
            FreshnessState = $_.Example.FreshnessState
            ConfidenceState = $_.Example.ConfidenceState
            EvidenceStartUtc = $_.Example.EvidenceStartUtc
            EvidenceEndUtc = $_.Example.EvidenceEndUtc
            SourceTimezone = $_.Example.SourceTimezone
        }
    })
    $rule = [GuideEventPatternRule]::new()
    $rule.RuleId = $ruleId
    $rule.RuleVersion = $ruleVersion
    $rule.Scope = $scope
    $rule.Grammar = $grammar
    $rule.FieldCandidates = @($fieldCandidates.ToArray())
    $rule.TimezoneInterpretation = $timezoneInterpretation
    $rule.EvidenceReferences = $evidenceReferences
    $rule.ConfidenceState = $state
    $rule.ConfidenceScore = $confidenceScore
    $rule.DriftStatus = $driftStatus
    $rule.BaselineRuleId = $existingRuleId
    $rule.DriftComparison = $driftComparison
    $rule.CrossSourceAssessment = $crossSourceAssessment
    $rule.ReasonCodes = @($allReasons | Sort-Object -Unique)
    $rule.RequiresReview = $state -ne 'Confirmed'
    $rule.AcceptedStateChanged = $false

    $reviewItems = [System.Collections.Generic.List[object]]::new()
    foreach ($reason in @($allReasons | Sort-Object -Unique)) {
        if ($reason -in @('EvidenceAgrees', 'AcceptedKnowledge', 'MetadataOnly')) { continue }
        switch ($reason) {
            'EvidenceContradicts' { $message = 'Timezone or schedule evidence resolves to different instants.' }
            'InvalidBaselineRule' { $message = 'The supplied baseline rule identifier is not a safe ChannelForge pattern identifier.' }
            'PatternDrift' { $message = 'The observed naming structure differs from the supplied rule or sample majority.' }
            'InconsistentExamples' { $message = 'Not every example fits one stable event-channel structure.' }
            'MissingTime' { $message = 'A critical event time is missing from one or more examples.' }
            'MissingDate' { $message = 'A critical event date is missing from one or more examples.' }
            'TimezoneUnresolved' { $message = 'A timezone label has no explicit safe mapping.' }
            'ReferenceInstantRequired' { $message = 'A yearless date needs an injected reference instant.' }
            'InsufficientExamples' { $message = "At least $MinimumExamples representative examples are required." }
            'EventFamilyConflict' { $message = 'Event-family evidence disagrees across the supplied inputs.' }
            'LeagueConflict' { $message = 'League evidence disagrees across the supplied inputs.' }
            'SportConflict' { $message = 'Sport evidence disagrees across the supplied inputs.' }
            'EvidenceMissing' { $message = 'A required identity or event field is missing.' }
            'AmbiguousTime' { $message = 'The date/time interpretation is ambiguous.' }
            'AmbiguousTitle' { $message = 'The event title is ambiguous.' }
            'NoEventData' { $message = 'The source did not provide event data for this candidate.' }
            'ScheduleChanged' { $message = 'The source reports a schedule change that requires review.' }
            'Postponed' { $message = 'The event is postponed; schedule-derived inference requires review.' }
            'Cancelled' { $message = 'The event is cancelled; schedule-derived inference requires review.' }
            'Rescheduled' { $message = 'The event is rescheduled; schedule-derived inference requires review.' }
            'InvalidDate' { $message = 'One or more date tokens are malformed or out of range.' }
            'InvalidTime' { $message = 'One or more time tokens are malformed or out of range.' }
            'TimezoneCrossCheckUnavailable' { $message = 'Duplicate timezone evidence was present but could not be normalized for comparison.' }
            'ConfidenceBelowThreshold' { $message = 'The candidate confidence is below the automatic confirmation threshold.' }
            'MirrorNotIndependent' { $message = 'Mirror sources are retained as provenance but are not counted as independent agreement.' }
            'SourceNeedsReview' { $message = 'An input source marked the evidence as requiring review.' }
            'SourceUnavailable' { $message = 'The source is unavailable; no candidate can be trusted automatically.' }
            'SourceStale' { $message = 'The source reports stale evidence; review is required before use.' }
            'StaleSource' { $message = 'The source is stale; review is required before use.' }
            default { $message = 'The supplied evidence needs review before this candidate can be used.' }
        }
        [void]$reviewItems.Add([ordered]@{ Code = $reason; Message = $message })
    }

    $preview = @($samples | ForEach-Object {
        [ordered]@{
            ExampleOrdinal = $_.Example.Ordinal
            Fingerprint = $_.Example.SafeFingerprint
            SourceId = $_.Example.SourceId
            SourceFamily = $_.Example.SourceFamily
            ChannelIdentifier = $_.ChannelIdentifier
            ChannelReference = $_.ChannelReference
            ChannelOrdinalText = $_.ChannelOrdinalText
            ChannelOrdinal = $_.ChannelOrdinal
            EventTitle = $_.EventTitle
            EventDate = $_.EventDate
            EventDateText = $_.EventDateText
            EventTimeText = $_.EventTimeText
            EventDayOfWeek = $_.EventDayOfWeek
            EventDayOfWeekFormat = $_.EventDayOfWeekFormat
            EventTime = $_.EventTimeText
            TimezoneLabels = @($_.TimezoneLabels)
            StartUtc = $_.CanonicalStartUtc
            StartTimeUtc = $_.CanonicalStartUtc
            EventStartUtc = $_.CanonicalStartUtc
            HomeParticipant = $_.HomeParticipant
            SourceTimezone = $_.SourceTimezone
            EventTimezone = $_.SourceTimezone
            AwayParticipant = $_.AwayParticipant
            League = if (-not [string]::IsNullOrEmpty($_.Example.League)) { $_.Example.League } else { $family.League }
            Sport = if (-not [string]::IsNullOrEmpty($_.Example.Sport)) { $_.Example.Sport } else { $family.Sport }
            EventFamily = $family.EventFamily
            EventType = $family.EventFamily
            EventStatus = $_.Example.EventStatus
            MatchState = $_.MatchState
            TimezoneCrossCheck = $_.TimezoneCrossCheck
            ReasonCodes = @($_.ReasonCodes)
        }
    })

    $volatileFacts = @($Examples | ForEach-Object { @($_.VolatileFacts) } | Where-Object { $null -ne $_ })
    $result = [GuidePatternInferenceResult]::new()
    $result.InferenceStatus = 'NativePatternCandidate'
    $result.OverallState = $state
    $result.DriftComparison = $driftComparison
    $result.Candidates = @($rule)
    $result.SelectedCandidate = if ($state -in @('Confirmed', 'SafeCandidate')) { $rule } else { $null }
    $result.ExtractionPreview = $preview
    $result.Examples = $evidenceReferences
    $result.ReviewItems = @($reviewItems.ToArray())
    $result.Provenance = $evidenceReferences
    $result.ExampleCount = $samples.Count
    $result.MatchedExampleCount = $matchedCount
    $result.ConfidenceScore = $confidenceScore
    $result.ConfidenceState = $state
    $result.DriftStatus = $driftStatus
    $result.BaselineRuleId = $existingRuleId
    $result.ReferenceInstantUtc = if ($null -ne $ReferenceInstantUtc) { $ReferenceInstantUtc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture) } else { '' }
    $result.VolatileFacts = @($volatileFacts)
    $result.CrossSourceAssessment = $crossSourceAssessment
    $result.AcceptedStatePreserved = @($samples | Where-Object { $_.Example.EvidenceType -eq 'AcceptedKnowledge' }).Count -gt 0
    $result.ReasonCodes = @($allReasons | Sort-Object -Unique)
    return $result
}
