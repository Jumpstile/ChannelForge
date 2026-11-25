function Read-ChannelForgeAdminPasswordFile {
    <#
    .SYNOPSIS
        Reads admin-password.json. Never throws. Returns Status ('Missing', 'Ok' or 'Corrupt') and Record.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigRoot)

    $path = Join-Path $ConfigRoot 'admin-password.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Status = 'Missing'; Record = $null }
    }
    try {
        $record = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
        if ([int]$record.Schema -ne 1 -or [string]::IsNullOrEmpty([string]$record.Salt) -or [string]::IsNullOrEmpty([string]$record.Hash)) {
            return [pscustomobject]@{ Status = 'Corrupt'; Record = $null }
        }
        return [pscustomobject]@{ Status = 'Ok'; Record = $record }
    }
    catch {
        return [pscustomobject]@{ Status = 'Corrupt'; Record = $null }
    }
}
