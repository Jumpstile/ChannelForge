function Get-ChannelForgeTargetPreview {
    # Report only. Compares the final lineup with what one compatibility profile says the
    # target accepts. Writes nothing and never changes a channel. Unknown stays "unknown".
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
        [string]$Profile,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [Channel[]]$Channel,

        # Optional profile file instead of data\compatibility\<Profile>.profile.json.
        [string]$ProfilePath
    )

    $profilePath = if ($ProfilePath) { $ProfilePath } else { Join-Path $PSScriptRoot "..\..\..\data\compatibility\$Profile.profile.json" }
    $loaded = Get-ChannelForgeCompatibilityProfile -Path $profilePath

    # M3U attribute -> profile capability -> channel has a value to write (same fields as ConvertTo-ChannelForgeM3UEntryBytes).
    $attributes = @(
        @{ Attribute = 'tvg-id'; Capability = 'tvg_id'; Has = { param($c) $c.TvgId } }
        @{ Attribute = 'tvg-name'; Capability = 'tvg_name'; Has = { param($c) $c.TvgName } }
        @{ Attribute = 'tvg-logo'; Capability = 'tvg_logo'; Has = { param($c) $c.Logo } }
        @{ Attribute = 'tvg-chno'; Capability = 'tvg_chno'; Has = { param($c) $c.AssignedNumber } }
        @{ Attribute = 'group-title'; Capability = 'group_title'; Has = { param($c) $c.Group } }
    )

    $rows = foreach ($attribute in $attributes) {
        $entry = $loaded.capabilities.($attribute.Capability)
        $state = [string]$entry.evidence.state
        $present = @($Channel | Where-Object { & $attribute.Has $_ }).Count
        # Only the profile's own words can say "ignored". No evidence means unknown, never supported.
        $status = if ($state -eq 'unknown') { 'unknown' }
        elseif ($entry.value -match '^(?i)(ignored|not supported|dropped)') { 'would-be-ignored' }
        else { 'per-profile' }
        [pscustomobject]@{
            Attribute       = $attribute.Attribute
            Status          = $status
            ChannelsWithValue = $present
            Evidence        = $state
            ProfileSays     = [string]$entry.value
        }
    }

    [pscustomobject]@{
        Profile      = [string]$loaded.id
        Version      = [string]$loaded.version
        ChannelCount = @($Channel).Count
        Attributes   = @($rows)
    }
}
