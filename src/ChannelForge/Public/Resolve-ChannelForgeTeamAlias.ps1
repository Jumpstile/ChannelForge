function Resolve-ChannelForgeTeamAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Sport = '',
        [string]$League = '',
        [string]$Group = '',
        [string]$Opponent = '',

        [string]$DataPath = (Join-Path $PSScriptRoot '..\..\..\data\rules\team-aliases.json')
    )

    # A team name shared by several leagues is resolved only when the context
    # leaves exactly one league. Anything else is a Review result, never a guess.
    if (-not (Test-Path -LiteralPath $DataPath -PathType Leaf)) {
        throw "Team alias file not found: $DataPath"
    }
    $data = Get-Content -LiteralPath $DataPath -Raw | ConvertFrom-Json

    function ConvertTo-TeamKey([string]$Text) {
        if (-not $Text) { return ' ' }
        (' ' + ((Normalize-ChannelForgeName -Name $Text).ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() + ' ')
    }
    function Find-TeamEntry([string]$Text) {
        $key = ConvertTo-TeamKey $Text
        @($data.teams | Where-Object {
                $names = @($_.team) + @($_.aliases)
                @($names | Where-Object { (ConvertTo-TeamKey $_) -eq $key }).Count -gt 0
            })
    }
    function Get-ClueLeague([string]$Text) {
        $key = ConvertTo-TeamKey $Text
        @($data.clues | Where-Object { $key.Contains((ConvertTo-TeamKey $_.text)) } | ForEach-Object { $_.leagues } | Select-Object -Unique)
    }

    $candidates = @(Find-TeamEntry $Name)
    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            Status = 'Review'; Team = $null; League = $null; Sport = $null; Candidates = @(); Evidence = @()
            Reason = "Team name '$Name' is not in the team alias data. A person needs to say which team this is."
        }
    }

    # Each context source narrows the leagues. A source with no clue says nothing.
    $sources = [ordered]@{
        Sport    = @(Get-ClueLeague $Sport)
        League   = @(Get-ClueLeague $League)
        Group    = @(Get-ClueLeague $Group)
        Opponent = @(if ($Opponent) { Find-TeamEntry $Opponent | ForEach-Object { $_.league } | Select-Object -Unique })
    }
    $evidence = [System.Collections.Generic.List[object]]::new()
    $survivors = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $candidates) {
        $rejected = $false
        foreach ($source in $sources.Keys) {
            $leagues = @($sources[$source])
            if ($leagues.Count -eq 0) { continue }
            $fits = $leagues -contains $candidate.league
            $kind = if ($fits) { 'Positive' } else { 'Negative' }
            if (-not $fits) { $rejected = $true }
            $evidence.Add([pscustomobject]@{
                    Candidate = $candidate.team; Kind = $kind; Source = $source
                    Detail    = "$source points to $($leagues -join '/'); $($candidate.team) plays in $($candidate.league)."
                })
        }
        if (-not $rejected) { $survivors.Add($candidate) }
    }

    # Two context sources that name no league in common contradict each other.
    $named = @($sources.Keys | Where-Object { @($sources[$_]).Count -gt 0 })
    for ($i = 0; $i -lt $named.Count; $i++) {
        for ($j = $i + 1; $j -lt $named.Count; $j++) {
            $a = @($sources[$named[$i]]); $b = @($sources[$named[$j]])
            if (@($a | Where-Object { $b -contains $_ }).Count -eq 0) {
                $evidence.Add([pscustomobject]@{
                        Candidate = $null; Kind = 'Conflicting'; Source = "$($named[$i])+$($named[$j])"
                        Detail    = "$($named[$i]) points to $($a -join '/') but $($named[$j]) points to $($b -join '/')."
                    })
            }
        }
    }
    $conflict = @($evidence | Where-Object { $_.Kind -eq 'Conflicting' }).Count -gt 0

    $shown = @($candidates | ForEach-Object { [pscustomobject]@{ Team = $_.team; League = $_.league; Sport = $_.sport } })
    if ($survivors.Count -eq 1 -and -not $conflict) {
        $team = $survivors[0]
        return [pscustomobject]@{
            Status = 'Resolved'; Team = $team.team; League = $team.league; Sport = $team.sport
            Candidates = $shown; Evidence = $evidence.ToArray(); Reason = ''
        }
    }

    $reason = if ($conflict) { "The clues for '$Name' disagree with each other. A person needs to pick the team." }
    elseif ($survivors.Count -eq 0) { "None of the teams called '$Name' fit the clues. A person needs to pick the team." }
    else { "'$Name' could be $(($survivors | ForEach-Object { $_.team }) -join ' or '). Add a league or sport clue, or pick the team." }
    [pscustomobject]@{
        Status = 'Review'; Team = $null; League = $null; Sport = $null
        Candidates = $shown; Evidence = $evidence.ToArray(); Reason = $reason
    }
}
