function Get-ChannelForgeCredentialRoot {
    [CmdletBinding()]
    param()

    return (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ChannelForge\credentials')
}
