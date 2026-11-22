[CmdletBinding()]
param(
    # Profile id, for example plex, iptvboss, dispatcharr.
    [Parameter(Mandatory)][string]$Profile,

    # The published M3U to preview. Read only; nothing is written.
    [Parameter(Mandatory)][string]$PlaylistPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ChannelForge\ChannelForge.psd1') -Force

$channels = @(Import-ChannelForgeM3UPlaylist -Path $PlaylistPath)
# The reader keeps tvg-chno as RawChannelNumber text; the exporter writes AssignedNumber.
foreach ($channel in $channels) {
    $number = 0
    if ([int]::TryParse([string]$channel.RawChannelNumber, [ref]$number)) { $channel.AssignedNumber = $number }
}

$report = & (Get-Module ChannelForge) { param($p, $c) Get-ChannelForgeTargetPreview -Profile $p -Channel $c } $Profile $channels
"Target preview: $($report.Profile) v$($report.Version), $($report.ChannelCount) channels (report only, nothing written)"
$report.Attributes | Format-Table Attribute, Status, ChannelsWithValue, Evidence, ProfileSays -AutoSize -Wrap | Out-String -Width 200
"Status unknown means no evidence. It is never treated as supported."
