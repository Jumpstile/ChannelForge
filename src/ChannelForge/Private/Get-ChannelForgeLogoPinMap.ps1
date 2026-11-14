function Get-ChannelForgeLogoPinMap {
    [CmdletBinding()]
    param([string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot))

    # logo-apply/v1: one read per build. Returns an exact, case-sensitive
    # TvgId -> link map. A missing file gives an empty map. A corrupt file
    # gives an empty map and a loud warning. Never throws, never writes.
    $map = [hashtable]::new([System.StringComparer]::Ordinal)
    $read = Read-ChannelForgeLogoPin -RepositoryRoot $RepositoryRoot
    if ($read.Status -eq 'Corrupt') {
        Write-Warning "Logo pins unreadable: $(@($read.Problems) -join '; '). No pin was applied."
    }
    else {
        foreach ($pin in @($read.Pins)) { $map[[string]$pin.TvgId] = [string]$pin.Logo }
    }
    return $map
}
