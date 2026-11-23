function Remove-ChannelForgeSourceSecret {
    <#
    .SYNOPSIS
        Deletes the one secret file named by a ref id. Touches no other file.
    .DESCRIPTION
        Returns Success and Category ('None', 'Missing' or 'DeleteFailed').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{32}$')]
        [string]$RefId,

        [string]$CredentialRoot = (Get-ChannelForgeCredentialRoot)
    )

    $path = Join-Path $CredentialRoot ('{0}.cred' -f $RefId)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Success = $false; Category = 'Missing' }
    }
    try {
        Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        return [pscustomobject]@{ Success = $true; Category = 'None' }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Category = 'DeleteFailed' }
    }
}
