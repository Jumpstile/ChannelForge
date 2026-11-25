function Remove-ChannelForgeAdminPasswordFile {
    <#
    .SYNOPSIS
        Deletes admin-password.json only. Touches no other file.
    .DESCRIPTION
        Returns Success and Category ('None', 'Missing' or 'DeleteFailed').
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigRoot)

    $path = Join-Path $ConfigRoot 'admin-password.json'
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
