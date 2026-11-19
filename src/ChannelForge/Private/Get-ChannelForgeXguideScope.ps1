function Get-ChannelForgeXguideScope {
    <#
    .SYNOPSIS
    Maps each build guide name to the playlist labels it serves, read from the saved source set (xguide-compare/v2).
    A build guide is matched to a saved guide by its address (public link) or by its file content, never by name.
    Returns $null (compare all guides, as in v1) unless the set is readable, has two or more enabled playlists
    with distinct labels, and every build guide matches exactly one distinct saved guide.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][object[]]$Guide
    )

    try { $set = Read-ChannelForgeSourceEnrollmentRecord -RepositoryRoot $RepositoryRoot } catch { return $null }
    $playlists = @($set.Playlists | Where-Object { [bool]$_.Enabled })
    $labels = @($playlists | ForEach-Object { [string]$_.Label })
    if ($playlists.Count -lt 2 -or $labels.Count -ne @($labels | Sort-Object -Unique -CaseSensitive).Count) { return $null }

    $saved = @($set.Guides | Where-Object { [bool]$_.Enabled })
    $scope = @{}
    $used = @{}
    foreach ($g in $Guide) {
        $name = [string]$g.Name
        $hash = ''
        if (-not [string]::IsNullOrWhiteSpace([string]$g.Path)) {
            try { $hash = Get-ChannelForgeSourceEnrollmentSourceHash -Bytes ([byte[]][IO.File]::ReadAllBytes([string]$g.Path)) } catch { return $null }
        }
        $match = @($saved | Where-Object {
                ($hash -ne '' -and [string]$_.SourceKind -ceq 'managed-file' -and [string]$_.ContentHash -ceq $hash) -or
                ($hash -eq '' -and -not [string]::IsNullOrWhiteSpace([string]$g.Url) -and [string]$_.SourceKind -ceq 'public-https' -and [string]$_.Url -ceq [string]$g.Url)
            })
        if ($match.Count -ne 1 -or $used.ContainsKey([string]$match[0].SourceId) -or $scope.ContainsKey($name)) { return $null }
        $used[[string]$match[0].SourceId] = 1
        $binding = @($set.Bindings | Where-Object { [string]$_.GuideId -ceq [string]$match[0].SourceId })[0]
        $served = if ($null -eq $binding -or -not [bool]$binding.Enabled -or ($null -ne $binding.PSObject.Properties['ExplicitlyUnbound'] -and [bool]$binding.ExplicitlyUnbound)) { @() }
        elseif ([bool]$binding.AppliesToAll) { $playlists }
        else { @($playlists | Where-Object { [string]$_.SourceId -cin @($binding.PlaylistIds | ForEach-Object { [string]$_ }) }) }
        $scope[$name] = [string[]]@($served | ForEach-Object { [string]$_.Label })
    }
    return $scope
}
