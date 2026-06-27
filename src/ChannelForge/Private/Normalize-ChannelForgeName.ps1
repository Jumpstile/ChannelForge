function Normalize-ChannelForgeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    # Channel names come from external playlists and are inconsistent.
    # Normalize only presentation noise here. Do not make category decisions here.
    $normalized = $Name.Trim()

    # Remove bracketed technical tags first.
    # This prevents values like [FHD] from becoming empty brackets after bare tag removal.
    $normalized = $normalized -replace '\[[^\]]*(FHD|UHD|HD|SD|4K|720p|1080p|HEVC|H265|H\.265)[^\]]*\]', ''
    $normalized = $normalized -replace '\([^\)]*(FHD|UHD|HD|SD|4K|720p|1080p|HEVC|H265|H\.265)[^\)]*\)', ''

    # Remove common quality labels that do not change channel identity.
    $normalized = $normalized -replace '\b(FHD|UHD|HD|SD|4K|720p|1080p|HEVC|H265|H\.265)\b', ''

    # Remove common backup/alternate markers while preserving meaningful names.
    $normalized = $normalized -replace '\b(Backup|Alt|Alternate)\b', ''

    # Collapse repeated whitespace created by removals.
    $normalized = $normalized -replace '\s+', ' '
    $normalized = $normalized.Trim()

    return $normalized
}