function Test-ChannelForgeElevated {
    <#
    .SYNOPSIS
        True when the process may run the server-side reset. On Windows that means administrator; elsewhere the file permissions decide.
    #>
    [CmdletBinding()]
    param()
    # Windows PowerShell 5.1 has no $IsWindows variable; it only runs on Windows.
    $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
    if (-not $onWindows) { return $true }
    $principal = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
