function Read-ChannelForgeUserGuideEvidence {
    # Reads a second XMLTV guide the owner supplies, for FACTS ONLY: event title, teams (when the title
    # is "A vs B"), calendar day, start time and the guide's channel id. Description, subtitle and
    # categories are never copied. The guide is read with Read-ChannelForgeXmltvSourceFile, so size
    # limits and a damaged file behave as for any guide. A programme whose start or stop cannot be read is skipped.
    # Returns schedule evidence records (Source 'user-guide', Attribution = the file name only).
    # The provider guide is never changed. Pure apart from reading the file.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [long]$MaxDocumentBytes = 67108864
    )

    $attribution = [System.IO.Path]::GetFileName($Path)
    $programmes = @(Read-ChannelForgeXmltvSourceFile -Path $Path -SourceId 'user-guide' -MaxDocumentBytes $MaxDocumentBytes -CandidateContractVersion 'blocker-2-contract/v8' -SkipBadProgrammeTimes)
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    foreach ($programme in $programmes) {
        $title = ([string]$programme.Title).Trim()
        if (-not $title) { continue }
        $teams = [regex]::Match($title, '^(.+?)\s+(?:vs\.?|v\.?|at|@)\s+(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $homeTeam = ''; $away = ''
        if ($teams.Success) { $homeTeam = $teams.Groups[1].Value.Trim(); $away = $teams.Groups[2].Value.Trim() }
        $startUtc = $programme.Start.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $invariant)
        $day = [TimeZoneInfo]::ConvertTimeFromUtc($programme.Start.UtcDateTime, [TimeZoneInfo]::Local).ToString('yyyy-MM-dd', $invariant)
        $idBytes = [System.Text.Encoding]::UTF8.GetBytes(("$($programme.ChannelId)|$title|$startUtc").ToLowerInvariant())
        [pscustomobject][ordered]@{
            Id = 'userguide-' + ([System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($idBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 16))
            Sport = ''; Title = $title; Home = $homeTeam; Away = $away; Date = $day; StartUtc = $startUtc
            ChannelName = [string]$programme.ChannelId; Source = 'user-guide'; Attribution = $attribution
        }
    }
}

function ConvertTo-ChannelForgeUserGuideChannel {
    # Turns user-guide evidence records into detector-style channels (Key, DisplayName, Programmes with
    # Title and Start), one per guide channel, so Get-ChannelForgeEventTimeAgreement can compare them
    # with the provider guide. Pure.
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Evidence = @())

    foreach ($group in @($Evidence | Group-Object ChannelName | Sort-Object Name)) {
        $keyBytes = [System.Text.Encoding]::UTF8.GetBytes('user-guide|' + $group.Name)
        [pscustomobject][ordered]@{
            Key = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($keyBytes)).Replace('-', '').ToLowerInvariant()
            DisplayName = [string]$group.Name
            Programmes = @($group.Group | ForEach-Object { [pscustomobject]@{ Title = $_.Title; Start = [datetimeoffset]::Parse($_.StartUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal); Stop = $null } })
        }
    }
}
