function Set-ChannelForgeLogoPin {
    <#
    .SYNOPSIS
    Pins a logo link to one channel, or removes a pin (state\logo-pins.json, logo-identity/v1).
    .DESCRIPTION
    The channel is matched by exact, case-sensitive TvgId. The link must be a
    public https link without a user name or password. Nothing is fetched.
    Pins are stored but not yet applied to builds, and the build report does
    not mention them yet. A corrupt pin file is never overwritten: the command
    refuses and the file stays as it is.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Set')]
    param(
        [Parameter(Mandatory)][string]$TvgId,
        [Parameter(Mandatory, ParameterSetName = 'Set')][string]$Logo,
        [Parameter(ParameterSetName = 'Set')][string]$Note = '',
        [Parameter(Mandatory, ParameterSetName = 'Remove')][switch]$Remove,
        [string]$RepositoryRoot = (Get-ChannelForgeWebRepositoryRoot)
    )

    $stored = Read-ChannelForgeLogoPin -RepositoryRoot $RepositoryRoot
    if ($stored.Status -eq 'Corrupt') {
        throw "Logo pins unreadable: $($stored.Problems -join '; '). Nothing was changed."
    }
    $others = @($stored.Pins | Where-Object { $_.TvgId -cne $TvgId })

    if ($Remove) {
        if ($others.Count -eq $stored.Pins.Count) {
            Write-Information "No pin exists for '$TvgId'. Nothing to remove." -InformationAction Continue
            return
        }
        $pins = $others
        $pin = $null
    }
    else {
        if ($TvgId.Length -lt 1 -or $TvgId.Length -gt 256 -or $TvgId -match '[\x00-\x1f\x7f]') { throw 'TvgId must be 1 to 256 characters with no control characters.' }
        if ($Note.Length -gt 200) { throw 'Note must be 200 characters or fewer.' }
        $problem = Get-ChannelForgeLogoPinLinkProblem -Logo $Logo
        if ($problem) { throw "Pin refused: $problem." }
        $pin = [pscustomobject][ordered]@{ TvgId = $TvgId; Logo = $Logo; Source = 'user'; PinnedAtUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); Note = $Note }
        $pins = @($others) + $pin
    }

    $ordered = [System.Collections.Generic.List[object]]::new([object[]]@($pins))
    $ordered.Sort([System.Comparison[object]]{ param($a, $b) [string]::CompareOrdinal($a.TvgId, $b.TvgId) })
    $root = (Get-ChannelForgeSourceEnrollmentPaths -RepositoryRoot $RepositoryRoot).StateRoot
    try {
        Write-ChannelForgeSourceEnrollmentAtomicJson -Path $stored.Path -AllowedRoot $root -Value ([ordered]@{ Version = 'logo-identity/v1'; Pins = $ordered.ToArray() })
    }
    catch {
        throw "Could not save the logo pins: $($_.Exception.Message) The old file was left as it was."
    }
    return $pin
}
