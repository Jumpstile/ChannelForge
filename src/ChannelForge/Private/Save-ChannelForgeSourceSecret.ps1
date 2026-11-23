function Save-ChannelForgeSourceSecret {
    <#
    .SYNOPSIS
        Saves one secret as a DPAPI-protected file named by a new random ref id.
    .DESCRIPTION
        Returns Success, Category and RefId. Category is 'None' or 'WriteFailed'.
        The secret is never written in clear text and never appears in output or errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [securestring]$Secret,

        [string]$CredentialRoot = (Get-ChannelForgeCredentialRoot)
    )

    $refId = [System.Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)).ToLowerInvariant()
    $tempPath = $null
    try {
        if (-not (Test-Path -LiteralPath $CredentialRoot -PathType Container)) {
            $folder = New-Item -ItemType Directory -Path $CredentialRoot -Force
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $acl.SetAccessRuleProtection($true, $false)
            $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow)
            $acl.AddAccessRule($rule)
            Set-Acl -LiteralPath $folder.FullName -AclObject $acl
        }

        $record = [ordered]@{ FormatVersion = 1; Secret = (ConvertFrom-SecureString -SecureString $Secret) } | ConvertTo-Json -Compress
        $tempPath = Join-Path $CredentialRoot ('{0}.tmp' -f $refId)
        [System.IO.File]::WriteAllText($tempPath, $record, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tempPath -Destination (Join-Path $CredentialRoot ('{0}.cred' -f $refId)) -ErrorAction Stop
        $tempPath = $null
        return [pscustomobject]@{ Success = $true; Category = 'None'; RefId = $refId }
    }
    catch {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{ Success = $false; Category = 'WriteFailed'; RefId = $null }
    }
}
