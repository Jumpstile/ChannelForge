function Write-ChannelForgeAdminPasswordFile {
    <#
    .SYNOPSIS
        Saves a protected sign-in file (default admin-password.json; users.json for the user store) in the config folder.
    .DESCRIPTION
        Reuses the engine's temp-file-then-replace writer. Returns Success and Category
        ('None', 'WriteFailed' or 'PermissionFailed'). The record is never printed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigRoot,
        [Parameter(Mandatory)]$Record,
        [ValidateSet('admin-password.json', 'users.json')][string]$FileName = 'admin-password.json'
    )

    $path = Join-Path $ConfigRoot $FileName
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes((ConvertTo-ChannelForgeCanonicalJson -InputObject $Record))
        Write-ChannelForgeSourceEnrollmentAtomicBytes -Path $path -Bytes $bytes -AllowedRoot $ConfigRoot
    }
    catch {
        return [pscustomobject]@{ Success = $false; Category = 'WriteFailed' }
    }
    try {
        if ($IsWindows) {
            $acl = [System.Security.AccessControl.FileSecurity]::new()
            $acl.SetAccessRuleProtection($true, $false)
            $admins = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
            foreach ($sid in @([System.Security.Principal.WindowsIdentity]::GetCurrent().User, $admins)) {
                $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, [System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow))
            }
            Set-Acl -LiteralPath $path -AclObject $acl -ErrorAction Stop
        }
        else {
            [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Category = 'PermissionFailed' }
    }
    return [pscustomobject]@{ Success = $true; Category = 'None' }
}
