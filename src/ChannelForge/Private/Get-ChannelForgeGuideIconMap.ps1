function Get-ChannelForgeGuideIconMap {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$ExactBinding = @(),

        [hashtable]$GroupDefaultLogo = @{},

        [hashtable]$LogoPin = @{}
    )

    # Guide file logos (issue #191): XMLTV channel reference -> the same public https
    # logo the playlist publishes for the exactly bound channel (Get-ChannelForgePublishLogo
    # decides; nothing is copied). Channels left with no logo have no entry.
    $map = [hashtable]::new([System.StringComparer]::Ordinal)
    $bindings = @($ExactBinding | Where-Object { $null -ne $_ -and $null -ne $_.M3UChannel })
    if ($bindings.Count -eq 0) { return , $map }

    $published = @(Get-ChannelForgePublishLogo -Channel @($bindings | ForEach-Object { $_.M3UChannel }) -GroupDefaultLogo $GroupDefaultLogo -LogoPin $LogoPin)
    for ($i = 0; $i -lt $bindings.Count; $i++) {
        $ref = [string]$bindings[$i].XmltvChannelId
        $logo = [string]$published[$i].Logo
        if ($ref.Length -gt 0 -and $logo.Length -gt 0 -and -not $map.ContainsKey($ref)) { $map[$ref] = $logo }
    }
    return , $map
}
