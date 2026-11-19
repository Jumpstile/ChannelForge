function Get-ChannelForgeLogoPin {
    <#
    .SYNOPSIS
    Lists the stored channel logo pins (state\logo-pins.json, logo-identity/v1).
    .DESCRIPTION
    Pins are applied to builds: a pinned logo link is used for that channel when a
    lineup is built. A missing file returns nothing and creates nothing.
    A corrupt file gives a warning with the reason, returns nothing and is
    left as it is.
    #>
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $stored = Read-ChannelForgeLogoPin -RepositoryRoot $RepositoryRoot
    if ($stored.Status -eq 'Corrupt') {
        Write-Warning "Logo pins unreadable: $($stored.Problems -join '; '). The file was not changed."
        return
    }
    $stored.Pins | Select-Object TvgId, Logo, PinnedAtUtc, Note
}
