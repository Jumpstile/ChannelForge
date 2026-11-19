function Test-ChannelForgeEventProviderError {
    # True when the text is the provider reporting an error ("No data", "Guide unavailable"), not an
    # event. Plain phrases from data\rules\event-provider-errors.json, whole words, any case.
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)
    if (-not $Text) { return $false }
    $path = Join-Path $PSScriptRoot '..\..\..\data\rules\event-provider-errors.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    foreach ($phrase in @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).phrases)) {
        $pattern = '(?<![\p{L}\p{N}])' + ([regex]::Escape($phrase) -replace '\\ ', '\s+') + '(?![\p{L}\p{N}])'
        if ([regex]::IsMatch($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) { return $true }
    }
    return $false
}

function Get-ChannelForgeEventPairKey {
    # Same-event key for one title. "A vs B" (also v, at, @) with both teams resolved by the team alias
    # data gives the sorted team pair; anything else is the plain title key. Unresolved teams are never guessed.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Title)
    $teamData = Join-Path $PSScriptRoot '..\..\..\data\rules\team-aliases.json'
    $match = [regex]::Match($Title, '^(.+?)\s+(?:vs\.?|v\.?|at|@)\s+(.+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success -and (Test-Path -LiteralPath $teamData -PathType Leaf)) {
        $a = Resolve-ChannelForgeTeamAlias -DataPath $teamData -Name $match.Groups[1].Value.Trim() -Opponent $match.Groups[2].Value.Trim()
        $b = Resolve-ChannelForgeTeamAlias -DataPath $teamData -Name $match.Groups[2].Value.Trim() -Opponent $match.Groups[1].Value.Trim()
        if ($a.Status -ceq 'Resolved' -and $b.Status -ceq 'Resolved') { return @{ Key = 'teams:' + ((@($a.Team, $b.Team) | Sort-Object) -join '|'); Label = 'Game' } }
    }
    @{ Key = 'title:' + (ConvertTo-ChannelForgeEventTitleKey -Text $Title); Label = 'Part' }
}

function Get-ChannelForgeEventDoubleheader {
    # Doubleheaders on one channel. Programme must be sorted by start (Title, Start, Stop; UTC). The same
    # teams or the same event name twice on one UTC day, in clear time order, get "Game 1"/"Game 2" or
    # "Part 1"/"Part 2". Anything unclear (three or more, a missing stop, overlap) gets no label and one
    # plain review question. Returns Label (start ticks -> prefix) and Review (strings). Pure.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Programme)
    $label = @{}; $review = [System.Collections.Generic.List[string]]::new()
    $groups = $Programme | Group-Object { $pair = Get-ChannelForgeEventPairKey -Title ([string]$_.Title); "$($_.Start.UtcDateTime.ToString('yyyyMMdd'))|$($pair.Key)" }
    foreach ($group in $groups | Where-Object { $_.Count -gt 1 }) {
        $rows = @($group.Group)
        $kind = (Get-ChannelForgeEventPairKey -Title ([string]$rows[0].Title)).Label
        $clear = $rows.Count -eq 2 -and $null -ne $rows[0].Stop -and $rows[0].Stop.UtcDateTime -le $rows[1].Start.UtcDateTime
        if (-not $clear) { [void]$review.Add("'$($rows[0].Title)' appears $($rows.Count) times on $($rows[0].Start.UtcDateTime.ToString('yyyy-MM-dd')) but the order or times are unclear. Which is which?"); continue }
        for ($i = 0; $i -lt 2; $i++) { $label[$rows[$i].Start.UtcDateTime.Ticks] = "$kind $($i + 1): " }
    }
    [pscustomobject]@{ Label = $label; Review = @($review.ToArray()) }
}
