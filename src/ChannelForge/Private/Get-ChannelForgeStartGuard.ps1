function Get-ChannelForgeStartGuard {
    <#
    .SYNOPSIS
        Decides whether the server may listen on an address. Never throws; never returns secrets.
    .DESCRIPTION
        Loopback (localhost, 127.x.x.x, ::1) is always Ready, with no password needed.
        Any other address needs a good admin password file in the config folder.
        With no password, the result is Refused, or SetupRequired when -AllowSetupMode is given
        (the caller then serves only the first-run page and a data-free health check).
        A corrupt password file is always Refused and is never touched.
        Returns State ('Ready', 'SetupRequired' or 'Refused') and a plain Reason.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Address,
        [Parameter(Mandatory)][string]$ConfigRoot,
        [switch]$AllowSetupMode
    )

    $hostName = $Address.Trim().Trim('[', ']')
    $ip = $null
    $isLoopback = $hostName -eq 'localhost' -or ([System.Net.IPAddress]::TryParse($hostName, [ref]$ip) -and [System.Net.IPAddress]::IsLoopback($ip))
    if ($isLoopback) {
        return [pscustomobject]@{ State = 'Ready'; Reason = '' }
    }

    $refusal = 'ChannelForge will not listen on the network without a password. Run first-time setup, or turn off network access.'
    switch ((Read-ChannelForgeAdminPasswordFile -ConfigRoot $ConfigRoot).Status) {
        'Ok' { return [pscustomobject]@{ State = 'Ready'; Reason = '' } }
        'Corrupt' { return [pscustomobject]@{ State = 'Refused'; Reason = "The saved password file is damaged. $refusal" } }
        default {
            if ($AllowSetupMode) { return [pscustomobject]@{ State = 'SetupRequired'; Reason = 'No password is set up yet. Only first-time setup is available.' } }
            return [pscustomobject]@{ State = 'Refused'; Reason = $refusal }
        }
    }
}
