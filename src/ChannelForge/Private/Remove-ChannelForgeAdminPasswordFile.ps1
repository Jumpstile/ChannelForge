function Remove-ChannelForgeAdminPasswordFile {
    <#
    .SYNOPSIS
        Deletes one sign-in file (default admin-password.json; users.json when asked). Touches no other file.
    .DESCRIPTION
        Returns Success and Category ('None', 'Missing' or 'DeleteFailed').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigRoot,
        [ValidateSet('admin-password.json', 'users.json')][string]$FileName = 'admin-password.json'
    )

    $path = Join-Path $ConfigRoot $FileName
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
