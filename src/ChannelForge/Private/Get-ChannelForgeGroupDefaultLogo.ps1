function Get-ChannelForgeGroupDefaultLogo {
    [CmdletBinding()]
    param([AllowNull()][object]$ProviderConfig)

    # Reads the optional group_default_logo map (group name -> URL) from a
    # parsed provider config. Values are checked later by
    # Get-ChannelForgePublishLogo.
    $map = @{}
    if ($null -ne $ProviderConfig -and $ProviderConfig.PSObject.Properties['group_default_logo']) {
        foreach ($entry in $ProviderConfig.group_default_logo.PSObject.Properties) { $map[$entry.Name] = [string]$entry.Value }
    }
    return $map
}
