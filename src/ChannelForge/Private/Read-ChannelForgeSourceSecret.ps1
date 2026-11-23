function Read-ChannelForgeSourceSecret {
    <#
    .SYNOPSIS
        Reads one DPAPI-protected secret by ref id.
    .DESCRIPTION
        Returns Success, Category and Secret (a SecureString, or $null on failure).
        Category is 'None', 'Missing', 'Corrupt' or 'Undecryptable'. Messages never carry paths or the secret.
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
        return [pscustomobject]@{ Success = $false; Category = 'Missing'; Secret = $null }
    }

    try {
        $record = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -ErrorAction Stop
        if ($record.FormatVersion -ne 1 -or [string]::IsNullOrEmpty([string]$record.Secret)) { throw 'bad record' }
        $encrypted = [string]$record.Secret
    }
    catch {
        return [pscustomobject]@{ Success = $false; Category = 'Corrupt'; Secret = $null }
    }

    try {
        $secret = ConvertTo-SecureString -String $encrypted -ErrorAction Stop
        return [pscustomobject]@{ Success = $true; Category = 'None'; Secret = $secret }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Category = 'Undecryptable'; Secret = $null }
    }
}
