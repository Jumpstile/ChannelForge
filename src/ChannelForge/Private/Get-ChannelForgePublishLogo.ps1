function Get-ChannelForgePublishLogo {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Channel = @(),

        [hashtable]$GroupDefaultLogo = @{},

        # TvgId -> public https link (Read-ChannelForgeLogoPin). Exact, case-sensitive.
        [hashtable]$LogoPin = @{},

        # Get-ChannelForgeLogoLookupMap result (logo-lookup/v1). Fills a gap only.
        [hashtable]$LogoLookup = @{}
    )

    # Group default logo (issue #191). Returns one object per channel, in
    # order: DisplayName, Logo (what to publish) and Replaced. A Public logo
    # is kept as is, unless a pin for the channel's TvgId exists (the pin wins). Any other logo is replaced by the group default, or
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

    $pins = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($id in @($LogoPin.Keys)) {
        $url = [string]$LogoPin[$id]
        if ((Get-ChannelForgeLogoStatus -Url $url) -eq 'Public') { $pins[[string]$id] = $url.Trim() }
    }

    $nameIds = Get-ChannelForgeLogoLookupNameIds -Channel $Channel -LogoLookup $LogoLookup
    foreach ($ch in @($Channel)) {
        $logo = [string]$ch.Logo
        $replaced = $false
        $pinned = $false
        $lookedUp = $false
        $ambiguous = $false
        $tvgId = [string]$ch.TvgId
        if ($tvgId.Length -gt 0 -and $pins.ContainsKey($tvgId)) {
            # Logo pin (logo-apply/v1): wins over a good public logo.
            $logo = $pins[$tvgId]
            $pinned = $true
        }
        elseif ((Get-ChannelForgeLogoStatus -Url $logo) -ne 'Public') {
            $logo = ''
            $found = Resolve-ChannelForgeLogoLookup -Channel $ch -LogoLookup $LogoLookup -NameIds $nameIds
            $ambiguous = $found.Ambiguous
            if ($found.Link.Length -gt 0) {
                $logo = $found.Link
                $lookedUp = $true
            }
            elseif ($defaults.ContainsKey([string]$ch.Group)) {
                $logo = $defaults[[string]$ch.Group]
                $replaced = $true
            }
        }
        [pscustomobject]@{ DisplayName = [string]$ch.DisplayName; Logo = $logo; Replaced = $replaced; TvgId = $tvgId; Pinned = $pinned; LookedUp = $lookedUp; LookupAmbiguous = $ambiguous }
    }
}

function Resolve-ChannelForgeLogoLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Channel,
        [hashtable]$LogoLookup = @{},

        # Name key -> guide ids of the channels in this build (built by the caller once).
        [hashtable]$NameIds = @{}
    )

    # logo-lookup/v1 rules 3 and 4, exact matches only. Returns Link ('' when none)
    # and Ambiguous. Rule 3: TvgId is a key in ById. Rule 4: the lower-cased
    # normalized name is a key in ByName. A name is ambiguous when channels with
    # different guide ids share it, or the file has no single link for it.
    $none = [pscustomobject]@{ Link = ''; Ambiguous = $false }
    if (-not ($LogoLookup.ById.Count -or $LogoLookup.ByName.Count -or $LogoLookup.Ambiguous.Count)) { return $none }

    $tvgId = [string]$Channel.TvgId
    if ($tvgId.Length -gt 0 -and $LogoLookup.ById.ContainsKey($tvgId)) {
        return [pscustomobject]@{ Link = [string]$LogoLookup.ById[$tvgId]; Ambiguous = $false }
    }
    $key = ConvertTo-ChannelForgeLogoLookupNameKey -Name ([string]$Channel.DisplayName)
    if ($key.Length -eq 0) { return $none }
    $multiple = $LogoLookup.Ambiguous.Contains($key)
    if (-not $multiple -and -not $LogoLookup.ByName.ContainsKey($key)) { return $none }
    if ($multiple -or $NameIds[$key].Count -gt 1) { return [pscustomobject]@{ Link = ''; Ambiguous = $true } }
    return [pscustomobject]@{ Link = [string]$LogoLookup.ByName[$key]; Ambiguous = $false }
}

function Get-ChannelForgeLogoLookupNameIds {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][AllowNull()][object[]]$Channel = @(),
        [hashtable]$LogoLookup = @{}
    )

    # Name key -> set of TvgIds, over every channel in this build. Empty when the
    # file has no name entries, so a build with no lookup pays nothing.
    $ids = @{}
    if (-not $LogoLookup.ByName.Count) { return $ids }
    foreach ($ch in @($Channel)) {
        $key = ConvertTo-ChannelForgeLogoLookupNameKey -Name ([string]$ch.DisplayName)
        if ($key.Length -eq 0) { continue }
        if (-not $ids.ContainsKey($key)) { $ids[$key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal) }
        [void]$ids[$key].Add([string]$ch.TvgId)
    }
    return $ids
}

function ConvertTo-ChannelForgeLogoLookupNameKey {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Name)

    # logo-lookup/v1 ByName key: Normalize-ChannelForgeName, then lower-cased
    # with the invariant culture. Case is the only extra fold. Empty in, empty out.
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    return (Normalize-ChannelForgeName -Name $Name).ToLowerInvariant()
}
