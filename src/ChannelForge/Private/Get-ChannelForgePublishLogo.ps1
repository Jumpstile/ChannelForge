function Get-ChannelForgePublishLogo {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Channel = @(),

        [hashtable]$GroupDefaultLogo = @{}
    )

    # Group default logo (issue #191). Returns one object per channel, in
    # order: DisplayName, Logo (what to publish) and Replaced. A Public logo
    # is kept as is. Any other logo is replaced by the group default, or
    # published empty (no tvg-logo) when the group has none. Never drops a
    # channel and never changes the channel itself.
    $defaults = @{}
    foreach ($group in @($GroupDefaultLogo.Keys)) {
        $url = [string]$GroupDefaultLogo[$group]
        if ((Get-ChannelForgeLogoStatus -Url $url) -eq 'Public') {
            $defaults[[string]$group] = $url.Trim()
        }
        else {
            Write-Warning "Group default logo for '$group' ignored: it is not a public https link."
        }
    }

    foreach ($ch in @($Channel)) {
        $logo = [string]$ch.Logo
        $replaced = $false
        if ((Get-ChannelForgeLogoStatus -Url $logo) -ne 'Public') {
            $logo = ''
            if ($defaults.ContainsKey([string]$ch.Group)) {
                $logo = $defaults[[string]$ch.Group]
                $replaced = $true
            }
        }
        [pscustomobject]@{ DisplayName = [string]$ch.DisplayName; Logo = $logo; Replaced = $replaced }
    }
}
